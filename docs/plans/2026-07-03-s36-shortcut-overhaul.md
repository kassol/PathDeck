# S36：快捷键收束 + 长按 ⌘ 浮窗 + 键位全面对齐

> 日期：2026-07-03　需求：shortcut-overhaul
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；键位语义决策见 `../adr/0001-return-renames-cmd-down-opens.md`。
> 全部关键决策已通过逐条拍板确认（2026-07-03 评审会）。

## 目标

1. **收束**：建立 `ShortcutRegistry` 作为全部快捷键元数据（键位 + 标题 + 分组 + 焦点语境 + 预留标记）的唯一真相源；菜单与 monitor 手写但引用注册表常量；`appReservedShortcuts` 与浮窗内容完全派生；单测遍历查重。
2. **浮窗（Shortcut Overlay）**：单独按住 ⌘ 800ms（期间无按键、无鼠标按下）→ keyWindow 的 WorkspaceRootView 顶层淡入材质卡片，全量分组展示快捷键；松开 ⌘ 淡出；显示期间执行组合键保持显示；任何 mouseDown 立即隐藏并取消本轮（保护 ⌘+点击多选）。
3. **键位全面对齐**（目标态总表见下）。
4. **⌘↓ 打开选中项**：补齐键盘打开路径（inline 重命名与 Return 触发在 S35 已存在，评审时误判为缺失，实现阶段修正——本切片只需新增 ⌘↓ 并给 Return 加纯键守卫）。
5. **状态归属修正**：Sidebar 与 Preview Pane 显隐迁为逐窗口 Session State（符合 CONTEXT.md 判据）；旧全局 `isPreviewPaneVisible` 值作为无快照窗口的默认。

## 键位总表（目标态）

