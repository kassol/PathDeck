# S32 NSWindow Tabbing — File Tab 升级原生 + Terminal Tab 视觉对齐

> 日期：2026-06-18
> 前置：S31 已合入（自绘三域 reorder 全部跑通）
> 触发：Sir 反馈"文件 tab 和 terminal 横向 tab 为什么不用 macOS 自带的机制？Finder 也有 tab，又好看，拖动排序又是自然的"

## 一句话

文件 tab（workspace 级）改走 NSWindow tabbing 拿系统能力（拖出/合并 / Mission Control / Window menu / `Cmd+1..9` / 视觉随系统升级）；terminal 横向 tab（pane 级）保留自绘，视觉对齐 Finder/Safari NSWindowTab 设计 token。两层 tab 机制不同但观感统一。

## 关键澄清（与 Sir 的对话锚定）

- **文件 tab = workspace**：每个 tab 自带 outline + editor + terminal session（一对多）+ 左右 sidebar，三者协同对应同一个激活 file tab
- **左右 sidebar 都是 per-tab**：操作目标与显示内容都跟随激活 file tab，不是跨 window 共享内容（只有 Pinned/Favorites 偏好数据全局共享）
- **Terminal 横向 tab 留作 pane 级 tab**：一个 file tab/workspace 允许多个 terminal session（VS Code 风格），不能用 NSWindow tabbing（系统不支持嵌套 tab group）

## 现状锚点

| 层 | 现在 | 改后 |
|---|---|---|
| File tab 容器 | 单 NSWindow（SwiftUI `Window("PathDeck", id: "main")`）+ 自绘 `FileTabBar` | N 个 NSWindow，系统 tab bar 在 title bar，相同 `tabbingIdentifier` 自动合并 |
| File tab 状态 | `TabManager` 单实例集中持有 `fileTabs: [FileTab]` + `workspaceModels: [UUID: WorkspaceModel]` + `terminalSessions: [UUID: TerminalSession]` | 每个 NSWindow 持有一个 `WorkspaceController`，本地拥有 WorkspaceModel + sessions |
| File tab 切换 | `tabManager.activeFileTabID` 变化驱动 SwiftUI 重渲染 | 系统 `windowDidBecomeKey` / `selectNextTab(_:)`，无业务介入 |
| File tab 重排 | S31 `tabManager.moveFileTab(source:to:)` + `.draggable` + `.dropDestination` | 系统拖拽（免费，S31 file tab 自绘 reorder 代码退役） |
| File tab 持久化 | `fileTabsState` (`[FileTabState]`) + `activeFileTabID` 单 key | `fileTabsState` 升级为 per-window state 数组 + window 顺序；activeFileTabID → activeWindow 由系统恢复 |
| Terminal 横向 tab | 自绘 `TerminalTabBar` / `VerticalTerminalTabBar`（S31 已加 reorder） | 保留自绘，视觉对齐 NSWindowTab（圆角、间距、活跃态色阶、拖拽 ghost、邻居让位）|
| 全局偏好 | TabManager 持 `sortColumn` / `sortAscending` / `showHidden` | 上移到 `WorkspacePreferences` 单实例，所有 window 订阅 |
| Sidebar 数据 | `PinnedFolders` 单实例 | 不变（本来就单实例），每个 window 各自渲染 `SidebarView`，DOM 多份、数据源一份 |
| URL Scheme / Services / Open With | `AppRouter` → `tabManager.findTabByAnchorOrCwd` → 复用或新建文件 tab | `AppRouter` → 遍历所有 window 找匹配 cwd → 激活该 window 或新建 window 并 `addTabbedWindow(_:ordered:)` 到 key window |
| `Cmd+W` / `Cmd+T` / `Cmd+1..9` | NSEvent local monitor + SwiftUI `.keyboardShortcut` | NSEvent monitor 改为针对 keyWindow；`Cmd+1..9` 走 `NSWindow.selectNextTab` 序列或系统自带 |
| Settings 窗口 | SwiftUI `Settings { SettingsView() }` | 不变，`tabbingMode = .disallowed` 防止被并入 |

## 技术决策

