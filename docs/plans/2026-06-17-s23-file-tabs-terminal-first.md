# S23：文件 Tab + Terminal-first 模式

> 状态：Done
> 前置：M5 闭合 + D1 Dogfood
> 目标：多目录并行浏览 + 终端工作上下文锚定 + Finder-first / Terminal-first 双模式切换

## 背景

PathDeck 当前是**单目录 + 多终端 session** 架构：一个 `WorkspaceModel` 管一个目录，终端 session 全局共享、不与目录关联。实际使用中两个痛点浮现：

1. 频繁在不同项目目录间切换，单目录无法并行浏览
2. 终端 session 与文件上下文割裂——在某个目录下开的终端，导航走了就失去关联

本需求引入**文件 Tab**（横向多目录）和 **Terminal-first 模式**（垂直终端 Tab + 全屏终端），通过 **anchor cwd** 机制把文件 Tab 和终端 session 绑定为一对多关系。

## Scope

- `FileTab` 数据模型 + `TabManager` 多 Tab 状态管理
- 文件 Tab bar UI（横向，PathBar 上方）
- 每个 FileTab 独立 `WorkspaceModel` 实例
- FileTab ↔ TerminalSession 一对多绑定 + anchor cwd 生命周期
- Terminal-first 模式布局 + 垂直 terminal tab bar UI
- Finder-first ↔ Terminal-first 模式切换
- 快捷键
- 持久化（重启恢复 file tabs + 终端关联 + 模式）

## Non-scope

- Tab 拖拽排序
- Tab 拖出为独立窗口
- Terminal split pane（水平/垂直分屏）
- Tab grouping / workspace 概念
- Tab 数量上限

## 设计

### 1. 数据模型

#### FileTab

```swift
struct FileTab: Identifiable {
    let id: UUID
    var title: String                    // 默认目录名，双击可编辑
    var isCustomTitle: Bool              // 是否用户自定义标题
    var mode: WorkspaceMode = .finderFirst  // per-tab 模式
    var isTerminalVisible: Bool = false  // per-tab 终端面板可见性
    var terminalAnchorCwd: URL?          // 终端锚定 cwd（nil = 未开过终端）
    var terminalSessionIDs: [UUID]       // 隶属的终端 session ID（有序）
    var activeTerminalID: UUID?          // 当前活跃终端 session
}
```

#### TabManager

```swift
@Observable final class TabManager {
    var fileTabs: [FileTab] = []
    var activeFileTabID: UUID?

    // 每个 tab 独立的 WorkspaceModel（tab 生命周期内存活）
    private var workspaceModels: [UUID: WorkspaceModel] = [:]

    // mode 为 per-tab（FileTab.mode），通过计算属性访问
    var activeTabMode: WorkspaceMode { get/set → fileTabs[activeIdx].mode }
    var activeTabTerminalVisible: Bool { get/set → fileTabs[activeIdx].isTerminalVisible }

    var activeTab: FileTab? { ... }
    var activeModel: WorkspaceModel? { workspaceModels[activeFileTabID] }

    func createTab(at url: URL) -> UUID { ... }
    func closeTab(_ id: UUID) { ... }
    func switchTab(to id: UUID) { ... }
    func toggleTerminalVisibility() { ... }
    func toggleActiveTabMode() { ... }
}
```

每个 `WorkspaceModel` 实例拥有独立的 `FSWatcher`、`items`、`sortColumn`、`searchQuery` 等状态。Tab 切换时无需快照/恢复——模型实例常驻内存，状态自然保持。

#### WorkspaceModel 多实例适配

当前 `WorkspaceModel` 用全局 UserDefaults key 持久化 `sortColumn`/`sortAscending`/`showHidden`。多实例时这些 key 冲突。处理方式：

- `sortColumn`/`sortAscending`/`showHidden` → 提升为全局偏好（所有 Tab 共享），由 `TabManager` 统一管理，`WorkspaceModel` 移除 didSet 持久化
- `lastOpenedFolder` → 废弃，改由 `TabManager` 持久化 Tab 列表取代
- `WorkspaceModel.init(root:)` 改为必传 `root` 参数，不再从 UserDefaults 读默认目录

### 2. Anchor CWD 生命周期

