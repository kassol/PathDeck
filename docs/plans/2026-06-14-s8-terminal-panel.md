# S8：Terminal Panel 嵌入主窗口 + TerminalEngine 协议

> 日期：2026-06-14　需求：terminal-panel（M2 切片 S8）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s7-open-folder-search.md`。

## 背景定位（M2 第一切片）

M1 全闭合（S1–S7），文件工作台可用。M2 目标：Terminal 成为文件工作流的一部分。

S2 已验证 libghostty 嵌入可行（独立冒烟窗口），但有两个遗留：
1. 终端在独立窗口中，与文件工作台割裂——用户必须在两个窗口间切换。
2. C 符号直连，无协议抽象——`Terminal/AGENTS.md` 明确约束「接入文件工作台时补 `TerminalEngine` 协议」。

S8 同时解决这两项：把终端嵌入主窗口底部面板，并通过协议隔离 libghostty。

| M2 切片 | 内容 | 覆盖 PRD |
|---|---|---|
| **S8** | **Terminal Panel 嵌入主窗口 + TerminalEngine 协议** | FR-TERM-001（部分）、FR-TERM-002（基础） |
| S9（后续） | Send Path + 拖拽文件到终端 | FR-BRIDGE-001、FR-BRIDGE-002 |
| S10（后续） | 多 Terminal Tab | FR-TERM-003 |

## 目标与验证标准

主窗口底部出现可展开/收起的终端面板，cwd 为当前工作区文件夹，用户无需离开文件工作台即可执行命令。

手动验证：
1. ⌃\` 或 Toolbar 按钮 → 底部展开终端面板，渲染 shell 提示符
2. 终端 cwd = 当前文件工作台目录（`pwd` 验证）
3. 可输入命令（`echo hi`、`ls`）并回显
4. 再按 ⌃\` → 面板收起，文件列表恢复占满
5. 拖拽分割线 → 终端面板高度可调
6. 文件工作台切换目录（⌘O / 双击 / 面包屑）→ 终端面板不崩溃（cwd 不自动跟随，属后续 FR-TERM-004）
7. 冒烟窗口（⌃⌥⌘T）仍可独立打开，与主窗口终端不冲突（验证多 surface）

单元测试：
- 现有 56 个单测 + `GhosttyLinkTests` 全部通过
- 无新增逻辑单测（协议是纯接口；面板是纯布局 + 状态切换，UI 行为由 GUI 走查覆盖）

## 最脆弱假设

同一 `ghostty_app_t` 下同时存在两个 surface（主窗口面板 + 冒烟窗口）是否冲突。libghostty 设计上支持多 surface（Ghostty 本身就是多 tab/split），`ghostty_surface_new` 接受同一个 app 实例。如果实测互斥：退路是主窗口面板独占，将冒烟窗口入口禁用或移除。

## 技术方案

### Part 1：TerminalEngine 协议

新建 `Terminal/TerminalEngine.swift`，定义协议：

```swift
import AppKit

protocol TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView
}
```

极简接口：给一个 cwd，返回一个可嵌入的 NSView。View 自己管理 surface 生命周期（创建/销毁跟随 NSView）。不暴露 shutdown——NSView deinit 时 surface 自动 free（现有 `GhosttySurfaceView.deinit` 已做）。

不暴露 `setCwd`：运行中的 shell 的 cwd 由 shell 自行管理（`cd` 命令），宿主侧无法从外部改变已创建 surface 的 cwd。这是终端模拟器的通用约束，不是协议设计缺陷。后续 FR-TERM-004（cwd 同步）通过 OSC 序列感知 shell cwd 变化，属 S10+ 范围。

### Part 2：GhosttyTerminalEngine 实现

新建 `Terminal/GhosttyTerminalEngine.swift`：

```swift
import AppKit

final class GhosttyTerminalEngine: TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView {
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = cwd
        return view
    }
}
```

**改动 `GhosttySurfaceView`**：

- 新增 `var initialCwd: URL?` 属性（设置后 `createSurface()` 使用它，不再硬编码 `homeDirectoryForCurrentUser`）
- `createSurface()` 改用 `initialCwd?.path ?? FileManager.default.homeDirectoryForCurrentUser.path`

这是 `GhosttySurfaceView.swift` 唯一改动，不改变 surface 生命周期、渲染驱动、键盘转发。

### Part 3：TerminalPanelView（NSViewRepresentable）

新建 `Terminal/TerminalPanelView.swift`：

```swift
import SwiftUI

struct TerminalPanelView: NSViewRepresentable {
    let cwd: URL
    let engine: any TerminalEngine