| # | 决策 | 理由 |
|---|------|------|
| D1 | 改用 AppKit 自管 NSWindow，删 `Window("PathDeck", id: "main")` scene | SwiftUI `Window` / `WindowGroup` 都不暴露 `tabbingIdentifier` / `addTabbedWindow`；必须降到 NSWindow 层。SwiftUI 仍为渲染层（`NSHostingController` 包 root view），不全盘改 AppKit |
| D2 | 每个 NSWindow 一个 `WorkspaceController: NSWindowController`，持有 `WorkspaceModel` + `[TerminalSession]` + 模式/可见性等 per-window 状态 | 用 NSWindowController 而非 NSWindowDelegate 是因为 controller 自动管理 window 生命周期 + key/main 切换；`workspaceController(forWindow:)` 反查就一行 |
| D3 | `tabbingIdentifier = "in.riverflows.PathDeck.workspace"` 固定，`tabbingMode = .preferred` | 同 ID 自动合并；preferred 表示"用户首选 tab"，新窗口默认合入 key window 的 tab 组（用户可在 System Settings 全局改成 always/never） |
| D4 | `WorkspacePreferences` 单实例上移（sort / showHidden / preview pane 可见性等全局偏好） | 这些偏好本来就是 app 级，per-window 改值要通知所有 window 同步；用 `@Observable` 单实例 + 各 window root view 注入 |
| D5 | `PinnedFolders` 保持单实例 | 偏好数据全局共享；window 内 `SidebarView` 各自渲染同一份 `@Observable` 引用 |
| D6 | 删除 `TabManager` | per-tab 状态全部下放到 `WorkspaceController`；跨 tab 共享全部上移到 `WorkspacePreferences`；TabManager 不再有职责 |
| D7 | Terminal 横向 tab 自绘视觉 token 对齐 NSWindowTab | 抄系统：tab 圆角 ~8pt（macOS Tahoe 视觉），活跃态 `controlBackgroundColor`，非活跃态 `windowBackgroundColor.opacity(0.6)`，分隔线 1pt `separatorColor`，关闭按钮 hover 才显形，整体高度对齐 NSWindowTab |
| D8 | Terminal 拖拽 ghost 用 tab snapshot | `NSItemProvider` + 当前自绘 tab 视图截图作为 dragging image；邻居 spring 让位用 SwiftUI `.transition` + `.animation(.spring)` |
| D9 | 持久化模型升级：`fileTabsState`（旧 single store）→ `workspaceWindowsState`（新 per-window 数组）+ window 顺序 | 旧 key 在迁移代码里读一次转成新格式后清除；不留长期 fallback |
| D10 | `Cmd+1..9` 不再绑 SwiftUI `.keyboardShortcut`，全部走 NSEvent local monitor 操作 keyWindow 的 `tabbedWindows[index]` | SwiftUI `.keyboardShortcut` 是 scene 级，多 window 下作用域语义混乱；NSEvent monitor 显式针对 keyWindow 干净 |
| D11 | 不引入 SwiftUI `WindowGroup` 混用 | `WindowGroup` 多实例 scene 与 NSWindow 自管会争抢 window 生命周期 + state restoration 互踩；只用 AppKit 一套 |
| D12 | Quit on last window close？保留默认（不退出，菜单栏常驻） | macOS 默认行为；用户从 Dock 重新点击会通过 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 复原最后一组 window |

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P1 | Refactor | AppKit 接管 window 生命周期：`PathDeckApp` 拆 Window scene → `AppDelegate` 自建 NSWindow + `WorkspaceController` | `PathDeck/PathDeckApp.swift`, `PathDeck/AppDelegate.swift`（新增/拆分）, `PathDeck/Workspace/WorkspaceController.swift`（新增）|
| P2 | Refactor | NSWindow tabbing 启用：`tabbingIdentifier` + `tabbingMode = .preferred` + "New Tab" 命令 → 新建 window + `addTabbedWindow`；删除 `FileTabBar` 调用点 | `PathDeck/Workspace/WorkspaceController.swift`, `PathDeck/ContentView.swift`, `PathDeck/PathDeckApp.swift`（菜单命令）|
| P3 | Refactor | 状态拆分：删 `TabManager`，新增 `WorkspacePreferences` 单实例 + `WorkspaceController` per-window 状态；`WorkspaceModel` / `TerminalSession` / Terminal sessions 全部下放到 controller | `PathDeck/TabManager.swift`（删除）, `PathDeck/WorkspacePreferences.swift`（新增）, `PathDeck/Workspace/WorkspaceController.swift`, `PathDeck/ContentView.swift`, `PathDeck/PathDeckApp.swift`（菜单命令绑定改 `@FocusedValue` → AppKit `firstResponder`）|
| P4 | Refactor | 持久化迁移：旧 `fileTabsState` 一次性读取转换为 `workspaceWindowsState`（每个 window 一份 state + window 顺序数组）；启动按顺序重建 N window + `addTabbedWindow` 串接；旧 key 清除 | `PathDeck/Workspace/WorkspacePersistence.swift`（新增）, `PathDeck/Workspace/WorkspaceController.swift` |
| P5 | Refactor | `AppRouter` 路由改造：URL Scheme / Services / Open With 找匹配 cwd 的 window → 激活；找不到 → 新建 window 并合入当前 key window 的 tab 组 | `PathDeck/AppRouter.swift`, `PathDeck/Workspace/WorkspaceController.swift` |
| P6 | Refactor | 快捷键迁移：`Cmd+W`（关 window/tab 一致系统语义，删自定义 monitor 的"关 file tab"分支）/ `Cmd+T`（终端焦点新建 terminal、否则新建 NSWindow tab）/ `Cmd+1..9`（NSEvent monitor → `tabbedWindows[n-1].makeKeyAndOrderFront`）；`Ctrl+Tab` / `Ctrl+Shift+Tab` → `selectNextTab(_:)` / `selectPreviousTab(_:)` | `PathDeck/ContentView.swift`, `PathDeck/PathDeckApp.swift` |
| P7 | Feat | Terminal 横向 tab 视觉对齐 NSWindowTab token：圆角/间距/活跃态/分隔线/关闭按钮 hover 显形 | `PathDeck/Terminal/TerminalTabBar.swift`, `PathDeck/Terminal/VerticalTerminalTabBar.swift` |
| P8 | Feat | Terminal 拖拽 ghost = tab snapshot + 邻居 spring 让位 + drop 弹性归位 | `PathDeck/Terminal/TerminalTabBar.swift`, `PathDeck/Terminal/VerticalTerminalTabBar.swift` |
| P9 | Cleanup | 删除 `FileTabBar.swift`、`FileTab.swift` 内"isCustomTitle / mode / isTerminalVisible / activeTerminalID"等 per-tab 字段（已下放到 WorkspaceController）；`FileTabDragID` Transferable / `pathDeckFileTab` UTType 清除（系统接管）；Info.plist 对应 UTExportedTypeDeclarations 移除 file tab 项保留 terminal session 项 | `PathDeck/FileTabBar.swift`（删除）, `PathDeck/FileTab.swift`（精简或删除）, `PathDeck/ReorderTransferables.swift`, `PathDeck/Info.plist`, `PathDeck/ArrayMove.swift`（若仅 file tab 用即删除）|
| P10 | Test | per-window state 持久化 / 迁移 / `WorkspaceController` 生命周期 / `AppRouter` 跨 window 路由 / `Cmd+1..9` 切换 / Terminal tab 视觉对齐快照 | `PathDeckTests/WorkspaceControllerTests.swift`（新增）, `PathDeckTests/WorkspacePersistenceTests.swift`（新增）, `PathDeckTests/AppRouterTests.swift`（追加）, `PathDeckTests/TabManagerTests.swift`（删除）|
| P11 | Docs | AGENTS.md（项目概述、目录索引、变更日志）+ `docs/prd.md`（如涉及 tab 心智章节）同步 | `AGENTS.md`, `docs/prd.md` |

