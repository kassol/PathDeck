# S37：预留位转正——Command Palette + Reopen Closed Tab

> 日期：2026-07-03　需求：补齐 S36 注册表中两个 Reserved Shortcut 的实现
> 权威产品定义见 `../prd.md`（7.2 Command Palette）；工作约束见根 `AGENTS.md`；术语见根 `CONTEXT.md`（Command / Command Palette / Close History / Reopen）。
> 全部关键决策已通过逐条拍板确认（2026-07-03 grilling 评审）。

## 目标

1. **⌘⇧P Command Palette**：窗口内命令搜索浮层，全量命令可搜、不可用置灰、模糊匹配、回车执行。
2. **⌘⇧T Reopen Closed Tab**：双语义对称 ⌘W——终端焦点重开最近关闭的终端 session，其他焦点重开最近关闭的 workspace 窗口。
3. **注册表升级为命令表**：`ShortcutSpec` 增加动作与可用性，Palette 内容 100% 派生；菜单层 action 一次到位改引命令表。

## 已拍板决策

| 决策点 | 结论 |
|---|---|
| 范围 | 两个预留位都实现，注册表不再留 reserved 条目 |
| ⌘⇧T 语义 | 双语义对称 ⌘W（终端焦点 → 重开终端；否则 → 重开窗口） |
| 栈归属 | 终端关闭栈 per-window（挂 WorkspaceController），窗口关闭栈全局（挂 WorkspaceManager） |
| 栈生命周期 | 栈式可连按回退，上限 10，仅进程内，不落盘 |
| 入栈条件 | 仅用户关闭手势（⌘W、关闭按钮）；shell exit（engine 回调）不入栈 |
| 重开窗口归位 | 原 tab 组仍有存活窗口 → tab 回原组；组已空 → 按关闭时 frame 恢复独立窗口 |
| 命令源 | ShortcutRegistry 升级为命令表（每条加 action + isEnabled，入参 WorkspaceController） |
| 命令范围 | 仅注册表非 reserved/system 条目（双语义各自成条），不新增无键位命令 |
| 重构粒度 | 菜单层（PathDeckApp）action 一次到位改调命令表；monitor 与 FileTableView 内部键处理（keyDown / responder chain）保持现状 |
| Palette UI | 窗口内 SwiftUI overlay（顶部居中，输入框 + 结果列表），per-window viewState 驱动，与 Shortcut Overlay 同模式 |
| 可用性 | 全量列出，isEnabled 为 false 置灰不可执行；fileFocus 命令作用于文件列表当前选中 |
| 匹配 | subsequence fuzzy（词首/连续命中加权），无输入按分组序全列；V1 无 MRU |
| 键盘交互 | ↑↓ 选择、↩ 执行并关闭、Esc 关闭还焦点（行业标准，未单独评审） |
| 可见性 | ⌘⇧P 进 View 菜单（Command Palette…）、⌘⇧T 进 Tabs 菜单（Reopen Closed Tab）；两条去掉 isReserved 进浮窗；补终端拦截 `p`+shift、`t`+shift |

## 实现要点

### 1. 命令表（ShortcutRegistry 升级）

- `ShortcutSpec` 增加 `action: (@MainActor (WorkspaceController) -> Void)?` 与 `isEnabled: (@MainActor (WorkspaceController) -> Bool)`（默认恒真）。system 组与纯展示项（长按 ⌘）action 为 nil。
- 双语义键已是独立条目（`newTab`/`newTerminalTab`、`closeWindow`/`closeTerminal`），各绑各的 action；⌘⇧T 依同模式拆 `reopenClosedWindow`（fileFocus）与 `reopenClosedTerminal`（terminalFocus）两条。
- 依赖选中项的命令挂谓词：`moveToTrash`/`duplicate`/`copy`/`sendPathToTerminal` 等要求非空选中，`renameFile` 要求单选；`reopenClosed*` 要求对应栈非空。
- PathDeckApp 各菜单 Button 的闭包改为「解析目标 controller（沿用 `keyWorkspaceController()` / `workspaceManager()` 兜底路径）→ 调命令表 action」；responder-chain 型命令（copy/paste/moveItemHere/duplicate/selectAll）的 action 封装现有 `NSApp.sendAction` 派发，语义不变。
- `ShortcutRegistryTests` 增加：非 system/展示项 action 非 nil；reserved 集合为空后原「reserved 不与生效项冲突」断言随之调整。

