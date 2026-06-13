//
//  GhosttyApp.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

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

    private init() {
        // 即便启动环境设了 NO_COLOR，也让终端内 TUI 能用色。
        if getenv("NO_COLOR") != nil { unsetenv("NO_COLOR") }

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("[PathDeck] ghostty_init failed")
            return
        }
        guard let config = ghostty_config_new() else {
            NSLog("[PathDeck] ghostty_config_new failed")
            return
        }
        ghostty_config_finalize(config)
        self.config = config

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { userdata in
            GhosttyApp.runtimeApp(from: userdata)?.scheduleTick()
        }
        // 冒烟不处理任何 action（reload config / open URL / 新窗口等一律不响应）。
        runtime.action_cb = { _, _, _ in false }
        // 本 xcframework 把该回调正确导入为返回 Bool，直接赋字面闭包即可。
        // （若换 GhosttyKit 构建把它导入成 Void，需改用顶层函数 + unsafeBitCast 兼容，见 Terminal/AGENTS.md。）
        runtime.read_clipboard_cb = { _, _, _ in false }
        runtime.confirm_read_clipboard_cb = { _, _, _, _ in }
        runtime.write_clipboard_cb = { _, _, _, _, _ in }
        // 冒烟不处理关闭请求，由用户手动关窗。
        runtime.close_surface_cb = { _, _ in }

        guard let created = ghostty_app_new(&runtime, config) else {
            NSLog("[PathDeck] ghostty_app_new failed")
            ghostty_config_free(config)
            self.config = nil
            return
        }
        self.app = created
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
    /// 证明 GhosttyKit 已正确链接、C 符号可从 Swift 调用，且不依赖窗口/GPU。
    static func libghosttyVersion() -> String {
        let info = ghostty_info()
        guard let version = info.version, info.version_len > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: version, count: Int(info.version_len)), as: UTF8.self)
    }
}