**Phase 独立性自检**：

- P1+P2 合并可 ship：能开多个 NSWindow tab，但 per-window 状态还在旧 TabManager 上，体验是"file tab 系统、terminal/sidebar 共享"——不 ship 出去（中间态怪异）
- P1–P6 合并可 ship：file tab 走系统全套，business 状态 per-window 化，URL 路由跨 window；terminal tab 视觉沿旧。**这是第一个可 ship 节点**
- P7–P8 独立可 ship：terminal tab 视觉/交互升级；不做也不影响 P1–P6 功能

切分为两个 release 节点：**Release A**（P1–P6 + P9 + P10 + P11） = NSWindow tabbing 上线；**Release B**（P7 + P8） = terminal tab 视觉抛光。

## Not Building

- **Phase 0 spike**（Sir 直选 B：边写边验，不预 spike）
- **Settings 窗口加入 tab 组**（明确 `tabbingMode = .disallowed`）
- **跨 window 拖动 terminal session**（terminal 仍 per-window 拥有，跨 window 拖出需要全新 session 拆分/迁移协议，非本需求）
- **`Cmd+Shift+T` 重开关闭的 tab**（macOS 系统本身不提供，自建需要 closed-window-history，非本需求）
- **`Move Tab to New Window` 自定义菜单**（系统 Window menu 已自带 `Show All Tabs in Mission Control` / `Move Tab to New Window`，免费拿到）
- **多 workspace 同窗内嵌**（已被现 NSWindow tabbing 方案覆盖，不再单独做）
- **VS Code 风格 file tab pin/unpin**（非本需求；系统 tab 无 pin 概念）
- **替换 Terminal-first 模式的纵向 terminal tab bar 视觉**（同步在 P7/P8 一起对齐，但不引入额外视觉差异）
- **Mission Control tab 缩略图自定义**（系统默认快照，不自定义）

---

## Phase 1：AppKit 接管 window 生命周期

### 目标

`PathDeckApp` 删 `Window` scene，改为 `AppDelegate` 在 `applicationDidFinishLaunching` 里手动创建 NSWindow + 挂 `NSHostingController(rootView: WorkspaceRootView())`。`WorkspaceController: NSWindowController` 持有 window + root view 注入的 `@Observable` 状态。

### 关键代码骨架

