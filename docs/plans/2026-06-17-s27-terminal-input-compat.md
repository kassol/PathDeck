# S27 Terminal Input Compat — 键盘 / 鼠标 / 剪贴板 / IME 全面接入

> 日期：2026-06-17
> 前置：S24 已合入（OSC title、divider 拖动等）

## 目标

补齐 `GhosttySurfaceView` 对标准终端输入的全面支持。当前只实现了 `keyDown`，剪贴板回调为空、`performKeyEquivalent` / `keyUp` / `flagsChanged` / 鼠标事件 / IME 全部缺失，导致 Cmd+V 粘贴、Cmd+C 复制、鼠标选择、滚动回看、CJK 输入法等基础功能不可用。

所有事件处理仅在终端 `GhosttySurfaceView` 为 first responder（即终端处于焦点）时触发——这是 AppKit responder chain 的天然机制，无需额外 guard。鼠标事件（scrollWheel / mouseUp / mouseDragged 等）由 AppKit 直接投递到光标下的 NSView，也天然限定到终端区域。

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P1 | Critical | 剪贴板回调 + `performKeyEquivalent` | `GhosttyApp.swift`, `GhosttySurfaceView.swift` |
| P2 | Important | `keyUp` + `flagsChanged` | `GhosttySurfaceView.swift` |
| P3 | Important | 鼠标事件全套 | `GhosttySurfaceView.swift` |
| P4 | Important | IME（NSTextInputClient） | `GhosttySurfaceView.swift` |

## Not Building

- Force Touch（`ghostty_surface_mouse_pressure`）——非标准终端需求，后续有需要再加
- OSC 52 用户确认弹窗（`confirm_read_clipboard_cb`）——初始 auto-deny，安全优先
- 终端右键自定义上下文菜单——鼠标事件转发到 libghostty 后，终端内的鼠标模式程序（vim 等）已可用；PathDeck 自己的右键菜单属独立需求
- 自定义 keybinding 配置界面——libghostty 内建 keybinding 系统已涵盖

---

## Phase 1：剪贴板 + performKeyEquivalent

### 问题

1. `GhosttyApp.swift` 中 `read_clipboard_cb` 返回 `false`，`write_clipboard_cb` / `confirm_read_clipboard_cb` 为空闭包。libghostty 调用 paste binding 时得不到剪贴板内容 → Cmd+V 不工作；libghostty 发起 copy 时无人写 pasteboard → Cmd+C 不工作。

2. `GhosttySurfaceView` 未覆写 `performKeyEquivalent(with:)`。macOS 对 Cmd+key 的分发顺序：先 `performKeyEquivalent`（沿 responder chain 向上），如果所有 responder 返回 false，再交给菜单系统匹配 `keyboardShortcut`。当前 GhosttySurfaceView 未覆写 → 返回 false → 菜单系统拦截 → libghostty 的 Cmd+key binding（paste/copy/clear/zoom 等）全部失效。

### 方案

#### 1a. 剪贴板回调（GhosttyApp.swift）

创建 surface 时设 `config.userdata = Unmanaged.passUnretained(self).toOpaque()`（GhosttySurfaceView 实例）。Ghostty 的 `read_clipboard_cb` / `write_clipboard_cb` / `close_surface_cb` 的第一个 `void*` 参数是 **surface userdata**（不是 app userdata），回调可直接反查发起请求的 view/surface，无需全局状态。

实现三个回调：

```swift
// read_clipboard_cb — libghostty 请求读剪贴板（paste binding 触发）
// 第一个参数 ud 是 surface_config.userdata → GhosttySurfaceView
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

// write_clipboard_cb — libghostty 请求写剪贴板（copy binding / OSC 52 write）
// write_clipboard_cb — 遍历 { mime, data } 数组，按 MIME 映射 PasteboardType
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

// confirm_read_clipboard_cb — 终端程序经 OSC 52 请求读剪贴板，需用户确认
// 初始实现：auto-deny（不调 complete_clipboard_request → 程序收不到内容）
runtime.confirm_read_clipboard_cb = { _, _, _, _ in }
```

#### 1b. performKeyEquivalent（GhosttySurfaceView.swift）

三层拦截：

