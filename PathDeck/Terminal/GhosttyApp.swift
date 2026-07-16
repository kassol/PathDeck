//
//  GhosttyApp.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import AppKit
import Foundation
import GhosttyKit

/// 进程级 libghostty runtime 单例（S2 冒烟）。
///
/// 职责仅限：初始化 libghostty、持有 `ghostty_app_t`、把 I/O 线程触发的 wakeup
/// 合并成主线程的一次 `ghostty_app_tick`。渲染由 libghostty 内部 CVDisplayLink 自驱，
/// 本类不涉及绘制。详见 `Terminal/AGENTS.md`。
///
/// 标 `nonisolated`：本类是 C runtime 桥，与 `MainActor` 无关；`wakeup_cb` 会在
/// libghostty 的 I/O 线程调用 `scheduleTick`，故不能受主 actor 隔离约束。
/// `@unchecked Sendable`：可变状态由 `tickLock` 保护，`app`/`config` 仅在主线程读写。
nonisolated final class GhosttyApp: @unchecked Sendable {
    static let shared = GhosttyApp()

    /// 初始化成功后非 nil；surface 创建依赖它。
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?

    private let tickLock = NSLock()
    private var tickScheduled = false

    private let handlersLock = NSLock()
    private var pwdHandlers: [ObjectIdentifier: (ghostty_surface_t, String) -> Void] = [:]
    private var titleHandlers: [ObjectIdentifier: (ghostty_surface_t, String) -> Void] = [:]
    private var fileURLHandlers: [ObjectIdentifier: (ghostty_surface_t, URL) -> Void] = [:]

    func registerPwdHandler(id: ObjectIdentifier, handler: @escaping (ghostty_surface_t, String) -> Void) {
        handlersLock.lock(); defer { handlersLock.unlock() }
        pwdHandlers[id] = handler
    }

    func unregisterHandlers(id: ObjectIdentifier) {
        handlersLock.lock(); defer { handlersLock.unlock() }
        pwdHandlers.removeValue(forKey: id)
        titleHandlers.removeValue(forKey: id)
        fileURLHandlers.removeValue(forKey: id)
    }

    func registerTitleHandler(id: ObjectIdentifier, handler: @escaping (ghostty_surface_t, String) -> Void) {
        handlersLock.lock(); defer { handlersLock.unlock() }
        titleHandlers[id] = handler
    }

    /// OPEN_URL 的 file:// 改道订阅（FR-BRIDGE-003 #6）：file:// 按本地路径走 Locate，
    /// 绝不 NSWorkspace.open（ADR-0003）。覆盖 OSC 8 href 为 file:// 而显示文本不是路径的场景。
    func registerFileURLHandler(id: ObjectIdentifier, handler: @escaping (ghostty_surface_t, URL) -> Void) {
        handlersLock.lock(); defer { handlersLock.unlock() }
        fileURLHandlers[id] = handler
    }

    private init() {
        if getenv("NO_COLOR") != nil { unsetenv("NO_COLOR") }

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("[PathDeck] ghostty_init failed")
            return
        }
        guard let config = ghostty_config_new() else {
            NSLog("[PathDeck] ghostty_config_new failed")
            return
        }
        // 终端外观经受管 runtime.conf 透传（xcframework 无逐键 setter）。先写当前偏好再 load。
        TerminalConfigWriter.writeCurrent().path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)
        self.config = config

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { userdata in
            GhosttyApp.runtimeApp(from: userdata)?.scheduleTick()
        }
        runtime.action_cb = { _, target, action in
            GhosttyApp.shared.handleAction(target: target, action: action)
        }
        runtime.read_clipboard_cb = { ud, clipboardType, state in
            guard clipboardType == GHOSTTY_CLIPBOARD_STANDARD else { return false }
            guard let content = NSPasteboard.general.string(forType: .string) else { return false }
            guard let ud else { return false }
            let view = Unmanaged<GhosttySurfaceView>.fromOpaque(ud).takeUnretainedValue()
            guard let surface = view.surface else { return false }
            content.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
            return true
        }
        runtime.confirm_read_clipboard_cb = { _, _, _, _ in }
        runtime.write_clipboard_cb = { _, clipboardType, contentPtr, contentCount, _ in
            guard clipboardType == GHOSTTY_CLIPBOARD_STANDARD,
                  let contentPtr, contentCount > 0 else { return }
            let contents = UnsafeBufferPointer(start: contentPtr, count: contentCount)
            var items: [(NSPasteboard.PasteboardType, String)] = []
            for content in contents {
                guard let dataPtr = content.data else { continue }
                let text = String(cString: dataPtr)
                let mime = content.mime.map { String(cString: $0) } ?? "text/plain"
                switch mime {
                case "text/plain": items.append((.string, text))
                case "text/html":  items.append((.html, text))
                default: break
                }
            }
            guard !items.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.declareTypes(items.map(\.0), owner: nil)
            for (type, text) in items {
                pb.setString(text, forType: type)
            }
        }
        runtime.close_surface_cb = { _, _ in
            NotificationCenter.default.post(name: .ghosttySurfaceDidClose, object: nil)
        }

        guard let created = ghostty_app_new(&runtime, config) else {
            NSLog("[PathDeck] ghostty_app_new failed")
            ghostty_config_free(config)
            self.config = nil
            return
        }
        self.app = created
    }

    // MARK: - 外观热重载

    /// 从 runtime.conf 重建全局 config 并应用到 app 级（影响后续新建 surface 的继承基线）。
    /// 配合 `applyCurrentConfig(to:)` 广播到现存 surface 实现热重载。由 `GhosttyTerminalEngine`
    /// 在 `.terminalAppearanceDidChange` 时调用（已 debounce）。
    func reloadConfig() {
        guard let app else { return }
        guard let newConfig = ghostty_config_new() else { return }
        TerminalConfigWriter.writeCurrent().path.withCString { ghostty_config_load_file(newConfig, $0) }
        ghostty_config_finalize(newConfig)
        ghostty_app_update_config(app, newConfig)
        if let old = config { ghostty_config_free(old) }
        config = newConfig
    }

    /// 把当前全局 config 增量应用到一个活动 surface（不重建，保留 scrollback/PTY/cwd）。
    /// libghostty 内部 diff 重算字体/网格/色彩并 reflow。
    func applyCurrentConfig(to surface: ghostty_surface_t) {
        guard let config else { return }
        ghostty_surface_update_config(surface, config)
        ghostty_surface_refresh(surface)
    }

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
        let surface = target.target.surface
        switch action.tag {
        case GHOSTTY_ACTION_PWD:
            if let cStr = action.action.pwd.pwd, let surface {
                let pwd = String(cString: cStr)
                handlersLock.lock()
                let handlers = pwdHandlers.values
                handlersLock.unlock()
                DispatchQueue.main.async {
                    for handler in handlers { handler(surface, pwd) }
                }
            }
            return true
        case GHOSTTY_ACTION_SET_TITLE:
            if let cStr = action.action.set_title.title, let surface {
                let title = String(cString: cStr)
                handlersLock.lock()
                let handlers = titleHandlers.values
                handlersLock.unlock()
                DispatchQueue.main.async {
                    for handler in handlers { handler(surface, title) }
                }
            }
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            // 终端输出中被 core 检测到的 URL（含 OSC 8 超链接）⌘Click：core 负责手势判定
            // 与下划线渲染，宿主只需响应打开请求，交系统默认程序。
            // 不筛 kind：两条点击链路（regex URL / OSC 8）都发 KIND_UNKNOWN；text/html 仅
            // write-screen-open 用（url 是裸文件路径），过不了 scheme 校验，回落 core fallback。
            let openURL = action.action.open_url
            guard let ptr = openURL.url, openURL.len > 0 else { return false }
            let raw = String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(openURL.len)), as: UTF8.self)
            guard let url = Self.openableURL(from: raw) else { return false }
            if url.isFileURL {
                // file:// 按本地路径走 Locate、绝不打开（ADR-0003）；engine 订阅后反查 session。
                guard let surface else { return true }
                handlersLock.lock()
                let handlers = fileURLHandlers.values
                handlersLock.unlock()
                DispatchQueue.main.async {
                    for handler in handlers { handler(surface, url) }
                }
                return true
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            // 子进程（shell）退出：Ghostty embedder 模型把退出决策委托给宿主。
            // 关闭对应 tab，并 return true 表示已处理——否则 Ghostty 显示默认
            // "press any key" overlay（exit 后不自动关闭 tab）。退出 surface 经
            // process_exited 反查（见 GhosttyTerminalEngine.handleSurfaceClose）。
            NotificationCenter.default.post(name: .ghosttySurfaceDidClose, object: nil)
            return true
        default:
            return false
        }
    }

    /// OPEN_URL action 的 URL 解析决策（纯函数，可单测）：必须能解析为带 scheme 的 URL，
    /// 否则拒绝——core 发来的都是 regex/OSC 8 命中的完整 URI，无 scheme 即异常数据。
    static func openableURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    /// 合并多次 wakeup 为主线程一次 tick。wakeup 在 I/O 线程高频触发，禁止每次都 tick。
    func scheduleTick() {
        tickLock.lock()
        defer { tickLock.unlock() }
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async {
            self.tick()
        }
    }

    /// 主线程泵 libghostty 事件循环（PTY I/O、定时器、action 派发），不涉及渲染。
    private func tick() {
        tickLock.lock()
        tickScheduled = false
        tickLock.unlock()
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// 从 app 级 userdata（`runtime.userdata`）取回单例。`wakeup_cb` 用。
    private static func runtimeApp(from userdata: UnsafeMutableRawPointer?) -> GhosttyApp? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
    }

    /// 链接冒烟用：返回 libghostty 版本号。
    static func libghosttyVersion() -> String {
        let info = ghostty_info()
        guard let version = info.version, info.version_len > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: version, count: Int(info.version_len)), as: UTF8.self)
    }
}