```
[Tab 无终端]                              [Tab 有终端]
anchorCwd = nil ──── 首次开终端 ────▶ anchorCwd = currentURL（冻结）
      ▲                                       │
      │                                       │ 继续开终端
      │                                       ▼
      │                              新 session.cwd = anchorCwd
      │                              （不管 tab 当前浏览到了哪里）
      │                                       │
      └──── 所有终端关闭，anchorCwd 清空 ◀────┘
```

规则：

1. 新建 FileTab → `anchorCwd = nil`，`terminalSessionIDs = []`
2. 在此 Tab 下首次开终端 → `anchorCwd` 冻结为此刻的 `model.currentURL`
3. 在此 Tab 下继续开终端 → 新 session 的 `cwd` 一律用 `anchorCwd`
4. Tab 内自由导航其他目录 → `anchorCwd` 不变，已有终端不受影响
5. Tab 提供"回到锚定目录"的快速入口（PathBar 上的锚点标记 + 点击回跳）
6. 该 Tab 下所有终端关闭 → `anchorCwd = nil`，回到状态 1
7. 终端 session 内部 `cd` 不受限制，OSC 7 cwd 同步照常运作

#### "回到锚定目录"入口

当 `anchorCwd != nil` 且 `anchorCwd != model.currentURL` 时，PathBar 左侧显示锚点按钮（⚓ 图标 + `anchorCwd.lastPathComponent`），点击 → `model.navigate(to: anchorCwd)`。

### 3. 布局与模式切换

#### Finder-first 模式（现有布局 + 文件 Tab bar）

```
┌──────────┬──────────────────────────────────────┐
│          │ [Tab1: Projects] [Tab2: Docs] [+]    │ ← FileTabBar (28pt)
│          ├──────────────────────────────────────┤
│          │ ⚓ Projects > src > components        │ ← PathBar (24pt, 含 anchor)
│ Sidebar  ├──────────────────────────────────────┤
│          │ FileTable              │ PreviewPane  │
│          ├──────────────────────────────────────┤
│          │ [T1] [T2] [+]                        │ ← 横向 TerminalTabBar (28pt)
│          │ Terminal (底部面板)                    │
└──────────┴──────────────────────────────────────┘
```

- FileTabBar 置于 PathBar 上方（新增）
- 底部终端面板保持现有横向 Tab bar 不变
- 终端面板仅显示**当前 FileTab 隶属的终端 session**

#### Terminal-first 模式

```
┌──────────┬──────────────────────────────────────┐
│          │ [Tab1: Projects] [Tab2: Docs] [+]    │ ← FileTabBar (28pt, 仍可见)
│          ├───────┬──────────────────────────────┤
│ Sidebar  │ T1    │                              │
│          │ T2    │  Terminal (全屏)              │
│          │ T3    │                              │
│          │ [+]   │                              │
│          │       │                              │
└──────────┴───────┴──────────────────────────────┘
             140pt
```

- FileTabBar 仍然可见（切换 Tab 会切换对应的终端 session 组）
- 文件列表/PreviewPane/底部终端面板全部隐藏
- 左侧垂直 Terminal Tab bar（~140pt）+ 右侧终端全屏
- 垂直 Tab bar 仅显示当前 FileTab 的终端 session

#### 模式切换

通过快捷键和 Toolbar 按钮切换。切换时保持所有状态（Tab 列表、终端 session、锚定关系）不变，只改布局。

### 4. FileTabBar UI

横向 Tab bar，高度 28pt，位于 PathBar 上方：

```swift
struct FileTabBar: View {
    var tabs: [FileTab]
    var activeTabID: UUID?
    var tabModels: [UUID: WorkspaceModel]  // 取目录名显示
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onNewTab: () -> Void
    var onRename: (UUID, String) -> Void
}
```

- 每个 Tab 项：目录名（`currentURL.lastPathComponent`）+ 关闭按钮（hover 显示）
- 有 `anchorCwd` 时 Tab 项显示终端图标（表示此 Tab 有锚定终端）
- 双击进入 inline 重命名
- 单击切换
- 右侧 `+` 按钮新建 Tab（cwd = 当前 Tab 的目录）
- 至少保留一个 Tab，最后一个 Tab 不显示关闭按钮
- Active 指示：底部 2pt accent 色条（与现有 TerminalTabBar 风格统一）