### 视图
| 键 | 动作 | 变化 |
|---|---|---|
| ⌘B | Sidebar 显隐 | **新增**（VS Code 惯例） |
| ⌘⇧B | Preview Pane 显隐 | **新增**，接替 ⌘⇧P |
| ⌃` | 终端面板显隐 | 不变 |
| ⌘⇧. | 隐藏文件显隐 | 不变 |
| 长按 ⌘ | Shortcut Overlay | **新增** |

### 文件操作
| 键 | 动作 | 变化 |
|---|---|---|
| Return | 重命名（inline） | 不变（S35 已实现），加纯键守卫，ADR-0001 |
| ⌘↓ | 打开选中项 | **新增**（键盘打开路径此前缺失） |
| Space | Quick Look | 不变 |
| ⌘↑ | 上级目录 | 不变 |
| ⌘⇧N / ⌘Delete / ⌘C / ⌘V / ⌘⌥V / ⌘A / ⌘D / ⌘⌥C / ⌘F / ⌘O | 同现状 | 不变（已与 Finder 一致） |

### 终端
| 键 | 动作 | 变化 |
|---|---|---|
| ⌃⇧` | New Terminal | **换键**，接替 ⌃⇧N（与 ⌃` 成对，VS Code 惯例） |
| ⌘↩ | Send Path to Terminal | **换键**，接替 ⌘⇧T（「提交/执行」语义） |
| ⌘⇧T（终端焦点分支同 ⌘T） | — | 见预留位 |

### 工作台 / Tab
| 键 | 动作 | 变化 |
|---|---|---|
| ⌘T | New Tab（文件焦点）/ New Terminal（终端焦点） | 不变，浮窗双语义并列标注 |
| ⌘W | 关终端（终端焦点）/ 关窗口 | 不变 |
| ⌘1..9、⌃Tab、⌃⇧Tab | Tab 切换 | 不变 |
| ⌘⇧R | Rename Workspace… | 不变 |

### 预留位（Reserved Shortcut，注册表标记，不绑动作、不进菜单与浮窗）
| 键 | 预留用途 |
|---|---|
| ⌘⇧P | 命令面板（VS Code/Zed/Sublime 事实标准） |
| ⌘⇧T | 重开关闭的 Tab（浏览器/VS Code 强惯例） |

## 架构决策（已拍板）

| 决策点 | 结论 |
|---|---|
| 右侧边栏定义 | 就是 Preview Pane，⌘⇧B 替代 ⌘⇧P |
| 显隐状态归属 | Sidebar 与 Preview Pane 均逐窗口 Session State，迁移 `isPreviewPaneVisible` |
| 浮窗触发 | 800ms 阈值；阈值内任意按键取消计时；执行快捷键后保持显示；松开 ⌘ 淡出；mouseDown 立即隐藏并取消本轮 |
| 收束深度 | 元数据注册表唯一真相源；菜单/monitor 手写引用常量；appReservedShortcuts 与浮窗派生；单测查重 |
| 浮窗内容 | 全量分组单屏（约 25 项），双语义键（⌘T/⌘W）并列标注生效焦点 |
| 浮窗形态 | 窗口内 SwiftUI overlay（ultraThinMaterial 卡片，`allowsHitTesting(false)`，淡入淡出），per-window viewState 驱动，仅 keyWindow 触发 |
| 范围 | 全面重排（上表全部落地），inline rename 本切片一并实现 |

## 实现要点

- **长按检测**：`WorkspaceController` 新增 `.flagsChanged` local monitor（与现有三 monitor 并列、严格 `keyWindow == self.window`、只观察不吞事件，终端的修饰键转发不受影响）；辅以 `.keyDown`（取消计时）与 `.leftMouseDown/.rightMouseDown/.otherMouseDown`（取消本轮）观察。仅 `modifierFlags` 恰为 `.command` 时起计时；出现其他修饰键即取消。
- **注册表**：`ShortcutRegistry` 静态表；条目含 key/modifiers/标题(本地化 key)/分组/焦点语境(通用|文件|终端)/reserved 标记。`appReservedShortcuts` 由注册表过滤生成；浮窗按分组渲染非 reserved 条目。单测：无重复（键+修饰组合 × 语境）、reserved 不与生效项冲突。
- **⌃⇧` 拦截风险**：Ghostty 层 Ctrl 组合直发终端（Terminal/AGENTS.md:59）；需验证 ⌃⇧` 在终端焦点下能到达菜单/monitor，若被 surface 吞掉则在 performKeyEquivalent 白名单特判（同 ⌃` 现状对齐）。
- **⌘↓ 打开**：FileNSOutlineView keyDown 处理 ⌘+↓（单选时），与双击共用 `openRow` 路径；Return 分支加 `flags.isEmpty` 守卫，⌘↩ 不落入重命名兜底。inline rename 本身 S35 已存在（右键菜单/新建文件夹同路径），无需新建。
- **状态迁移**：session 快照增加 `isSidebarVisible`、`isPreviewPaneVisible`；`NavigationSplitView` 绑 `columnVisibility`；旧全局 preference 读一次作默认后废弃字段。
- **派发机制**：新菜单项沿用 Commands + `keyWorkspaceController()` 严格读路径（与 ⌘⇧P 现状同路径）；Return/⌘↓/Space 留在 FileNSOutlineView keyDown；走查须覆盖文件焦点与终端焦点。

## 验证

- 单测：注册表查重与派生一致性（`ShortcutRegistryTests`）；长按状态机全语义（`ShortcutOverlayHoldTrackerTests`，注入调度同步驱动）；session 快照新字段 roundtrip + 旧快照兼容（`WorkspacePersistenceTests`）。rename 逻辑既有测试覆盖（`WorkspaceModelFileOpsTests`）。
- 手动走查（视觉/交互）：长按 800ms 出浮窗、松开消失、⌘C 快速按不闪现、浮窗期间执行 ⌘B 生效且浮窗保持、⌘+点击多选浮窗不弹、双窗口仅 keyWindow 弹；⌘B/⌘⇧B 两侧显隐且逐窗记忆重启还原；终端焦点下 ⌃⇧`、⌘↩、⌘⇧B 生效；Return 重命名 Esc 取消、⌘↓ 打开。
