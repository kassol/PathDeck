//
//  GhosttySurfaceView.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import AppKit
import GhosttyKit
import Metal

/// 承载单个 libghostty terminal surface 的 `NSView`（S2 冒烟）。
///
/// 渲染由 libghostty 内部 CVDisplayLink 自驱：本视图只负责
/// ① 提供 `CAMetalLayer` backing；② surface 生命周期与尺寸/缩放/display 同步；
/// ③ 转发键盘事件。本视图从不调用 `ghostty_surface_draw`。详见 `Terminal/AGENTS.md`。
final class GhosttySurfaceView: NSView {
    private var surface: ghostty_surface_t?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 不支持")
    }

    deinit {
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    // MARK: - Layer

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        // framebufferOnly = false 让合成器可读 drawable（半透明/模糊窗口需要），对齐 standalone Ghostty。
        metalLayer.framebufferOnly = false
        return metalLayer
    }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - 生命周期

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // surface 必须在挂上 window 后再创建，否则拿不到有效 layer/display → 黑屏。
        guard window != nil else { return }
        if surface == nil {
            createSurface()
        } else {
            syncSurfaceGeometry()
        }
        window?.makeFirstResponder(self)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        syncSurfaceGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceGeometry()
    }

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: - Surface

    private func createSurface() {
        guard let app = GhosttyApp.shared.app else {
            NSLog("[PathDeck] surface 创建跳过：ghostty app 未初始化")
            return
        }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = scaleFactor

        // 嵌套 withCString 保证所有 C 指针在 ghostty_surface_new 调用期间有效。
        // env 注入 TERM=xterm-256color 规避缺失的 xterm-ghostty terminfo（决策 D-S2-1）。
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        "TERM".withCString { termKey in
            "xterm-256color".withCString { termValue in
                var envVars = [ghostty_env_var_s(key: termKey, value: termValue)]
                home.withCString { cHome in
                    config.working_directory = cHome
                    envVars.withUnsafeMutableBufferPointer { buffer in
                        config.env_vars = buffer.baseAddress
                        config.env_var_count = buffer.count
                        surface = ghostty_surface_new(app, &config)
                    }
                }
            }
        }

        guard let surface else {
            NSLog("[PathDeck] ghostty_surface_new 返回 nil")
            return
        }

        syncSurfaceGeometry()
        ghostty_surface_set_focus(surface, true)
        // 创建后 kick 首帧，防止 Ghostty miss 第一个 vsync 而停在空白帧。
        ghostty_surface_refresh(surface)
    }

    /// 同步 display id / 内容缩放 / 像素尺寸到 surface。display id 让内部 CVDisplayLink 锁对刷新率。
    private func syncSurfaceGeometry() {
        guard let surface else { return }
        if let displayID = (window?.screen ?? NSScreen.main)?.displayID, displayID != 0 {
            ghostty_surface_set_display_id(surface, displayID)
        }
        ghostty_surface_set_content_scale(surface, scaleFactor, scaleFactor)
        let backing = convertToBacking(NSRect(origin: .zero, size: bounds.size)).size
        let wpx = UInt32(max(0, backing.width))
        let hpx = UInt32(max(0, backing.height))
        if wpx > 0, hpx > 0 {
            ghostty_surface_set_size(surface, wpx, hpx)
        }
    }

    private var scaleFactor: Double {
        Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }

    // MARK: - 键盘（冒烟最小回显路径）

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        var key = ghostty_input_key_s()
        key.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        key.keycode = UInt32(event.keyCode)
        key.mods = mods(from: event.modifierFlags)
        key.consumed_mods = consumedMods(from: event.modifierFlags)
        key.composing = false
        key.unshifted_codepoint = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0

        let handled: Bool
        if let text = event.characters, !text.isEmpty {
            // text 指针只需在 ghostty_surface_key 调用期间有效。
            handled = text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            handled = ghostty_surface_key(surface, key)
        }

        if !handled {
            super.keyDown(with: event)
        }
    }

    private func mods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    /// consumed_mods 仅含参与文本翻译的修饰键；Control/Command 从不参与，故排除。
    private func consumedMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }
}

private extension NSScreen {
    /// CoreGraphics display id，用于 `ghostty_surface_set_display_id`。
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
