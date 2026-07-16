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
    var initialCwd: URL?
    var onSurfaceReady: (() -> Void)?
    var onSurfaceFailed: ((SurfaceFailureReason) -> Void)?
    /// ⌘Click 命中 Path Link（FR-BRIDGE-003）：engine 反查 session 后派发 Locate。
    var onPathLinkClick: ((PathLink) -> Void)?
    /// 本终端 OSC 7 最近上报的 cwd（engine 的 pwd handler 写入）。相对路径只挂在它上面；
    /// nil（shell integration 未生效 / 未出首个 prompt）时相对路径不触发。
    var reportedCwd: URL?
    private(set) var surface: ghostty_surface_t?
    private var markedText: String?
    private var heldModifierKeycodes: Set<UInt16> = []
    private var currentKeyEvent: NSEvent?
    private var keyTextAccumulator: [String]?
    private var hadMarkedTextBeforeInterpret = false
    private var suppressNextLeftMouseUp = false
    private var pressedMouseButtons: Set<Int> = []
    private var forwardedKeyPresses: Set<UInt16> = []
    private var keyUpMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 不支持")
    }

    deinit {
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
        guard window != nil else {
            if let monitor = keyUpMonitor {
                NSEvent.removeMonitor(monitor)
                keyUpMonitor = nil
            }
            return
        }
        if surface == nil {
            createSurface()
        } else {
            syncSurfaceGeometry()
        }
        installKeyUpMonitorIfNeeded()
        window?.makeFirstResponder(self)
    }

    private func installKeyUpMonitorIfNeeded() {
        guard keyUpMonitor == nil else { return }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, let surface = self.surface else { return event }
            guard self.window?.firstResponder === self else { return event }
            guard event.modifierFlags.contains(.command) else { return event }
            guard self.forwardedKeyPresses.remove(event.keyCode) != nil else { return event }
            var key = self.buildInputKey(from: event, action: GHOSTTY_ACTION_RELEASE)
            key.text = nil
            _ = ghostty_surface_key(surface, key)
            return nil
        }
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func becomeFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, false)
            releaseHeldModifiers(surface: surface)
            releaseForwardedKeys(surface: surface)
        }
        clearComposition()
        return super.resignFirstResponder()
    }

    private func releaseHeldModifiers(surface: ghostty_surface_t) {
        for keycode in heldModifierKeycodes {
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_RELEASE
            key.keycode = UInt32(keycode)
            key.mods = GHOSTTY_MODS_NONE
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.composing = false
            key.text = nil
            key.unshifted_codepoint = 0
            _ = ghostty_surface_key(surface, key)
        }
        heldModifierKeycodes.removeAll()
    }

    private func releaseForwardedKeys(surface: ghostty_surface_t) {
        for keycode in forwardedKeyPresses {
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_RELEASE
            key.keycode = UInt32(keycode)
            key.mods = GHOSTTY_MODS_NONE
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.composing = false
            key.text = nil
            key.unshifted_codepoint = 0
            _ = ghostty_surface_key(surface, key)
        }
        forwardedKeyPresses.removeAll()
    }

    private func clearComposition() {
        guard markedText != nil, let surface else { return }
        inputContext?.discardMarkedText()
        ghostty_surface_preedit(surface, nil, 0)
        markedText = nil
    }

    override func mouseDown(with event: NSEvent) {
        let wasFocused = window?.firstResponder === self
        window?.makeFirstResponder(self)
        // ⌘Click（纯 ⌘，不含 ⇧⌥⌃）命中 Path Link → 本地 Locate，不进 core（绕过 mouse
        // reporting，终端惯例）；未命中则照常转发，core 自己的 URL ⌘Click（OPEN_URL）不受影响。
        let clickFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if clickFlags.contains(.command),
           clickFlags.isDisjoint(with: [.shift, .option, .control]),
           let link = pathLink(at: event) {
            suppressNextLeftMouseUp = true
            onPathLinkClick?(link)
            return
        }
        guard wasFocused, let surface else {
            suppressNextLeftMouseUp = true
            return
        }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                         mods(from: event.modifierFlags))
    }

    // MARK: - Surface

    private func createSurface() {
        guard let app = GhosttyApp.shared.app else {
            NSLog("[PathDeck] surface 创建跳过：ghostty app 未初始化")
            onSurfaceFailed?(.appNotInitialized)
            onSurfaceFailed = nil
            onSurfaceReady = nil
            return
        }

        var config = ghostty_surface_config_new()
        config.wait_after_command = false
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = scaleFactor
        // 新建时直填字号保证即时正确；同一字号也写入 runtime.conf 供热重载（单一真值 = TerminalPreferences）。
        config.font_size = Float(TerminalPreferences.shared.fontSize)

        let cwdPath = (initialCwd ?? FileManager.default.homeDirectoryForCurrentUser).path
        let shellPath = TerminalPreferences.shared.resolvedShell

        var envPairs: [(key: String, value: String)] = [("TERM", "xterm-256color")]
        envPairs.append(contentsOf: ShellIntegration.envVars(for: shellPath))

        let keys = envPairs.map { strdup($0.key)! }
        let values = envPairs.map { strdup($0.value)! }
        defer { keys.forEach { free($0) }; values.forEach { free($0) } }

        var envVars = zip(keys, values).map { ghostty_env_var_s(key: $0, value: $1) }

        cwdPath.withCString { cCwd in
            shellPath.withCString { cShell in
                config.working_directory = cCwd
                config.command = cShell
                envVars.withUnsafeMutableBufferPointer { buffer in
                    config.env_vars = buffer.baseAddress
                    config.env_var_count = buffer.count
                    surface = ghostty_surface_new(app, &config)
                }
            }
        }

        guard let surface else {
            NSLog("[PathDeck] ghostty_surface_new 返回 nil")
            onSurfaceFailed?(.surfaceNewReturnedNil)
            onSurfaceFailed = nil
            onSurfaceReady = nil
            return
        }

        syncSurfaceGeometry()
        ghostty_surface_set_focus(surface, true)
        // 创建后 kick 首帧，防止 Ghostty miss 第一个 vsync 而停在空白帧。
        ghostty_surface_refresh(surface)
        onSurfaceReady?()
        onSurfaceReady = nil
        onSurfaceFailed = nil
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

    // MARK: - Text Injection

    func insertText(_ text: String) {
        guard let surface else { return }
        let utf8 = Array(text.utf8)
        utf8.withUnsafeBufferPointer { buffer in
            ghostty_surface_text(surface, buffer.baseAddress, UInt(buffer.count))
        }
    }

    // MARK: - 键盘

    private func buildInputKey(from event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = mods(from: event.modifierFlags)
        key.consumed_mods = consumedMods(from: event.modifierFlags)
        key.composing = false
        key.unshifted_codepoint = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        return key
    }

    @discardableResult
    private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e, surface: ghostty_surface_t) -> Bool {
        if action == GHOSTTY_ACTION_PRESS || action == GHOSTTY_ACTION_REPEAT {
            forwardedKeyPresses.insert(event.keyCode)
        }
        var key = buildInputKey(from: event, action: action)
        if let text = event.characters, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            return ghostty_surface_key(surface, key)
        }
    }

    /// App 保留的 ⌘ 组合由 ShortcutRegistry 派生（S36 收束），不再手工维护。
    private static let appReservedShortcuts: Set<TerminalReservedKey> =
        ShortcutRegistry.terminalReservedKeys

    private static let ctrlReservedKeycodes: Set<UInt16> = [48, 50]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.control), !flags.contains(.command) {
            if Self.ctrlReservedKeycodes.contains(event.keyCode) {
                return super.performKeyEquivalent(with: event)
            }
            if markedText != nil {
                return super.performKeyEquivalent(with: event)
            }
            sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS, surface: surface)
            return true
        }

        guard flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           let first = chars.first {
            let shortcut = TerminalReservedKey(
                char: first,
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option)
            )
            if Self.appReservedShortcuts.contains(shortcut) {
                return super.performKeyEquivalent(with: event)
            }
        }

        let key = buildInputKey(from: event, action: GHOSTTY_ACTION_PRESS)
        var bindingFlags = ghostty_binding_flags_e(rawValue: 0)
        guard ghostty_surface_key_is_binding(surface, key, &bindingFlags) else {
            return super.performKeyEquivalent(with: event)
        }

        sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS, surface: surface)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        if markedText == nil {
            let key = buildInputKey(from: event, action: action)
            var bindingFlags = ghostty_binding_flags_e(rawValue: 0)
            if ghostty_surface_key_is_binding(surface, key, &bindingFlags) {
                sendKeyEvent(event, action: action, surface: surface)
                return
            }
        }

        currentKeyEvent = event
        keyTextAccumulator = []
        hadMarkedTextBeforeInterpret = markedText != nil
        interpretKeyEvents([event])
        currentKeyEvent = nil

        if let texts = keyTextAccumulator, !texts.isEmpty {
            if !hadMarkedTextBeforeInterpret {
                forwardedKeyPresses.insert(event.keyCode)
            }
            for text in texts {
                if hadMarkedTextBeforeInterpret {
                    let scalars = text.unicodeScalars
                    if let first = scalars.first,
                       scalars.index(after: scalars.startIndex) == scalars.endIndex,
                       first.value < 0x20 {
                        continue
                    }
                }
                var k: ghostty_input_key_s
                if hadMarkedTextBeforeInterpret {
                    k = ghostty_input_key_s()
                    k.action = action
                    k.keycode = 0
                    k.mods = GHOSTTY_MODS_NONE
                    k.consumed_mods = GHOSTTY_MODS_NONE
                    k.composing = false
                    k.unshifted_codepoint = 0
                } else {
                    k = buildInputKey(from: event, action: action)
                }
                if let first = text.utf8.first, first >= 0x20 {
                    text.withCString { ptr in
                        k.text = ptr
                        _ = ghostty_surface_key(surface, k)
                    }
                } else {
                    k.text = nil
                    _ = ghostty_surface_key(surface, k)
                }
            }
        }
        keyTextAccumulator = nil
        hadMarkedTextBeforeInterpret = false
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }
        guard forwardedKeyPresses.remove(event.keyCode) != nil else { return }
        var key = buildInputKey(from: event, action: GHOSTTY_ACTION_RELEASE)
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }

    private static let modifierKeycodeToMask: [UInt16: NSEvent.ModifierFlags] = [
        56: .shift, 60: .shift,
        59: .control, 62: .control,
        58: .option, 61: .option,
        55: .command, 54: .command,
        57: .capsLock,
    ]

    override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }
        if markedText != nil { return }

        let keycode = event.keyCode
        guard let mask = Self.modifierKeycodeToMask[keycode] else { return }

        let held = heldModifierKeycodes.contains(keycode)
        let isPress: Bool
        if held {
            isPress = false
        } else if event.modifierFlags.contains(mask) {
            isPress = true
        } else {
            return
        }

        if isPress {
            heldModifierKeycodes.insert(keycode)
        } else {
            heldModifierKeycodes.remove(keycode)
        }

        var key = ghostty_input_key_s()
        key.action = isPress ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        key.keycode = UInt32(keycode)
        key.mods = mods(from: event.modifierFlags)
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.composing = false
        key.text = nil
        key.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, key)
    }

    override func doCommand(by selector: Selector) {
        guard !hadMarkedTextBeforeInterpret else { return }
        if let event = currentKeyEvent, let surface {
            sendKeyEvent(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS, surface: surface)
        }
    }

    private func mods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func consumedMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    // MARK: - 鼠标

    private func surfacePoint(from event: NSEvent) -> (x: Double, y: Double) {
        let local = convert(event.locationInWindow, from: nil)
        return (local.x, bounds.height - local.y)
    }

    // MARK: - Path Link（FR-BRIDGE-003）

    /// 点击像素 → 格子坐标 → 读取该行文本 → Path Link 检测。
    /// 格子换算：click 点（view point，左上原点）× scale − padding px，除以 cell px。
    /// window-padding 由 ghostty 按 content scale 缩放（`TerminalConfigWriter` 写 pt 值）。
    private func pathLink(at event: NSEvent) -> PathLink? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0,
              size.cell_width_px > 0, size.cell_height_px > 0 else { return nil }

        let pt = surfacePoint(from: event)
        let scale = scaleFactor
        let paddingPx = Double(TerminalPreferences.shared.padding) * scale
        let xPx = pt.x * scale - paddingPx
        let yPx = pt.y * scale - paddingPx
        guard xPx >= 0, yPx >= 0 else { return nil }

        let col = Int(xPx / Double(size.cell_width_px))
        let row = Int(yPx / Double(size.cell_height_px))
        guard col < Int(size.columns), row < Int(size.rows) else { return nil }

        // 点击格必须非空白：行尾空区/词间空格直接 miss，也规避 read_text 尾部修剪的歧义。
        guard let cell = viewportText(row: row, fromCol: col, toCol: col),
              !cell.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // 格子列 ≠ 字符下标（CJK 等宽字符占 2 格 1 字符）：用 core 自己的选区语义换算——
        // [0, col] 前缀的字符数减一即点击字符下标（前缀末格非空白，不受尾部修剪影响）。
        guard let prefix = viewportText(row: row, fromCol: 0, toCol: col),
              !prefix.isEmpty else { return nil }
        let index = prefix.count - 1

        guard let line = viewportText(row: row, fromCol: 0, toCol: Int(size.columns) - 1) else { return nil }
        return PathLinkDetector.detect(line: line, index: index, cwd: reportedCwd,
                                       probe: PathLinkDetector.fileSystemProbe)
    }

    /// 读取 viewport 第 `row` 行（0-based，顶部为 0）[fromCol, toCol] 闭区间的文本。
    private func viewportText(row: Int, fromCol: Int, toCol: Int) -> String? {
        guard let surface else { return nil }
        var selection = ghostty_selection_s()
        selection.top_left = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
            x: UInt32(fromCol), y: UInt32(row)
        )
        selection.bottom_right = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
            x: UInt32(toCol), y: UInt32(row)
        )
        selection.rectangle = false

        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(text.text_len)),
                      as: UTF8.self)
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextLeftMouseUp {
            suppressNextLeftMouseUp = false
            return
        }
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                         mods(from: event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
    }

    override func mouseExited(with event: NSEvent) {
        if let surface {
            ghostty_surface_mouse_pos(surface, -1, -1, GHOSTTY_MODS_NONE)
        }
        NSCursor.arrow.set()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { super.rightMouseDown(with: event); return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        let handled = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT,
                                                   mods(from: event.modifierFlags))
        if handled {
            pressedMouseButtons.insert(event.buttonNumber)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        guard pressedMouseButtons.remove(event.buttonNumber) != nil else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT,
                                         mods(from: event.modifierFlags))
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
    }

    private static func ghosttyMouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 2:  return GHOSTTY_MOUSE_MIDDLE
        case 3:  return GHOSTTY_MOUSE_FOUR
        case 4:  return GHOSTTY_MOUSE_FIVE
        case 5:  return GHOSTTY_MOUSE_SIX
        case 6:  return GHOSTTY_MOUSE_SEVEN
        case 7:  return GHOSTTY_MOUSE_EIGHT
        case 8:  return GHOSTTY_MOUSE_NINE
        case 9:  return GHOSTTY_MOUSE_TEN
        case 10: return GHOSTTY_MOUSE_ELEVEN
        default: return GHOSTTY_MOUSE_MIDDLE
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        let handled = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS,
                                                   Self.ghosttyMouseButton(for: event.buttonNumber),
                                                   mods(from: event.modifierFlags))
        if handled { pressedMouseButtons.insert(event.buttonNumber) }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        guard pressedMouseButtons.remove(event.buttonNumber) != nil else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE,
                                         Self.ghosttyMouseButton(for: event.buttonNumber),
                                         mods(from: event.modifierFlags))
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else {
            super.scrollWheel(with: event)
            return
        }
        let pt = surfacePoint(from: event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))

        var scrollMods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas { scrollMods |= 1 }

        let momentumValue: Int32
        switch event.momentumPhase {
        case .began:      momentumValue = 1
        case .stationary: momentumValue = 2
        case .changed:    momentumValue = 3
        case .ended:      momentumValue = 4
        case .cancelled:  momentumValue = 5
        case .mayBegin:   momentumValue = 6
        default:          momentumValue = 0
        }
        scrollMods |= (momentumValue << 1)

        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
    }
}

