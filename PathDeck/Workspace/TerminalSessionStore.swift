import Foundation
import Observation

/// 单个 NSWindow workspace 持有的 terminal session 数组（@Observable）。
/// session 顺序就是 terminal tab bar 顺序；activeTerminalID 在 WorkspaceViewState。
@Observable
final class TerminalSessionStore {
    private(set) var sessions: [TerminalSession] = []

    func contains(_ id: UUID) -> Bool {
        sessions.contains { $0.id == id }
    }

    func session(_ id: UUID) -> TerminalSession? {
        sessions.first { $0.id == id }
    }

    var allIDs: Set<UUID> { Set(sessions.map(\.id)) }

    func append(_ session: TerminalSession) {
        sessions.append(session)
    }

    @discardableResult
    func remove(_ id: UUID) -> Int? {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        sessions.remove(at: idx)
        return idx
    }

    func rename(_ id: UUID, to title: String, manual: Bool) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        if manual && title.isEmpty {
            // 清 manual flag 并回到 cwd 名作为默认标题，下次 OSC title 到来时会自动覆盖。
            sessions[idx].isManuallyRenamed = false
            sessions[idx].title = sessions[idx].currentCwd.lastPathComponent
            return
        }
        sessions[idx].title = title
        if manual {
            sessions[idx].isManuallyRenamed = true
        }
    }

    func updateCwd(_ id: UUID, to url: URL) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].currentCwd = url
    }

    func move(source: UUID, to destinationIndex: Int) -> Bool {
        guard let from = sessions.firstIndex(where: { $0.id == source }) else { return false }
        let before = sessions.map(\.id)
        sessions.moveElement(from: from, to: destinationIndex)
        return sessions.map(\.id) != before
    }
}