```swift
// PathDeckApp.swift
@main
struct PathDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    init() { ShellIntegration.prepare() }
    var body: some Scene {
        Settings { SettingsView() }
        // Window scene 删除；window 由 AppDelegate 自管
    }
}

// AppDelegate.swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var workspaceManager: WorkspaceManager!
    func applicationDidFinishLaunching(_ n: Notification) {
        workspaceManager = WorkspaceManager()
        workspaceManager.restoreSession()  // 重建 N window + addTabbedWindow
        if workspaceManager.controllers.isEmpty {
            workspaceManager.openNewWindow(cwd: FileManager.default.homeDirectoryForCurrentUser)
        }
    }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows v: Bool) -> Bool {
        if !v { workspaceManager.openNewWindow(cwd: ...) }
        return true
    }
}

// WorkspaceController.swift
final class WorkspaceController: NSWindowController, NSWindowDelegate {
    let workspace: WorkspaceModel
    let terminalSessions: TerminalSessionStore  // per-window
    let viewState: WorkspaceViewState           // per-window @Observable (mode/isTerminalVisible/...)
    init(cwd: URL, engine: TerminalEngine) { ... }
    func windowDidBecomeKey(_ n: Notification) { /* 触发 AppRouter 等 */ }
    func windowWillClose(_ n: Notification) { /* 关闭所有 terminal session */ }
}
```

### 验证

构建 + 启动 app；能开 1 个 window；点击 "File → New Tab"（即 `Cmd+T`）能开第二个 window 并自动并入同一 tab 组（系统 tab bar 出现）；关闭 tab 行为符合系统语义。

### 风险

- `NSHostingController` 包 SwiftUI 在 tab 切换 / window 拆分时 state 不丢——P1 末必须手测验证一次
- `ShellIntegration.prepare()` 在 SwiftUI App `init` 内调用顺序保留不变

---

## Phase 2：启用 NSWindow tabbing

### 关键代码

```swift
extension WorkspaceController {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.tabbingIdentifier = "in.riverflows.PathDeck.workspace"
        window?.tabbingMode = .preferred
    }
}

// WorkspaceManager.swift
final class WorkspaceManager {
    private(set) var controllers: [WorkspaceController] = []
    func openNewWindow(cwd: URL, tabbedTo existing: NSWindow? = nil) {
        let controller = WorkspaceController(cwd: cwd, engine: sharedEngine)
        controllers.append(controller)
        if let existing { existing.addTabbedWindow(controller.window!, ordered: .above) }
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
```

### 菜单 New Tab 改造

```swift
// PathDeckApp.swift / TabCommands
Button("New Tab") {
    (NSApp.delegate as? AppDelegate)?.workspaceManager.openNewWindow(
        cwd: NSApp.keyWindow?.workspaceController?.workspace.currentURL ?? home,
        tabbedTo: NSApp.keyWindow
    )
}.keyboardShortcut("t")
```

### 验证

- 开三个 tab → 系统 tab bar 三条
- 拖拽分离一个 tab → 独立 window
- 拖回去 → 合并
- Window menu 列出全部 tab
- Mission Control 缩略图正常
- `Cmd+1` `Cmd+2` `Cmd+3` 切换（P6 之后）

---

## Phase 3：状态拆分（删 TabManager）

### 拆分映射

| 旧 TabManager 字段/方法 | 新归宿 |
|---|---|
| `fileTabs: [FileTab]` | `WorkspaceManager.controllers: [WorkspaceController]` |
| `activeFileTabID: UUID?` | `NSApp.keyWindow` |
| `workspaceModels: [UUID: WorkspaceModel]` | `WorkspaceController.workspace` |
| `terminalSessions: [UUID: TerminalSession]` | `WorkspaceController.terminalSessions: TerminalSessionStore` |
| `sortColumn` / `sortAscending` / `showHidden` | `WorkspacePreferences`（单实例 `@Observable`） |
| `activeTab.mode` | `WorkspaceController.viewState.mode` |
| `activeTab.isTerminalVisible` | `WorkspaceController.viewState.isTerminalVisible` |
| `activeTerminalID` | `WorkspaceController.viewState.activeTerminalID` |
| `terminalAnchorCwd` | `WorkspaceController.viewState.terminalAnchorCwd` |
| `createTab(at:)` | `WorkspaceManager.openNewWindow(cwd:tabbedTo:)` |
| `closeTab(_:)` | `controller.window?.close()` |
| `switchTab(to:)` | `controller.window?.makeKeyAndOrderFront(nil)` |
| `switchToNextTab` / `Previous` | `window.selectNextTab(_:)` / `selectPreviousTab(_:)` |
| `switchToTabByIndex(n)` | `window.tabbedWindows?[n].makeKeyAndOrderFront(nil)` |
| `renameTab(_:to:)` | NSWindow `title`（系统直接读 `window.title` 当 tab title） |
| `moveFileTab` | 系统接管，删除 |
| `addTerminalSession` / `removeTerminalSession` / `setActiveTerminal` / `renameTerminalSession` / `updateTerminalCwd` / `moveTerminalSession` | 全部下放 `TerminalSessionStore`（per-window） |
| `findTabByAnchorOrCwd(_:)` | `WorkspaceManager.findController(matching:)` |
| `applySort` / `toggleHidden` / `toggleTerminalVisibility` / `toggleActiveTabMode` | preferences 走全局；mode/visibility 走 keyWindow controller |
| `saveTabState` / `restoreTabState` | `WorkspacePersistence`（Phase 4）|

### `@FocusedValue` 改造