### 2. Close History（Reopen）

- **窗口栈（WorkspaceManager）**：`controllerWillClose` 在移除 controller 前捕获 `windowStateFor(c)` + 窗口 frame + 同 tab 组 sibling controller 弱引用数组，push 进 `closedWindowStack`（上限 10，FIFO 淘汰最旧）。`reopenClosedWindow()`：pop → `restoreController(from:)` 重建 → sibling 中首个仍存活者作 tab 宿主 `addTabbedWindow`；全没了 → 独立窗口 `setFrame(记录 frame)`（过 `validatedOnScreen` 校验）→ makeKey。注意 Cmd+Q 路径同样触发入栈，进程退出栈随之消亡，无需特判。
- **终端栈（WorkspaceController）**：`closeTerminal(_:)` 加来源参数（默认 UI 手势入栈；`handleEngineSessionClose` 传不入栈）。入栈内容：title、cwd、isManuallyRenamed、关闭时 index。`reopenClosedTerminal()`：pop → `createTerminal(cwdOverride:)` → 恢复标题（isManuallyRenamed 时走 `renameTerminal(manual: true)`）→ `reorderTerminal` 回原 index（clamp 到当前范围）。
- **⌘⇧T 派发**：WorkspaceController 新增 monitor 分支（同 ⌘T monitor 模式：严格 keyWindow，first responder 是 GhosttySurfaceView → 终端栈，否则 → manager 窗口栈）；Tabs 菜单项作 Settings 焦点时兜底，栈空时 disabled。

### 3. Command Palette

- `WorkspaceViewState` 增 `isCommandPaletteVisible`；`WorkspaceRootView` 顶层 overlay（材质卡片：TextField + 结果列表），与 Shortcut Overlay 并列。
- 焦点管理：呼出时记录当前 first responder，输入框 makeFirstResponder；Esc/执行后关闭并还焦点。终端焦点下呼出需验证 GhosttySurfaceView 让位/复位（风险点，见验证）。
- 匹配为纯函数 `CommandPaletteFilter.rank(query:specs:)`：subsequence 命中才保留，词首命中 > 连续命中 > 散点命中；无输入按 `overlayColumns` 分组序全列。可单测。
- 行渲染：标题 + 键帽 tokens + 语境 badge（复用浮窗的双语义标注）；isEnabled false 置灰、↑↓ 跳过、↩ 无效。
- ⌘⇧P 触发：View 菜单 keyboardShortcut + monitor 分支（终端焦点可用）；`reservedInTerminal` 补 `p`+shift 与 `t`+shift 后 GhosttySurfaceView 拦截集合自动派生。

## 验证

- 单测：命令表完整性（action/isEnabled 覆盖、查重沿用）；fuzzy 匹配排序（词首/连续/散点/不命中）；窗口栈 push/pop/上限/sibling 失效降级（可注入假 controller 列表）；终端栈 exit 不入栈、index 恢复 clamp；`WorkspacePersistence` 不受影响（关闭历史不落盘，无快照字段变化）。
- 手动走查（视觉/交互）：
  1. 文件焦点 ⌘⇧P → palette 浮层弹出、输入框聚焦 → 输入 "trash"（无选中）→ Move to Trash 置灰 ↩ 无效 → Esc 关闭、焦点回文件列表。
  2. 终端焦点 ⌘⇧P → 能呼出（不落入终端）；执行 "New Terminal Tab" → 新终端建立。
  3. ⌘W 关一个带自定义标题的终端 → ⌘⇧T（终端焦点）→ 同 cwd、同标题、回原位置；shell 内 exit → ⌘⇧T 不复活它。
  4. 关一个 tab 组内窗口 → ⌘⇧T（文件焦点）→ tab 回原组；关组内全部窗口后 ⌘⇧T → 按原 frame 独立窗口恢复、终端组随快照重建。
  5. 连关 3 个终端后连按 ⌘⇧T 3 次逐个回退；第 4 次无动作。
  6. 长按 ⌘ 浮窗出现 Command Palette 与 Reopen Closed Tab 两条新条目。