// MARK: - NSTextInputClient

extension GhosttySurfaceView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        let text: String
        if let s = string as? String { text = s }
        else if let s = string as? NSAttributedString { text = s.string }
        else { return }

        ghostty_surface_preedit(surface, nil, 0)
        markedText = nil

        if currentKeyEvent != nil {
            keyTextAccumulator?.append(text)
        } else {
            let utf8 = Array(text.utf8)
            utf8.withUnsafeBufferPointer { buffer in
                ghostty_surface_text(surface, buffer.baseAddress, UInt(buffer.count))
            }
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let surface else { return }
        let text: String
        if let s = string as? String { text = s }
        else if let s = string as? NSAttributedString { text = s.string }
        else { return }

        if text.isEmpty {
            ghostty_surface_preedit(surface, nil, 0)
            markedText = nil
        } else {
            let utf8 = Array(text.utf8)
            utf8.withUnsafeBufferPointer { buffer in
                ghostty_surface_preedit(surface, buffer.baseAddress, UInt(buffer.count))
            }
            markedText = text
        }
    }

    func unmarkText() {
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
        markedText = nil
    }

    func hasMarkedText() -> Bool { markedText != nil }

    func markedRange() -> NSRange {
        guard let markedText else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.utf16.count)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x,
                              y: bounds.height - y - h,
                              width: w,
                              height: h)
        return window?.convertToScreen(convert(viewRect, to: nil)) ?? viewRect
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? { nil }
}

extension Notification.Name {
    static let ghosttySurfaceDidClose = Notification.Name("ghosttySurfaceDidClose")
    /// 终端外观偏好变更：`GhosttyTerminalEngine` 观察后重写 runtime.conf + 热重载所有活动 surface。
    nonisolated static let terminalAppearanceDidChange = Notification.Name("terminalAppearanceDidChange")
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