旧通道：`@FocusedValue(\.tabManager) private var tabManager` — 因为 SwiftUI scene 内只一个 active view。
新通道：菜单命令需要 `NSApp.keyWindow?.windowController as? WorkspaceController` 直取。

SwiftUI menu 命令 (`CommandMenu`) 在 AppKit-managed window 模式下仍可工作，但 `@FocusedValue` 链路需要每个 window 内 root view 主动注入；改为简化路径：

```swift
@MainActor
func keyWorkspaceController() -> WorkspaceController? {
    (NSApp.keyWindow?.windowController as? WorkspaceController)
}
```

菜单 action 直接调上面 helper，不再依赖 `@FocusedValue`。仅 `WorkspaceModel` / `WorkspacePreferences` 给 SwiftUI view 用 `@Environment` / `@Observable` 注入。

### 风险

- 旧代码大量 `tabManager.foo` 引用要替换，编译期能逐条暴露。一次性重构 + 编译报错 driven。
- 菜单命令在 keyWindow 切换时无法实时 enable/disable（旧 `@FocusedValue` 自动跟）：用 `NSMenu.delegate` 的 `menuNeedsUpdate(_:)` 在 menu open 时拉一次 keyWindow 状态。

---

## Phase 4：持久化迁移

### 新模型

```swift
struct WorkspaceWindowState: Codable {
    let cwd: String
    let isCustomTitle: Bool
    let title: String?
    let mode: String  // finderFirst | terminalFirst
    let isTerminalVisible: Bool
    let anchorCwd: String?
    let terminalSessions: [TerminalSessionState]
    let activeTerminalIndex: Int?
}

struct WorkspaceSessionState: Codable {
    let windows: [WorkspaceWindowState]  // 顺序 = 系统 tab 显示顺序
    let keyWindowIndex: Int?
}
```

### 启动迁移

```swift
extension WorkspacePersistence {
    func loadSessionState() -> WorkspaceSessionState? {
        let d = UserDefaults.standard
        // 新 key
        if let data = d.data(forKey: "workspaceSessionState"),
           let s = try? JSONDecoder().decode(WorkspaceSessionState.self, from: data) {
            return s
        }
        // 旧 key 一次性迁移
        if let data = d.data(forKey: "fileTabsState"),
           let legacy = try? JSONDecoder().decode([FileTabState].self, from: data) {
            let activeID = d.string(forKey: "activeFileTabID")
            let windows = legacy.map { mapLegacy($0) }
            let keyIdx = legacy.firstIndex(where: { $0.id == activeID })
            let state = WorkspaceSessionState(windows: windows, keyWindowIndex: keyIdx)
            persist(state)
            d.removeObject(forKey: "fileTabsState")
            d.removeObject(forKey: "activeFileTabID")
            return state
        }
        return nil
    }
}
```

### 启动重建

```swift
extension WorkspaceManager {
    func restoreSession() {
        guard let state = persistence.loadSessionState(), !state.windows.isEmpty else { return }
        var prev: NSWindow?
        for w in state.windows {
            let c = WorkspaceController(...)
            if let prev { prev.addTabbedWindow(c.window!, ordered: .above) }
            controllers.append(c)
            prev = c.window
        }
        if let idx = state.keyWindowIndex, controllers.indices.contains(idx) {
            controllers[idx].window?.makeKeyAndOrderFront(nil)
        } else {
            controllers.first?.window?.makeKeyAndOrderFront(nil)
        }
    }
}
```

### 保存触发点

- `windowDidBecomeKey` / `windowDidResignKey`（key 索引变化）
- `WorkspaceManager.openNewWindow` / `windowWillClose`（数量变化）
- per-window 状态变化（mode / isTerminalVisible / cwd / terminal sessions / anchor）→ controller 内部 debounce 写一次全局 state

### 测试

- 迁移单测：构造旧 `fileTabsState` + `activeFileTabID` → 调 `loadSessionState` → 验证返回值 + 旧 key 已清
- 重建单测：构造 `WorkspaceSessionState` → 验证 controller 数量 / 顺序 / keyWindow

---

## Phase 5：AppRouter 跨 window 路由

### 改造

```swift
extension WorkspaceManager {
    func findController(matchingCwd url: URL) -> WorkspaceController? {
        let std = url.standardizedFileURL
        return controllers.first { c in
            c.workspace.currentURL.standardizedFileURL == std
            || c.viewState.terminalAnchorCwd?.standardizedFileURL == std
        }
    }
}

// AppDelegate route consumer 改为：
private func handleRoute(_ route: AppRouter.Route) {
    let manager = workspaceManager
    switch route {
    case .open(let url):
        if let c = manager.findController(matchingCwd: url) {
            c.window?.makeKeyAndOrderFront(nil)
        } else {
            manager.openNewWindow(cwd: url, tabbedTo: NSApp.keyWindow)
        }
    case .terminal(let url, let confirm): ...
    case .reveal(let urls): manager.keyController?.workspace.reveal(urls)
    }
}
```