#### 滚动

Tab 超出可视宽度时水平滚动（`ScrollView(.horizontal)`）。

### 5. 垂直 Terminal Tab bar UI

Terminal-first 模式下的左侧终端 session 列表，宽度 140pt：

```swift
struct VerticalTerminalTabBar: View {
    var sessions: [TerminalSession]
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNewTab: () -> Void
    var onNavigateToCwd: ((URL) -> Void)?
}
```

- 每个 Tab 项：标题（一行，截断）+ cwd 末段（副文本，点击跳转文件浏览器）+ 关闭按钮（hover）
- 项高 ~36pt
- Active 指示：左侧 2pt accent 色条
- 底部固定 `+` 按钮（不随列表滚动）
- 超出可视高度时纵向滚动（`ScrollView(.vertical)`）
- 双击进入 inline 重命名

### 6. 快捷键

| 快捷键 | 功能 | 备注 |
|--------|------|------|
| `⌘T` | 新建文件 Tab | 与 Finder 一致 |
| `⌘W` | 关闭（终端焦点时关终端，否则关 Tab） | NSEvent local monitor 拦截，最后一个 Tab 时关窗口 |
| `⌃Tab` | 下一个文件 Tab | 标准 macOS |
| `⌃⇧Tab` | 上一个文件 Tab | 标准 macOS |
| `⌘1`…`⌘9` | 切换到文件 Tab #N | 与浏览器一致 |
| `⌃`` ` | 切换终端面板显隐 | 无终端时自动新建 |
| `⌃⇧N` | 新建终端 session（当前 Tab 下） | 终端可见时生效 |

#### `⌘W` 三层优先级（NSEvent local monitor）

1. 焦点在终端（`GhosttySurfaceView` 是 firstResponder）→ 关闭当前 terminal session
2. 焦点在文件区 + 多 Tab → 关闭当前 file tab
3. 单 Tab → 放行事件，系统关窗口

#### `⌃`` ` 终端 toggle

简单 show/hide 终端面板（Finder-first 模式下）。若无终端 session 则自动创建一个。模式切换（Finder-first ↔ Terminal-first）通过 Toolbar 按钮操作，模式跟随 FileTab（per-tab）。

### 7. 持久化

#### FileTabState（Codable）

```swift
struct FileTabState: Codable {
    let id: String                       // UUID string
    let title: String
    let isCustomTitle: Bool
    let mode: String                     // "finderFirst" / "terminalFirst"（per-tab）
    let isTerminalVisible: Bool          // per-tab 终端面板可见性
    let currentURLPath: String
    let anchorCwdPath: String?           // nil = 无锚定
    let terminalStates: [TerminalTabState]
    let activeTerminalIndex: Int?        // 按 session 列表索引还原
}
```

#### 存储 key

| Key | 内容 |
|-----|------|
| `fileTabsState` | `[FileTabState]` JSON（含 per-tab mode/isTerminalVisible） |
| `activeFileTabID` | UUID string |
| `sortColumn` | 全局排序列 |
| `sortAscending` | 全局排序方向 |
| `showHidden` | 全局显示隐藏文件 |
| `bottomPanelHeight` | 保留 |
| `previewPaneVisible` | 保留 |

废弃的 key：`terminalTabsState`（终端 tab 现在挂在 FileTab 下）、`lastOpenedFolder`（由 Tab 列表取代）、`workspaceMode`（mode 已内嵌到 FileTabState per-tab）、`bottomPanelVisible`（已内嵌到 FileTabState per-tab 的 `isTerminalVisible`）。

#### 恢复逻辑

1. 读 `fileTabsState` → 重建 FileTab 数组 + 每个 Tab 的 WorkspaceModel
2. 每个 Tab 的 `terminalStates` → 重建 TerminalSession + 调用 `terminalEngine.createSession`
3. 恢复 `activeFileTabID`、`workspaceMode`
4. 若无保存状态 → 创建单个 Tab（cwd = 上次目录或 Home）

### 8. AppRouter 适配

当前 AppRouter 路由直接作用于单个 WorkspaceModel。多 Tab 后规则：