    func makeNSView(context: Context) -> NSView {
        engine.makeTerminalView(cwd: cwd)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // cwd 变化不触发 surface 重建（shell 自管 cwd）。
        // 文件工作台切换目录时，已有终端保持当前 shell 状态不变。
    }
}
```

只依赖 `TerminalEngine` 协议，不 `import GhosttyKit`。

### Part 4：ContentView 布局改造

当前布局（从上到下）：PathBarView → SearchBarView(条件) → FileTableView → 最近变化(固定 180pt)。

改造后：

```
PathBarView
SearchBarView (条件)
─────────── 上半部 ───────────
FileTableView
─────────── 分割线 ───────────    ← 仅 isTerminalVisible 时出现
TerminalPanelView                ← 仅 isTerminalVisible 时出现
─────────── 下半部 ───────────
最近变化 (固定 180pt)            ← 终端展开时隐藏
```

终端展开时，「最近变化」隐藏（两个底部面板不共存，M3 再设计面板 tab 切换）。终端收起时，「最近变化」恢复。

**分割线实现**：用 AppKit `NSSplitView` 包装（SwiftUI 的 `VSplitView` 对子视图约束粗糙，无法精确控制最小/最大高度）。或者用 SwiftUI `.frame` + `DragGesture` 实现可拖拽分割线（轻量、不引入新 AppKit 桥接）。

推荐后者（DragGesture）——只需一个 `@State var terminalHeight: CGFloat = 250` + 一个 4pt 高的拖拽条。终端面板最小 100pt、最大不超过窗口高度 60%。

### Part 5：WorkspaceModel 状态

`WorkspaceModel` 新增：

```swift
var isTerminalVisible: Bool = false
```

单一布尔值，控制终端面板展开/收起。不存储终端实例——终端 NSView 的生命周期由 SwiftUI view 树管理。

### Part 6：菜单命令 + 快捷键

`PathDeckApp.swift` 的 `TerminalCommands` 改造：

- 保留现有「打开终端（冒烟）」⌃⌥⌘T
- 新增「切换终端面板」⌃\`（toggle `model.isTerminalVisible`）

⌃\` 的 SwiftUI 绑定：`.keyboardShortcut("`", modifiers: .control)`。

Toolbar 按钮：ContentView toolbar 新增一个终端图标按钮（SF Symbol `terminal`），点击 toggle。

### Part 7：TerminalEngine 实例管理

`ContentView` 持有一个 `GhosttyTerminalEngine` 实例（`@State private var terminalEngine = GhosttyTerminalEngine()`），传给 `TerminalPanelView`。这是 ContentView 中唯一直接引用具体实现的位置——后续如果切换到 SwiftTerm fallback，只改这一行。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| **新增** `Terminal/TerminalEngine.swift` | 协议定义 |
| **新增** `Terminal/GhosttyTerminalEngine.swift` | 协议实现，包装 `GhosttySurfaceView` |
| **新增** `Terminal/TerminalPanelView.swift` | NSViewRepresentable，只依赖协议 |
| `Terminal/GhosttySurfaceView.swift` | 新增 `initialCwd` 属性，`createSurface()` 使用它 |
| `ContentView.swift` | 底部布局改造（终端面板 + 可拖拽分割线 + 条件隐藏最近变化） |
| `WorkspaceModel.swift` | 新增 `isTerminalVisible` |
| `PathDeckApp.swift` | 终端面板切换命令（⌃\`）+ Toolbar 按钮 |
| `Terminal/AGENTS.md` | 更新职责、目录结构、模块规范（协议已补） |

## 不改动

| 文件 | 理由 |
|---|---|
| `Terminal/GhosttyApp.swift` | runtime 单例不变，多 surface 由 `ghostty_surface_new` 自然支持 |
| `Terminal/TerminalSmokeView.swift` | 冒烟窗口保留，不改动 |
| `FileWorkspace/*` | 无关 |
| `ChangeJournal/*` | 无关（`ChangeListView` 只是被条件隐藏，不改其代码） |
| `PathDeck.xcodeproj/project.pbxproj` | 新文件在 synchronized group 内自动纳入；无新链接依赖 |

## Scope

- `TerminalEngine` 协议 + `GhosttyTerminalEngine` 实现
- 主窗口底部可展开/收起的 Terminal Panel
- Panel 初始 cwd = 当前工作区文件夹
- Toolbar 按钮 + ⌃\` 切换面板
- 可拖拽分割线调整面板高度
- 终端展开时隐藏「最近变化」面板

## Non-scope

- 多 Terminal Tab（FR-TERM-003，S10）
- Send Path / 拖拽文件到终端（FR-BRIDGE-001/002，S9）
- Terminal cwd 双向同步（FR-TERM-004，P1）
- 终端主题配色 Deck Dark 完整注入（需 `ghostty_config` 配置，独立切片）
- xterm-ghostty terminfo / shell-integration 资源打包
- IME / 完整键映射 / 复制粘贴 / 选区 / 滚动
- 命令预设 / Command Palette（FR-TERM-006，P2）

## 实现顺序

1. `TerminalEngine.swift` — 协议定义
2. `GhosttySurfaceView.swift` — 添加 `initialCwd` 属性
3. `GhosttyTerminalEngine.swift` — 协议实现
4. `TerminalPanelView.swift` — NSViewRepresentable
5. `WorkspaceModel.swift` — 添加 `isTerminalVisible`
6. `ContentView.swift` — 布局改造（分割线 + 终端面板 + 条件隐藏最近变化）
7. `PathDeckApp.swift` — 菜单命令（⌃\`）+ Toolbar 按钮
8. `Terminal/AGENTS.md` — 更新
9. build + 现有单测 + GUI 走查（7 条验收标准）

## 工作量

3 个新文件 + 4 个改动文件 + 1 个文档更新，~150 行新代码。