`router.pending` 的消费从 ContentView `.onChange` 改为 `AppRouter` 主动 push 到 AppDelegate。

---

## Phase 6：快捷键迁移

| 快捷键 | 旧实现 | 新实现 |
|---|---|---|
| `Cmd+T`（无 terminal 焦点） | SwiftUI menu `Button "New Tab"` → tabManager.createTab | menu → `workspaceManager.openNewWindow(...)` |
| `Cmd+T`（terminal 焦点） | NSEvent monitor → `createTerminalTab` | 监控器保留，只是改读 `WorkspaceController.keyController?.terminalSessionStore.createSession()` |
| `Cmd+W`（单 tab） | NSEvent monitor `NSApp.keyWindow?.close()` | 删监控器分支，系统 `Cmd+W` 已经 close keyWindow（tab/window 统一语义） |
| `Cmd+W`（多 tab） | NSEvent monitor `tabManager.closeTab` | 系统自动关 key tab |
| `Cmd+W`（terminal 焦点） | NSEvent monitor → `closeTerminalTab` | 保留，需先看 firstResponder is GhosttySurfaceView |
| `Cmd+1..9` | SwiftUI `.keyboardShortcut("1")` 绑 `switchToTabByIndex` | NSEvent local monitor → `NSApp.keyWindow?.tabbedWindows?[n-1].makeKeyAndOrderFront(nil)` |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | tabManager.switchToNextTab/Previous | `NSApp.keyWindow?.selectNextTab(nil)` / `selectPreviousTab(nil)` |
| `Cmd+Shift+T`（Send Path） | 不变 | 不变 |
| `` Ctrl+` ``（Toggle Terminal） | tabManager.toggleTerminalVisibility | keyController.viewState.isTerminalVisible.toggle |
| `Ctrl+Shift+N`（New Terminal） | createTerminalTab | keyController.terminalSessionStore.createSession |

---

## Phase 7：Terminal 横向 tab 视觉对齐

### Token 对齐（参照 macOS Tahoe NSWindowTab）

| 属性 | 当前 `TerminalTabBar` | 目标 |
|---|---|---|
| Tab 圆角 | 6pt | 8pt（系统） |
| Tab 间距 | 2pt | 4pt（系统） |
| Tab 高度 | 28pt | 28pt（保留） |
| 活跃态背景 | `.regularMaterial` | `controlBackgroundColor`（更亮，对齐系统） |
| 非活跃态背景 | `Color.clear` | `windowBackgroundColor.opacity(0.6)` |
| 活跃态边框 | 无 | 1pt `separatorColor` 下边线（与系统 NSWindowTab 一致）|
| Tab 之间分隔线 | 无 | 1pt `separatorColor` |
| 关闭按钮 | 永显（弱色） | 默认隐藏，hover tab 时淡入 |
| 字体 | `.system(size: 12)` | `.system(size: 13, weight: .regular)` |
| 标题最大宽度 | 自适应 | 200pt 上限 + truncation |
| Active 下边 underline | 2pt accent | 删（与 NSWindowTab 视觉一致）|

应用到 `TerminalTabBar.swift` + `VerticalTerminalTabBar.swift`（纵向略调：分隔线变上下、活跃态背景同步）。

### 验证（视觉对齐）

- 并排截图 Finder tab + PathDeck terminal tab，色阶/圆角/间距/字号视觉一致
- 关闭按钮 hover 行为对齐

---

## Phase 8：Terminal tab 拖拽抛光

### 改造

| 行为 | 当前 | 目标 |
|---|---|---|
| Dragging image | SwiftUI 默认（tab 完整快照，含背景）| 自定义：tab snapshot + 0.85 alpha + 轻微阴影，跟随光标 |
| 邻居让位 | 无（drop 才动） | hover 期 hovered 边的邻居 spring 平移 28pt 让出落点（横向）/ 高度让位（纵向）|
| Drop 归位 | 瞬时切换顺序 | spring `(response: 0.35, damping: 0.7)` 缓动到最终位置 |
| Drop 落点指示 | 2pt accent 插入线（S31 已有，保留）| 保留 + 改用 systemBlue.opacity(0.6) 与系统视觉对齐 |
| 跨 tab bar 边界 auto-scroll | 无 | 横向溢出时拖到 leading/trailing 8pt 区域触发 ScrollView auto-scroll |

实现：

- Dragging image：`NSItemProvider.registerObject(ofClass:)` 之后用 `View.snapshot()` extension 转 `NSImage` 设为 dragging image
- 邻居让位：`@State var hoveredDropIndex: Int?` + 各 tab `.offset(x: shouldOffset(index, hoveredDropIndex))` + `.animation(.spring(...), value: hoveredDropIndex)`
- Drop 归位：`tabManager.moveTerminalSession` 调用后包一层 `withAnimation(.spring(...))`（实际上数组 reorder + identity 稳定的 ForEach 在 spring animation block 内自然缓动）
- Auto-scroll：`ScrollViewReader` + 拖拽位置接近边界时 `scrollTo` 邻居 ID

### 验证

手测：8 个 terminal tab，跨整条 tab bar 拖动顺序，观察 ghost 跟手 / 邻居让位 / drop 缓动 / 边界 auto-scroll。

---

## 风险与 Attack

| # | 风险 | 触发条件 | 缓解 |
|---|------|---------|------|
| R1 | NSHostingController 状态在 NSWindow tab merge/split 时丢失 | 拖出 tab 形成独立 window 后再拖回 | P1 验证；Apple 文档承诺 NSHostingController 在 window reparent 时保留 SwiftUI state（基于 view tree，不依赖 window）|
| R2 | 多 window 下 SwiftUI `Settings` scene 行为 | 任一 window 触发 `Cmd+,` | Settings scene 是独立 scene，与 workspace window 解耦，预期正常；保留单测覆盖 |
| R3 | `tabbingMode = .preferred` 用户全局偏好覆盖 | System Settings → General → Prefer tabs = Never | 接受系统语义；新 window 不自动合入，用户需 `Cmd+T` 主动开 tab |
| R4 | Terminal session 跟随 window 拆分时，session 已在数组里如何处理 | 用户从 tabbed window 拖出 tab 形成新 window | per-window `TerminalSessionStore` 在 controller 内，拖出 = window 不变只是脱离 tab 组，session 数组随 controller 走，零迁移 |
| R5 | 持久化迁移失败 | 旧 `fileTabsState` 损坏 | `try?` decode + fallback：删旧 key，开默认 home window |
| R6 | `Cmd+1..9` 在某些 system shortcut 下被吞 | 用户绑定了系统快捷键 | NSEvent local monitor 拦截在前；若 keyWindow 不是 workspace（如 Settings）放行 |
| R7 | URL Scheme 路由到背景 window 时未激活 | external entry 命中已存在 window 但 window 不在前台 | `makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)` 显式拉前 |
| R8 | window state restoration 与 macOS 系统的 Resume 冲突 | macOS 启动时系统也尝试恢复 window | 显式 `NSWindow.allowsAutomaticWindowTabbing = false` 在 app init 关掉系统级 tabbing，再手动 enable；并 `NSWindow.userTabbingPreference` 行为遵循用户偏好 |
| R9 | 多 window 下 `AppRouter` 单例 `pending` token 竞争 | 同时两个 URL Scheme 调用 | AppRouter 已经是 `@Observable` + token 消费模型，由 AppDelegate 主动 drain（不再 ContentView .onChange）|
| R10 | Terminal session 关闭时 owner window 已 close | 异步 PTY exit 回调 | controller `windowWillClose` 主动 closeAllSessions；session close 回调内 `weak self` 保护 |
| R11 | `applicationShouldHandleReopen` 行为冲突 | 全部 window close 后 Dock 重点 | 实现为：若无 window，重建一个 home window（不复原历史，保持简单）|

### Premise collapse 检查

**最脆弱假设**：SwiftUI `NSHostingController` 嵌入 NSWindow tabbing 后，SwiftUI view tree 在 window reparent 期间 state 不丢、Observation 链路不断。

- 若 X 不成立：Phase 1 末验证即可暴露；不通过则回退方案 = 全 AppKit root view（NSSplitViewController + NSToolbar），把 SwiftUI 限定到子组件粒度（PreviewPane / TerminalTabBar 等）；plan 重写 P1。
- 这是 P1 验证的核心目标，**P1 不过则停**，回到 think 重判。

---

## 测试策略

### 单元测试新增 / 改造

| 测试文件 | 覆盖 |
|---|---|
| `WorkspacePersistenceTests.swift`（新增）| 旧 `fileTabsState` → `workspaceSessionState` 迁移正确性 / 旧 key 清除 / 空 state 默认 / 损坏 state 容错 |
| `WorkspaceControllerTests.swift`（新增）| controller init / per-window state 独立性 / windowWillClose 关 session / mode 切换 / preferences sync |
| `WorkspaceManagerTests.swift`（新增）| openNewWindow tabbedTo 串接 / findController matching cwd / restoreSession 顺序与 key window |
| `AppRouterTests.swift`（追加）| `.open(url)` 命中已有 window 激活 vs 新建合入；`.terminal(url)` 同语义 |
| `TabManagerTests.swift`（删除）| 旧 ~30 例全部迁移到 `WorkspaceControllerTests` / `WorkspaceManagerTests` |
| `FileTabBarTests.swift`（若有，删除）| FileTabBar 不再存在 |
| `TerminalTabBarVisualTests`（手动） | P7/P8 视觉对齐与拖拽手感非自动化，记入 docs/plans 验收清单 |

### 手测清单（Release A 合并前）

1. 启动空 state → 一个 home window，title bar 无 tab bar
2. `Cmd+T` → 第二个 tab，title bar 显示系统 tab bar
3. 拖拽分离 tab → 独立 window，原 tab 组缩为单 tab
4. 拖回 → 合并
5. Window menu → 列出 tab，能切换
6. Mission Control → 缩略图正常
7. `Cmd+1` / `Cmd+2` → 切换正确
8. `Ctrl+Tab` / `Ctrl+Shift+Tab` → 循环切换
9. `Cmd+W` 单 tab → close window；多 tab → close key tab
10. terminal 焦点下 `Cmd+W` / `Cmd+T` → 影响 terminal session，不影响 window tab
11. URL Scheme `pathdeck:///open?path=...` 已有 window 命中 → 激活；不命中 → 新建合入
12. Finder Services / Open With → 同上
13. 关 app → 重启 → 全部 tab 复原（顺序 + key 一致）
14. 跨 tab：sidebar Favorites 增删 → 所有 tab 的 sidebar 同步刷新
15. 跨 tab：sort / showHidden 切换 → 所有 tab 同步
16. 旧 `fileTabsState` 迁移 → 启动一次后旧 key 清，新 key 正确

