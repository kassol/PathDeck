# S9：Send Path to Terminal（Context Bridge 首个切片）

> 日期：2026-06-14　需求：send-path-to-terminal（M2 切片 S9）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s8-terminal-panel.md`。

## 背景定位（M2 第二切片）

M1 闭合（S1–S7），S8 把终端面板嵌入主窗口。但终端与文件工作台之间**没有数据流通**——用户选中文件后，要手动复制路径、切到终端、粘贴。这正是 PathDeck 区别于「Finder + 外挂终端」的核心价值：Context Bridge。

S9 落地 FR-BRIDGE-001（Send Path to Terminal），是 Context Bridge 的第一个用户可感知功能。

| M2 切片 | 内容 | 覆盖 PRD |
|---|---|---|
| S8 ✅ | Terminal Panel 嵌入主窗口 + TerminalEngine 协议 | FR-TERM-001（部分）、FR-TERM-002（基础） |
| **S9** | **Send Path to Terminal** | **FR-BRIDGE-001** |
| S10（后续） | 拖文件到 Terminal | FR-BRIDGE-002 |
| S11（后续） | 多 Terminal Tab | FR-TERM-003 |

## 目标与验证标准

选中文件 → 右键或快捷键 → 路径以 shell-escaped 格式注入终端光标处。

手动验证：
1. 选中一个文件 → 右键「发送路径到终端」→ 终端光标处出现该文件的绝对路径（已转义）
2. 选中多个文件 → 右键「发送路径到终端」→ 终端出现空格分隔的多条转义路径
3. 选中包含空格、引号、中文的文件名 → 路径正确转义，可直接追加命令回车执行
4. 菜单快捷键 ⌘⇧T → 效果与右键相同
5. 终端面板隐藏时执行 → 自动展开终端面板，然后注入路径
6. 空白区域右键 → 不显示「发送路径到终端」
7. 发送后终端不丢失先前输入的内容（路径 append 到光标处）

单元测试：
- shell escape 纯函数：空格、单引号、双引号、反斜杠、换行、中文、空字符串、纯 ASCII 无特殊字符（不转义）
- 现有 56 个单测全部通过

## 最脆弱假设

**`ghostty_surface_complete_clipboard_request` 能以 bracketed paste 方式注入任意文本到 PTY。**

已确认 `ghostty.h` 中存在：
- `ghostty_surface_text(surface, ptr, len)` — 向 surface 写入 UTF-8 文本，等同于用户打字（IME 提交路径）
- `ghostty_surface_complete_clipboard_request(surface, text, userdata, confirmed)` — 完成剪贴板请求（bracketed paste）

两条路径：
1. **直接用 `ghostty_surface_text`**：最简单，逐字符等同键入。但如果终端处于 vim/readline 特殊模式，裸文本可能被解释为命令。
2. **通过 `ghostty_surface_complete_clipboard_request` 走 bracketed paste**：终端程序（bash/zsh readline）会将 `\e[200~...\e[201~` 包裹的内容视为纯文本粘贴，不触发补全/历史展开。这是 Ghostty 本体粘贴行为的底层 API。

**选择方案 1（`ghostty_surface_text`）**。理由：
- S2 已验证 `ghostty_surface_key` 走通键盘回显，`ghostty_surface_text` 是同层 API，直接向 PTY 写入文本
- `complete_clipboard_request` 需要一个来自 ghostty 的 clipboard request context（`userdata` 参数），不能凭空调用——它是 callback 式 API，必须先由 ghostty 发起 `read_clipboard_cb` 请求、宿主响应时才能调用
- 路径注入场景下（shell 提示符等待输入），`surface_text` 等同于用户快速打字，行为正确
- cmux 生产项目验证了这条路径

如果实测 `ghostty_surface_text` 在某些 shell 模式下有问题，退路是通过 macOS 剪贴板 + 模拟 ⌘V 按键事件间接粘贴。

## 技术方案

### Part 1：Shell Path Escape 纯函数

新建 `PathDeck/FileWorkspace/ShellEscape.swift`（放在 FileWorkspace 因为它是路径处理逻辑）：

```swift
enum ShellEscape {
    static func escape(_ path: String) -> String {
        // 纯 ASCII 且无特殊字符 → 不加引号
        // 否则用单引号包裹，内部单引号用 '\'' 转义
    }

    static func escapeMultiple(_ paths: [String]) -> String {
        paths.map { escape($0) }.joined(separator: " ")
    }
}
```

转义策略：POSIX shell 单引号包裹（`'...'`），内部单引号用 `'\''` 切断。这是最安全的 shell 转义方式——单引号内没有任何元字符展开。纯 ASCII 且无空格/特殊字符的路径不加引号，保持可读性。

### Part 2：TerminalEngine 协议扩展

`TerminalEngine.swift` 协议新增：

```swift
protocol TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView
    func writeText(_ text: String)
}
```

`writeText` 将文本注入当前终端 surface（等同于用户快速键入）。

### Part 3：GhosttyTerminalEngine + GhosttySurfaceView 实现

`GhosttySurfaceView` 新增公开方法：

```swift
func insertText(_ text: String) {
    guard let surface else { return }
    text.withCString { ptr in
        ghostty_surface_text(surface, ptr, text.utf8.count)
    }
}
```

`GhosttyTerminalEngine` 持有对当前 surface view 的弱引用，实现 `writeText`：

```swift
final class GhosttyTerminalEngine: TerminalEngine {
    private weak var currentSurfaceView: GhosttySurfaceView?

    func makeTerminalView(cwd: URL) -> NSView {
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = cwd
        currentSurfaceView = view
        return view
    }

    func writeText(_ text: String) {
        currentSurfaceView?.insertText(text)
    }
}
```

弱引用保证 surface view 生命周期仍由 SwiftUI view 树管理。

### Part 4：右键菜单 + 快捷键

**FileTableView Coordinator** 的 `menuNeedsUpdate` 中，在「复制路径」之后添加「发送路径到终端」菜单项（仅有选中文件时显示，空白区域不显示）：

```swift
addMenuItem(to: menu, title: "发送路径到终端", action: #selector(menuSendPathToTerminal(_:)))
```

菜单 action 通过闭包回调链传到 ContentView 层。

**FileTableView** 新增回调：

```swift
var onSendPathToTerminal: ([URL]) -> Void
```

Coordinator 的 `menuSendPathToTerminal` 收集 `selectedURLs()`，调用该回调。

**ContentView** 中接线：

```swift
FileTableView(
    ...
    onSendPathToTerminal: { urls in
        if !model.isTerminalVisible {
            model.isTerminalVisible = true
            terminalCreated = true
        }
        let escaped = ShellEscape.escapeMultiple(urls.map { $0.path(percentEncoded: false) })
        terminalEngine.writeText(escaped)
    }
)
```

**菜单命令**：`TerminalCommands` 新增：

```swift
Button("发送路径到终端") {
    // 通过 FocusedValue 拿 model.selectedURLs + terminalEngine
}
.keyboardShortcut("t", modifiers: [.command, .shift])
```

需要在 `FocusedValues` 新增一个 `sendPathToTerminal` action entry，或将 `terminalEngine` 也通过 focused value 传递。

**设计选择**：新增 `@Entry var sendPathAction: (([URL]) -> Void)?`，ContentView 把闭包通过 `.focusedSceneValue` 传出。TerminalCommands 调用时直接拿 `model.selectedURLs` + 该 action。这样菜单命令和右键菜单共享同一条路径，不重复逻辑。

### Part 5：终端自动展开

`onSendPathToTerminal` 回调中，若 `!model.isTerminalVisible`，先 toggle，等 `terminalCreated` 后再注入文本。需要一个短暂的 `DispatchQueue.main.async` 让 SwiftUI 完成一轮布局（surface view 挂上 window 后才能接收文本）。

```swift
onSendPathToTerminal: { urls in
    let escaped = ShellEscape.escapeMultiple(urls.map { $0.path(percentEncoded: false) })
    if model.isTerminalVisible {
        terminalEngine.writeText(escaped)
    } else {
        model.isTerminalVisible = true
        terminalCreated = true
        DispatchQueue.main.async {
            terminalEngine.writeText(escaped)
        }
    }
}
```

## 改动文件清单

| 文件 | 改动 |
|---|---|
| **新增** `FileWorkspace/ShellEscape.swift` | shell path escape 纯函数 |
| `Terminal/TerminalEngine.swift` | 协议新增 `writeText(_ text: String)` |
| `Terminal/GhosttyTerminalEngine.swift` | 实现 `writeText`，持有 surface view 弱引用 |
| `Terminal/GhosttySurfaceView.swift` | 新增 `insertText(_ text: String)`（调用 `ghostty_surface_text`） |
| `FileWorkspace/FileTableView.swift` | Coordinator 右键菜单添加「发送路径到终端」+ 新增 `onSendPathToTerminal` 回调 |
| `ContentView.swift` | 接线 `onSendPathToTerminal` + focused value 传递 action |
| `PathDeckApp.swift` | TerminalCommands 新增「发送路径到终端」⌘⇧T |

## 不改动

| 文件 | 理由 |
|---|---|
| `Terminal/GhosttyApp.swift` | runtime 单例不变 |
| `Terminal/TerminalPanelView.swift` | 纯布局包装，不涉及文本注入 |
| `Terminal/TerminalSmokeView.swift` | 冒烟窗口不参与 Context Bridge |
| `FileWorkspace/WorkspaceModel.swift` | 无新状态（`selectedURLs` + `isTerminalVisible` 已存在） |
| `ChangeJournal/*` | 无关 |
| `PathDeck.xcodeproj/project.pbxproj` | 新文件在 synchronized group 内自动纳入 |

## Scope

- Shell path escape 纯函数（单引号包裹，POSIX 安全）
- `TerminalEngine` 协议扩展 `writeText`
- `GhosttySurfaceView.insertText` 调用 `ghostty_surface_text` C API
- 右键菜单「发送路径到终端」（单选 / 多选）
- 菜单快捷键 ⌘⇧T
- 终端隐藏时自动展开再注入

## Non-scope

- 拖拽文件到终端（FR-BRIDGE-002，S10）
- 相对路径 / 换行分隔 / 格式选择弹层（PRD §10.3 的 optional popover，后续增量）
- Terminal cwd 双向同步（FR-TERM-004）
- 多 Terminal Tab（FR-TERM-003，S11）
- 预览文本选区发送到终端（FR-BRIDGE-005，P1）
- Send Path 的 Undo（路径已写入 PTY 流，不可逆，不需 Undo）

## 实现顺序

1. `ShellEscape.swift` — 纯函数 + 单测
2. `GhosttySurfaceView.swift` — 新增 `insertText`
3. `TerminalEngine.swift` — 协议扩展 `writeText`
4. `GhosttyTerminalEngine.swift` — 实现 `writeText` + 弱引用 surface view
5. `FileTableView.swift` — 右键菜单 + `onSendPathToTerminal` 回调
6. `ContentView.swift` — 接线回调 + focused value
7. `PathDeckApp.swift` — ⌘⇧T 菜单命令
8. build + 现有单测 + 新增 ShellEscape 单测 + GUI 走查（7 条验收标准）
9. `Terminal/AGENTS.md` + `FileWorkspace/AGENTS.md` — 更新

## 工作量

1 个新文件 + 6 个改动文件 + 2 个文档更新，~120 行新代码 + ~8 个单测。
