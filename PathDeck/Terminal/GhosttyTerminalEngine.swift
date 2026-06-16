import AppKit
import GhosttyKit

final class GhosttyTerminalEngine: TerminalEngine {
    var onSessionClose: ((UUID) -> Void)?
    var onCwdChange: ((UUID, URL) -> Void)?
    var onPendingDropped: ((UUID, Int, PendingDropReason) -> Void)?

    private let engineID = ObjectIdentifier(UUID.self as Any.Type)
    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]
    /// internal（非 private）以便 @testable 断言 pending 状态（S19 测试缝）。
    var pendingBuffers: [UUID: PendingTextBuffer] = [:]
    var pendingTimeoutTokens: [UUID: UUID] = [:]
    private var observer: NSObjectProtocol?
    private let registrationID: ObjectIdentifier

    init() {
        let sentinel = NSObject()
        registrationID = ObjectIdentifier(sentinel)

        observer = NotificationCenter.default.addObserver(
            forName: .ghosttySurfaceDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSurfaceClose()
        }

        GhosttyApp.shared.registerPwdHandler(id: registrationID) { [weak self] surface, pwd in
            self?.handlePwdChange(surface: surface, pwd: pwd)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        GhosttyApp.shared.unregisterPwdHandler(id: registrationID)
    }

    func createSession(cwd: URL) -> UUID {
        let id = UUID()
        sessionCwds[id] = cwd
        return id
    }

    func closeSession(_ id: UUID) {
        surfaceViews.removeValue(forKey: id)
        sessionCwds.removeValue(forKey: id)
        pendingBuffers.removeValue(forKey: id)
        cancelPendingTimeout(id)
    }

    func terminalView(for id: UUID) -> NSView {
        if let existing = surfaceViews[id] { return existing }
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = sessionCwds[id]
        view.onSurfaceReady = { [weak self] in
            self?.flushPendingTexts(for: id)
        }
        view.onSurfaceFailed = { [weak self] reason in
            self?.handleSurfaceCreationFailure(id: id, reason: reason)
        }
        surfaceViews[id] = view
        return view
    }

    func writeText(_ text: String, to id: UUID) {
        if let view = surfaceViews[id], view.surface != nil {
            view.insertText(text)
        } else {
            let result = pendingBuffers[id, default: PendingTextBuffer()].enqueue(text)
            if !result.droppedFromOverflow.isEmpty {
                onPendingDropped?(id, result.droppedFromOverflow.count, .overflow)
            }
            schedulePendingTimeout(for: id)
        }
    }

    private func flushPendingTexts(for id: UUID) {
        cancelPendingTimeout(id)
        guard var buffer = pendingBuffers.removeValue(forKey: id),
              let view = surfaceViews[id] else { return }
        for text in buffer.drain() {
            view.insertText(text)
        }
    }

    /// surface 创建失败：立即显式丢弃 pending 并上报，不再等盲目超时。
    private func handleSurfaceCreationFailure(id: UUID, reason: SurfaceFailureReason) {
        cancelPendingTimeout(id)
        guard var buffer = pendingBuffers.removeValue(forKey: id) else { return }
        let dropped = buffer.drain()
        if !dropped.isEmpty {
            onPendingDropped?(id, dropped.count, .surfaceCreationFailed)
        }
    }

    private func schedulePendingTimeout(for id: UUID) {
        let token = UUID()
        pendingTimeoutTokens[id] = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.pendingTimeoutTokens[id] == token else { return }
            self.pendingTimeoutTokens.removeValue(forKey: id)
            guard var buffer = self.pendingBuffers.removeValue(forKey: id) else { return }
            let dropped = buffer.drain()
            if !dropped.isEmpty {
                self.onPendingDropped?(id, dropped.count, .timeout)
            }
        }
    }

    private func cancelPendingTimeout(_ id: UUID) {
        pendingTimeoutTokens.removeValue(forKey: id)
    }

    private func handleSurfaceClose() {
        let states = surfaceViews.compactMap { id, view -> (id: UUID, exited: Bool)? in
            guard let surface = view.surface else { return nil }
            return (id, ghostty_surface_process_exited(surface))
        }
        // 先收集全部已退出 id 再回调：onSessionClose 会改 surfaceViews，避免遍历中改集合。
        for id in Self.exitedSessionIDs(from: states) {
            onSessionClose?(id)
        }
    }

    /// 从 (id, 是否已退出) 快照挑出全部已退出 session（纯函数，脱离 libghostty 可单测）。
    static func exitedSessionIDs(from states: [(id: UUID, exited: Bool)]) -> [UUID] {
        states.filter { $0.exited }.map { $0.id }
    }

    private func handlePwdChange(surface: ghostty_surface_t, pwd: String) {
        for (id, view) in surfaceViews {
            guard view.surface == surface else { continue }
            let url: URL
            if pwd.hasPrefix("file://") {
                guard let parsed = URL(string: pwd) else { return }
                url = URL(fileURLWithPath: parsed.path).standardizedFileURL
            } else if let decoded = pwd.removingPercentEncoding {
                url = URL(fileURLWithPath: decoded).standardizedFileURL
            } else {
                url = URL(fileURLWithPath: pwd).standardizedFileURL
            }
            onCwdChange?(id, url)
            return
        }
    }
}