### 手测清单（Release B 合并前）

17. 8 个 terminal tab 横向拖动：ghost 跟手、邻居 spring 让位、drop 缓动
18. 关闭按钮 hover 才显形
19. 视觉与 Finder tab 并排比对：色阶/圆角/间距对齐
20. Terminal-first 模式纵向 tab 同步验证

---

## 持久化 key 变更

| key | 旧 | 新 |
|---|---|---|
| `fileTabsState` | 存在 | 删除（迁移后清） |
| `activeFileTabID` | 存在 | 删除（迁移后清） |
| `workspaceSessionState` | — | 新增（per-window 数组 + keyWindowIndex） |
| `sortColumn` | 存在 | 保留（迁到 `WorkspacePreferences`） |
| `sortAscending` | 存在 | 保留 |
| `showHidden` | 存在 | 保留 |
| `bottomPanelHeight` | 存在 | 保留（per-window 不引入新 key，沿用全局；如 Sir 后续要 per-window 再加） |
| `verticalTabWidth` | 存在 | 保留（同上） |
| `previewPaneVisible` | 存在 | 保留（同上） |

**全局 vs per-window 偏好**：`bottomPanelHeight` / `verticalTabWidth` / `previewPaneVisible` 当前是全局；改 NSWindow tabbing 后用户可能期望 per-window，但本需求保持全局以减少改动量；记入「后续考虑」。