1. **Ctrl+key（无 Cmd）**：除 `ctrlReservedKeycodes`（Tab=48、backtick=50）和 Ctrl+Shift+N 外，全部直发 libghostty（Ctrl+C/Return// 等终端关键键不被 AppKit 截走）
2. **Cmd+key**：`appReservedShortcuts`（`ReservedShortcut(char, shift, option)` 精确三元组，包含 t/w/o/f/q/,/1-9/Shift+t/n/p/./Option+c/Delete/Up）命中 → fallthrough 到菜单系统
3. **剩余 Cmd+key**：`ghostty_surface_key_is_binding` → 是 binding 则发 libghostty（Cmd+C/V 等终端 binding），否则 fallthrough

`keyDown` 中不再需要设置 `activeSurface`——clipboard 回调通过 surface userdata 直接定位 surface。

#### 冲突分析

`performKeyEquivalent` 返回 true 会"吃掉"事件，菜单系统不再处理。需要确认 libghostty 没有绑定 PathDeck 菜单用的快捷键：

| PathDeck 菜单快捷键 | libghostty 默认绑定? | 冲突? | 处理 |
|---------------------|---------------------|-------|------|
| Cmd+T (New Tab) | `super+t=new_tab` | **有** | `appReservedChars` 过滤，fallthrough 到菜单系统 |
| Cmd+W (Close Tab) | `super+w=close_surface` | **有** | `appReservedChars` 过滤 + addLocalMonitor 拦截 |
| Cmd+O (Open Folder) | `super+o=open_config` | **有** | `appReservedChars` 过滤 |
| Cmd+F (Find) | `super+f=start_search` | **有** | `appReservedChars` 过滤 |
| Cmd+Q (Quit) | `super+q=quit` | **有** | `appReservedShortcuts` 过滤 |
| Cmd+, (Settings) | `super+comma=open_config` | **有** | `appReservedShortcuts` 过滤 |
| Cmd+Shift+T (Send Path) | 无 | 无 | — |
| Cmd+Shift+N (New Folder/Terminal) | `super+shift+n=new_window` | **有** | `appReservedShortcuts` 过滤 |
| Ctrl+` (Toggle Terminal) | 无 | 无 | — |
| Cmd+1~9 (Tab Jump) | `super+1..9=goto_tab` | **有** | `appReservedShortcuts` 过滤 |

**冲突解决**：`performKeyEquivalent` 中维护 `appReservedShortcuts` 静态集合（`ReservedShortcut(char, shift, option)` 精确三元组，覆盖所有 PathDeck 菜单快捷键），匹配时直接 fallthrough 到 `super`（菜单系统），不检查 Ghostty binding。非 reserved 的 Cmd+key 才经 `ghostty_surface_key_is_binding` 判断是否为终端 binding。

libghostty 默认绑定 Cmd+C（copy）、Cmd+V（paste）等——这些不在 `appReservedShortcuts` 中，正确交给终端处理。终端 unfocused 时 `performKeyEquivalent` 不经过 GhosttySurfaceView，不影响文件浏览器侧的快捷键。

### 关键假设

`read_clipboard_cb` 的第一个 `void*` 参数是 **surface userdata**（来自 `surface_config.userdata`），不是 app userdata。依据：Ghostty embedded.zig 中 Surface 调用 clipboard 回调时传入 `self.userdata`。`wakeup_cb` 是唯一使用 app userdata 的回调。

### 涉及文件

- `GhosttyApp.swift`：实现 3 个 clipboard callback（`read_clipboard_cb` 通过 surface userdata 反查 view）
- `GhosttySurfaceView.swift`：`createSurface` 设 `config.userdata = self` + 新增 `performKeyEquivalent` 覆写

---

## Phase 2：keyUp + flagsChanged

### 问题

- `keyUp` 未覆写：key release 事件不转发到 libghostty。kitty keyboard protocol 需要 release 事件，vim 等程序可能依赖。
- `flagsChanged` 未覆写：单独按下/松开修饰键（Shift/Ctrl/Option/Cmd）不通知 libghostty。某些终端功能（修饰键改变光标形状等）依赖此事件。

### 方案

#### 2a. keyUp

RELEASE 永远不带 text（上游 Ghostty 一致）。只对 `forwardedKeyPresses` 中有记录的 keyCode 发 RELEASE——app reserved 快捷键（Cmd+Q/T/W 等）的 PRESS 没发给 Ghostty，RELEASE 也不发：

```swift
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
```

Cmd+key 的 keyUp 由 local monitor 拦截（macOS 不经 responder chain 投递 Cmd+keyUp），同样受 `forwardedKeyPresses` 守卫。`resignFirstResponder` 时对 outstanding 的 `forwardedKeyPresses` 逐个发 RELEASE 后清空。

#### 2b. flagsChanged

`heldModifierKeycodes: Set<UInt16>` 按物理 keyCode 追踪，正确区分左右同类键。`modifierKeycodeToMask` 字典做 keyCode → aggregate mask 映射。判断 press/release 不靠 aggregate flags（左右同按时 aggregate 仍为 true），而是看 held 集合：已 held → release；未 held + aggregate 仍含该 mask → press；未 held + aggregate 不含 → 忽略（防幽灵 press）：

```swift
private var heldModifierKeycodes: Set<UInt16> = []