| Route | 行为 |
|-------|------|
| `.open(url)` | 在当前 Tab 导航（不新建 Tab） |
| `.reveal(urls)` | 在当前 Tab 导航到父目录 + 高亮 |
| `.terminal(url)` | 找已有 Tab 的 `anchorCwd == url` 或 `currentURL == url` → 激活该 Tab + 开终端；否则新建 Tab + 开终端 |

### 9. ContentView 重构

当前 ContentView 直接持有 `@State model`、`@State terminalSessions` 等。重构后：

**移除的 @State**：
- `model: WorkspaceModel` → 由 `TabManager.workspaceModels[activeTabID]` 取代
- `terminalSessions: [TerminalSession]` → 由 `FileTab.terminalSessionIDs` + TerminalEngine 取代
- `activeTerminalID: UUID?` → 由 `FileTab.activeTerminalID` 取代

**新增的 @State**：
- `tabManager: TabManager`

**移除的方法**：
- `restoreTerminalTabs()` / `saveTerminalTabState()` → 合并到 TabManager 统一持久化

**workspaceContent 布局变化**：

```swift
// Finder-first
VStack(spacing: 0) {
    FileTabBar(...)                    // NEW
    PathBarView(...)                   // 现有（加 anchor 按钮）
    SearchBarView(...)                 // 现有
    HStack { FileTableView, PreviewPane }  // 现有
    if hasTerminals {
        TerminalDividerView(...)       // 现有
        BottomPanelBar(...)            // 现有（数据源改为当前 Tab 的 sessions）
        TerminalPanelView(...)         // 现有（sessionIDs=全 Tab 保活，activeSessionID=当前 Tab）
    }
}

// Terminal-first
VStack(spacing: 0) {
    FileTabBar(...)                    // NEW（仍可见）
    HStack(spacing: 0) {
        VerticalTerminalTabBar(...)    // NEW
        TerminalPanelView(...)         // 全屏
    }
}
```

根据 `tabManager.activeTabMode` 用 `if/else` 切换两种布局。TerminalPanelView 在两种模式下共用（NSViewRepresentable 用 `isHidden` 管理 surface，不受父布局影响）。

## 文件清单

### 新建

| 文件 | 说明 |
|------|------|
| `PathDeck/FileTab.swift` | FileTab 值类型 + FileTabState（Codable） |
| `PathDeck/TabManager.swift` | @Observable 多 Tab 状态管理 + 持久化 |
| `PathDeck/FileTabBar.swift` | 横向文件 Tab bar UI |
| `PathDeck/Terminal/VerticalTerminalTabBar.swift` | 纵向终端 Tab bar UI |

### 编辑

| 文件 | 变更 |
|------|------|
| `PathDeck/ContentView.swift` | 主重构：TabManager 替代单 Model；添加 FileTabBar；双模式布局切换；终端管理方法适配 per-tab session |
| `PathDeck/PathDeckApp.swift` | 新增快捷键（⌘T/⌃Tab/⌘1-9/⌃⇧N）；`⌃`` ` 改为 toggle 终端显隐；⌘W 通过 NSEvent local monitor 在 ContentView 实现 |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 移除 `lastFolderKey` 自恢复逻辑；`sortColumn`/`sortAscending`/`showHidden` 的 didSet 持久化移除（提升到 TabManager）；`init(root:)` 改为必传；移除 `isBottomPanelVisible`（提升到 TabManager） |
| `PathDeck/Terminal/TerminalTabBar.swift` | 无功能变更，仅 Finder-first 模式下继续使用 |
| `PathDeck/Terminal/TerminalPanelView.swift` | `sessionIDs` 传 `allTerminalSessionIDs`（跨 Tab 全集）以保活 surface；`activeSessionID` 为当前 Tab 的活跃 session |
| `PathDeck/AppRouter.swift` | `.terminal` 路由增加 Tab 匹配逻辑 |

### 文档

| 文件 | 变更 |
|------|------|
| `AGENTS.md` | 更新目录索引 + 变更日志 |
| `PathDeck/Terminal/AGENTS.md` | 新增 VerticalTerminalTabBar |
| `PathDeck/FileWorkspace/AGENTS.md` | WorkspaceModel 多实例说明 |

## 实施顺序

### Phase 1：文件 Tab 基础