---

## 决策点（需 Sir 确认后再起手）

| 决策 | 选项 | 推荐 |
|---|---|---|
| `tabbingMode` | `.preferred`（新 window 默认合入 tab 组） / `.automatic`（跟随系统 General 偏好）| `.preferred`（更符合 PathDeck"workspace 默认成 tab"心智）|
| 关闭最后一个 window | 退出 app / 保持菜单栏常驻 | 保持常驻（macOS 默认行为）|
| `Cmd+T` 终端焦点行为 | 新建 terminal session（沿用现状）/ 始终新建 tab | 沿用现状（terminal 焦点 → 新 session，文件焦点 → 新 tab）|
| 全局 vs per-window 的 `bottomPanelHeight` 等 | 全局 / per-window | 全局（本需求范围内不变）|

---

## 变更日志预登记（合入 AGENTS.md）

> 2026-06-?? **S32 NSWindow Tabbing**（Release A）：文件 tab 升级原生 NSWindow tabbing — 每个 file tab 升级为独立 `WorkspaceController: NSWindowController`（持有 per-window WorkspaceModel + TerminalSessionStore + viewState），统一 `tabbingIdentifier = "in.riverflows.PathDeck.workspace"` + `tabbingMode = .preferred` 自动合并。删除 `TabManager` / `FileTabBar` / `FileTabDragID` / `pathDeckFileTab` UTType / S31 file tab 自绘拖拽重排；保留 `TerminalSessionDragID` 与 terminal 自绘 tab。新增 `WorkspaceManager`（全 window 注册中心）/ `WorkspacePreferences`（全局偏好单实例 sort/showHidden 等）/ `WorkspacePersistence`（per-window state 迁移）。`AppRouter` 跨 window 匹配 cwd 激活 vs 新建合入。快捷键迁移：`Cmd+W` / `Cmd+1..9` / `Ctrl+Tab` 走系统 NSWindow tabbing API；NSEvent monitor 保留终端焦点分支。旧 `fileTabsState` + `activeFileTabID` 一次性迁移到 `workspaceSessionState` 后清除。Window menu / Mission Control / 拖出/合并 / 视觉随系统升级 全部免费拿到。
>
> 2026-06-?? **S32 Terminal Tab Polish**（Release B）：terminal 横向 tab + 纵向 tab 视觉对齐 NSWindowTab 设计 token（圆角 8pt / 间距 4pt / `controlBackgroundColor` 活跃态 / 分隔线 / 关闭按钮 hover 显形 / 字号 13）；拖拽 ghost 改用 tab snapshot + 邻居 spring 让位 + drop 弹性归位 + 横向溢出 auto-scroll。两层 tab 观感统一。