private static let modifierKeycodeToMask: [UInt16: NSEvent.ModifierFlags] = [
    56: .shift, 60: .shift,
    59: .control, 62: .control,
    58: .option, 61: .option,
    55: .command, 54: .command,
]

override func flagsChanged(with event: NSEvent) {
    guard let surface else {
        super.flagsChanged(with: event)
        return
    }

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
```

### 涉及文件

- `GhosttySurfaceView.swift`：新增 `keyUp` + `flagsChanged` 覆写 + `heldModifierKeycodes: Set<UInt16>` + `modifierKeycodeToMask` + Caps Lock 支持

---

## Phase 3：鼠标事件

### 问题

终端面板内所有鼠标交互不工作：
- 无法用鼠标选择终端文本（需 mouseDown/mouseDragged/mouseUp → libghostty selection）
- 无法滚动回看历史（需 scrollWheel → `ghostty_surface_mouse_scroll`）
- vim/tmux/htop 等开启鼠标模式的程序无法响应点击/滚动（需 mouse button + pos 转发）
- 右键菜单不可用（需 rightMouseDown/Up）

### 方案

所有鼠标事件在 `GhosttySurfaceView.swift` 中覆写。坐标转换统一提取为辅助方法。

#### 坐标转换

```swift
/// NSView 坐标（左下原点）→ surface 坐标（左上原点，view point 坐标）
/// 不乘 scaleFactor——libghostty 内部处理 Retina 缩放
private func surfacePoint(from event: NSEvent) -> (x: Double, y: Double) {
    let local = convert(event.locationInWindow, from: nil)
    let x = local.x
    let y = bounds.height - local.y  // 翻转 Y
    return (x, y)
}
```

#### 事件覆写

```swift
// mouseDown — 焦点点击完全抑制（press + up 均不转发 TUI）
override func mouseDown(with event: NSEvent) {
    let wasFocused = window?.firstResponder === self
    window?.makeFirstResponder(self)
    guard wasFocused, let surface else {
        suppressNextLeftMouseUp = true
        return
    }
    let pt = surfacePoint(from: event)
    ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))
    _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                     mods(from: event.modifierFlags))
}