1. `FileTab` + `FileTabState` 数据模型
2. `TabManager`（Tab CRUD + WorkspaceModel 实例管理）
3. `WorkspaceModel` 多实例适配（移除全局 key 持久化）
4. `FileTabBar` UI
5. `ContentView` 接入 TabManager（替代单 Model，FileTabBar 上屏）
6. 快捷键（⌘T/⌘W/⌃Tab/⌃⇧Tab/⌘1-9）
7. 持久化（Tab 列表 + activeTabID）

验证点：多 Tab 可用——新建/关闭/切换 Tab，各 Tab 独立目录状态，重启恢复。

### Phase 2：Terminal ↔ FileTab 绑定

1. `terminalSessions` 从 ContentView 全局 → FileTab per-tab
2. `createTerminalTab()` 适配 anchor cwd 生命周期
3. `closeTerminalTab()` 适配——最后一个 session 关闭时清 anchorCwd
4. `TerminalPanelView` sessionIDs 传 allTerminalSessionIDs（跨 Tab 保活 surface），activeSessionID 为当前 Tab 的活跃 session
5. PathBar anchor 按钮（回到锚定目录）
6. `⌃`` ` toggle 终端面板显隐（显示当前 Tab 的 session）
7. 持久化（Tab + 终端关联 + anchor）

验证点：终端锚定可用——Tab A 开终端锚定 `/a`，导航走，新建终端仍在 `/a`；Tab B 独立；关闭全部终端后 anchor 清空。

### Phase 3：Terminal-first 模式

1. `VerticalTerminalTabBar` UI
2. `FileTab.mode` per-tab + `workspaceContent` 双模式布局
3. `⌃`` ` 简化为 toggle 终端面板
4. Toolbar 模式切换按钮（toggleActiveTabMode）
5. 持久化（mode）

验证点：模式切换可用——Toolbar 按钮切换 Finder-first/Terminal-first，⌃` 仅 toggle 终端面板显隐，Terminal-first 下垂直 Tab 列表正确显示当前 Tab 的终端 session，mode 为 per-tab 互不干扰。

## 风险

| 风险 | 应对 |
|------|------|
| FileTableView（NSViewRepresentable）切 Tab 时状态残留（滚动位置、selection） | 每个 WorkspaceModel 独立 `items`/`selectedURLs`/`revealSelection`，NSTableView `reloadData` 时自然重置。若滚动位置需保留，在 Coordinator 里按 tabID 缓存 `visibleRect` |
| 多个 WorkspaceModel 的 FSWatcher 对同一目录重复监听 | FSEvents 允许多个 stream 监听同一路径，各自独立回调，无冲突 |
| TerminalPanelView.updateNSView 的 changed 守卫 | 当前按 `activeSessionID` + `isActive` 判断变化。Tab 切换会改变 sessionIDs 集合，需确保 coordinator 正确清理前 Tab 的 subview mapping |
| `WorkspaceModel.isBottomPanelVisible` 提升后与现有 UI 绑定断裂 | 已改为 per-tab `FileTab.isTerminalVisible`，ContentView 通过 `tabManager.activeTabTerminalVisible` 读写 |
| 内存：多 Tab 各持 WorkspaceModel + items 数组 | 可接受——单个 10k 目录的 `[FileItem]` ~1-2MB，Tab 数量通常 < 10 |

## 验收

- [ ] 新建/关闭/切换文件 Tab，各 Tab 独立目录、排序、搜索状态
- [ ] ⌘T/⌘W/⌃Tab/⌃⇧Tab/⌘1-9 全部生效
- [ ] Tab A 开终端 → anchor 冻结 → 导航走 → 新建终端 cwd 仍为 anchor → 关闭全部终端 → anchor 清空
- [ ] Tab 间终端 session 互不干扰
- [ ] PathBar anchor 按钮可见（anchor 存在且不是当前目录时），点击回到锚定目录
- [ ] ⌃` 终端 toggle：显示/隐藏终端面板（无终端时自动新建）；模式切换通过 Toolbar 按钮
- [ ] Terminal-first 模式下垂直 Tab 列表正确显示当前 Tab 的终端 session
- [ ] 切换文件 Tab 联动切换终端 session 组（两种模式下都正确）
- [ ] 重启恢复：文件 Tab 列表 + 终端 session + anchor 关系 + 模式
- [ ] 现有 126 单测不退化