override func mouseUp(with event: NSEvent) {
    guard let surface else { return }
    if suppressNextLeftMouseUp { suppressNextLeftMouseUp = false; return }
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

// pressedMouseButtons: Set<Int> 按 event.buttonNumber 跟踪 Ghostty 接受的 press，
// release 只对有记录的发送，防止孤立 release。

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
```

#### scrollWheel

```swift
override func scrollWheel(with event: NSEvent) {
    guard let surface else {
        super.scrollWheel(with: event)
        return
    }
    let pt = surfacePoint(from: event)
    ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods(from: event.modifierFlags))

    // scroll mods: packed int，bit layout 见 ghostty src/input/mouse.zig
    // bit 0: precision (trackpad=1, wheel=0)
    var scrollMods: ghostty_input_scroll_mods_t = 0
    if event.hasPreciseScrollingDeltas {
        scrollMods |= 1  // precision bit
    }

    // momentum phase 映射（bits 1-3）
    let momentumValue: Int32
    switch event.momentumPhase {
    case .began:      momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
    case .stationary: momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
    case .changed:    momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
    case .ended:      momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
    case .cancelled:  momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
    case .mayBegin:   momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
    default:          momentumValue = Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
    }
    scrollMods |= (momentumValue << 1)

    ghostty_surface_mouse_scroll(surface,
                                 event.scrollingDeltaX,
                                 event.scrollingDeltaY,
                                 scrollMods)
}
```

注意：`ghostty_input_scroll_mods_t` 的 bit layout 需要对照 Ghostty 源码 `src/input/mouse.zig` 中的 `ScrollMods` packed struct 确认。上述 bit 位分配是基于 Ghostty 公开源码的推断（bit 0 = precision, bits 1-3 = momentum phase），实现时需验证。如果 bit layout 不确定，可暂时传 0（丧失 trackpad smooth scroll 和 momentum，但基本滚动可用）。

#### mouseMoved 激活

`mouseMoved` 默认不投递，需在窗口级或 tracking area 启用：

```swift
override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    let area = NSTrackingArea(
        rect: bounds,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self
    )
    addTrackingArea(area)
}
```

### 涉及文件

- `GhosttySurfaceView.swift`：新增 ~10 个鼠标事件覆写 + `surfacePoint` 辅助 + tracking area

---

## Phase 4：IME（输入法）

### 问题

`GhosttySurfaceView` 未实现 `NSTextInputClient` 协议。CJK 输入法（拼音、五笔、日文、韩文）在终端中无法使用——按键直接作为 ASCII 发送，不经过输入法转换。

### 方案

`GhosttySurfaceView` 遵循 `NSTextInputClient`，`keyDown` 改走 `interpretKeyEvents` 让输入法参与处理。

#### keyDown 改造

```swift
override func keyDown(with event: NSEvent) {
    guard let surface else {
        super.keyDown(with: event)
        return
    }

    let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
    let key = buildInputKey(from: event, action: action)
    var bindingFlags = ghostty_binding_flags_e(rawValue: 0)
    if ghostty_surface_key_is_binding(surface, key, &bindingFlags) {
        sendKeyEvent(event, action: action, surface: surface)
        return
    }

    // 非 keybinding → 走 interpretKeyEvents 让 IME 处理
    // insertText append 到 keyTextAccumulator: [String]（支持复杂 IME 一次多提交）
    currentKeyEvent = event
    keyTextAccumulator = []
    interpretKeyEvents([event])
    currentKeyEvent = nil

    // IME 产出文本 → 逐段发 PRESS（与上游 Ghostty 一致）
    // C0 控制字符（首字节 < 0x20）不设 text，让 Ghostty 按 keycode/mods 编码
    if let texts = keyTextAccumulator, !texts.isEmpty {
        for text in texts {
            var k = buildInputKey(from: event, action: action)
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
}
```

#### NSTextInputClient 核心方法

```swift
extension GhosttySurfaceView: NSTextInputClient {
    // 输入法提交最终文本
    // keyDown 流程中只累积到 keyTextAccumulator，由 keyDown 统一发 PRESS + text
    // 外部直接调用（menu / programmatic）走 ghostty_surface_text
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

    // 输入法更新候选/组合文本（preedit）
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let surface else { return }
        let text: String
        if let s = string as? String { text = s }
        else if let s = string as? NSAttributedString { text = s.string }
        else { return }

        let utf8 = Array(text.utf8)
        utf8.withUnsafeBufferPointer { buffer in
            ghostty_surface_preedit(surface, buffer.baseAddress, UInt(buffer.count))
        }
        markedText = text.isEmpty ? nil : text
    }

    func unmarkText() {
        guard let surface else { return }
        ghostty_surface_preedit(surface, nil, 0)
        markedText = nil
    }

    func hasMarkedText() -> Bool {
        markedText != nil
    }

    func markedRange() -> NSRange {
        guard let markedText else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.utf16.count)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    // 输入法候选窗口定位
    // ghostty_surface_ime_point 返回 view point 坐标（左上原点），不需要除 scale
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: bounds.height - y - h,
                              width: w, height: h)
        return window?.convertToScreen(convert(viewRect, to: nil)) ?? viewRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }
}
```

新增属性：

```swift
private var markedText: String?
```

### 与 Phase 1 performKeyEquivalent 的关系

`performKeyEquivalent` 处理 Cmd+key（由 macOS 在 keyDown 之前分发），不经过 `interpretKeyEvents` / IME 路径——这是正确的，因为 Cmd+key 不参与输入法。

`keyDown` 中 IME 路径只对非 keybinding 的普通按键生效（字母、数字、标点等）。Ctrl+C 等 keybinding 通过 `ghostty_surface_key_is_binding` 检测后直接走 libghostty，跳过 IME。

### 涉及文件

- `GhosttySurfaceView.swift`：遵循 `NSTextInputClient` + `markedText` 属性 + `keyDown` 改造

---

## 验证策略

每个 Phase 独立验证，不依赖后续 Phase。

### Phase 1 验证

自动验证（build 通过）+ GUI 走查：

1. 终端输入 `echo hello` → 正常回显（keyDown 不回归）
2. 终端中 Cmd+V → 粘贴剪贴板内容到 shell prompt
3. 终端中用鼠标选中文本（Phase 3 之后才有鼠标选择，此阶段用 `echo test | pbcopy` 准备剪贴板） → Cmd+C（暂不验证，需 Phase 3 鼠标选择支持后才有内容可复制）
4. 终端 focused 时 Cmd+T → 仍然新建 Tab（确认 performKeyEquivalent 不吞 PathDeck 菜单快捷键）
5. 文件列表 focused 时 Cmd+V → 无反应（确认事件只在终端 focused 时触发）

### Phase 2 验证

GUI 走查：

1. 终端中运行 `cat`，按键后松开 → 无异常（keyUp 不干扰正常输入）
2. 按住 Shift → 松开 → 无异常（flagsChanged 不引发多余输入）

### Phase 3 验证

GUI 走查：

1. 终端中双指滚动 → 回看历史输出
2. 终端中鼠标拖动选择文本 → 出现选区高亮
3. 选区后 Cmd+C → 文本复制到剪贴板
4. `vim` 中启用鼠标模式 → 点击/滚动正常响应
5. 终端面板外（文件列表区域）滚动 → 不影响终端

### Phase 4 验证

GUI 走查：

1. 切换到拼音输入法 → 终端中输入拼音 → 出现候选框 → 选词 → 文字插入终端
2. 输入法组合过程中按 Esc → 取消组合，不影响终端
3. Ctrl+C 在输入法激活时 → 仍然发送 interrupt（不被 IME 吞掉）

---

## 风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| `read_clipboard_cb` surface userdata 为 nil | `config.userdata` 未设 → clipboard 请求失败 | `createSurface` 显式设 `config.userdata = self`（`passUnretained`），回调直接反查 view |
| `scrollMods` bit layout 与 Ghostty 源码不匹配 | trackpad smooth scroll 不工作 | 暂传 0，基本滚动仍可用；后续对照 Ghostty 源码修正 |
| `performKeyEquivalent` 对某个 PathDeck 菜单快捷键返回 true | 菜单快捷键在终端 focused 时失效 | `appReservedShortcuts` 精确三元组（char, shift, option）过滤 PathDeck 菜单快捷键 → fallthrough；仅剩余 Cmd+key 经 `ghostty_surface_key_is_binding` 判断 |
| `keyDown` 改走 `interpretKeyEvents` 后输入路径变化 | 可能影响已有的 keyDown → ghostty_surface_key 逻辑 | `insertText` 累积到 `keyTextAccumulator: [String]`（支持一次多提交），keyDown 返回后逐段发 `ghostty_surface_key(PRESS, text:)`，C0 控制字符（< 0x20）不设 text；keybinding 走快速路径跳过 IME |

---

## 实现顺序

Phase 1 → Phase 2 → Phase 3 → Phase 4，每 Phase 独立 commit，可逐步合入。Phase 1 是最高优先级，解决最常被问到的 Cmd+V / Cmd+C 问题。
