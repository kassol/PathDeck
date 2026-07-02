# AGENTS.md — Workspace

> 多 NSWindow workspace 的状态拆分与生命周期管理。
> 替换 S31 及之前的 `TabManager` / `FileTab` / `FileTabBar` 自绘 tab 栈。

## 职责

把"一个 file tab = 一个 workspace"升级为"一个 NSWindow = 一个 workspace"，借力系统 NSWindow tabbing 拿到拖出/合并、Mission Control、`Cmd+1..9`、Window menu、视觉跟随系统升级等能力。本模块负责：

- 每个 NSWindow 自包含的 workspace 单元（WorkspaceController 持 WorkspaceModel + TerminalSessionStore + WorkspaceViewState）
- 全局共享的偏好（WorkspacePreferences：sort/showHidden/面板尺寸/preview pane）
- 跨 window 查找（findController(matchingCwd:) / findControllerOwning(sessionID:)）
- 持久化迁移（旧 `fileTabsState` → 新 `workspaceSessionState`）

## 目录结构

```
Workspace/
├── WorkspaceMode.swift          finderFirst | terminalFirst 枚举（per-window mode）
├── WorkspaceViewState.swift     per-window @Observable: mode / isTerminalVisible / activeTerminalID / terminalAnchorCwd / isCustomTitle / customTitle
├── WorkspacePreferences.swift   全局 @Observable 单实例: sort / showHidden / bottomPanelHeight / verticalTabWidth / isPreviewPaneVisible（didSet 自持久化）
├── TerminalSessionStore.swift   per-window @Observable [TerminalSession]: append / remove / rename / updateCwd / move
├── WorkspaceController.swift    NSWindowController: 持 workspace + viewState + store；tabbingIdentifier + tabbingMode = .preferred；createTerminal / closeTerminal；windowDidBecomeKey → 通知 manager
├── WorkspaceManager.swift       全 controller 注册中心 + TerminalEngine 单实例宿主 + persistSession debounce 100ms
├── WorkspaceSessionState.swift  WorkspaceWindowState（per-window 持久化 schema）+ WorkspaceSessionState（含 windows 顺序 + keyWindowIndex）
├── WorkspacePersistence.swift   UserDefaults 持久化封装；旧 `fileTabsState` + `activeFileTabID` 一次性迁移
└── WorkspaceRootView.swift      per-window SwiftUI root：NavigationSplitView + workspace content + per-window NSEvent ⌘W/⌘T monitor（仅响应本 window keyWindow）
```

## 模块规范

- **TerminalEngine 单实例**：由 `WorkspaceManager` strong 持有；`WorkspaceController` 仅 weak（`engineHandle` 计算属性兜底）。session ID 全局唯一；engine 的 `onSessionClose` / `onCwdChange` / `onTitleChange` 经 manager 反查 owner controller 派发，禁止 controller 直接订阅 engine。`windowWillClose` 必须同步卸载 `contentViewController`：关闭后 runloop 残留的 SwiftUI 渲染不得再触碰 `engineHandle`（engine 生命周期短于 controller 的场景——如单测局部 manager——会命中 fatalError，CI 慢时序实测踩过）。
- **持久化 debounce + 关键节点 flush**：`WorkspaceManager.persistSession()` 走 100ms debounce 合并日常变化（rename/reorder/cwd/mode 切换等经 `WorkspaceController` 包装方法触发）；关 window（`controllerWillClose`）和 app 退出（`AppDelegate.applicationWillTerminate`）都改调 `persistSessionImmediately()` 立即写盘，避免快速关闭/退出时丢最近变化导致重启复原已关 window。视图层 `WorkspacePersistenceModifier` 监听 controller 的 `store.sessions.count` / `viewState.isTerminalVisible/mode/activeTerminalID` / `workspace.currentURL` 变化触发 debounce 路径。
- **lastActiveControllerID 兜底**：manager 维护 `lastActiveControllerID: ObjectIdentifier?`，在 `controllerDidBecomeKey` 更新、在 `controllerWillClose` 清空。`keyController` computed 与持久化 `keyGroupIndex` 的判定优先看 `window.isKeyWindow`；Settings / NSAlert / 其他非 workspace 面板抢走 key window 时所有 workspace.isKeyWindow 都为 false，此时退到 lastActive 标识"用户视角的当前 workspace"，避免无脑 fallback 到 `controllers.first` 污染恢复目标与外部路由的 `tabbedTo` 入参（典型场景：激活第 2 个 workspace → 开 Settings → Quit，重启应仍回到第 2 个 workspace 所在 group）。
- **NSWindow tabbing 关键 API**：
  - `NSWindow.allowsAutomaticWindowTabbing = false`（启动前设置，关掉系统自动 tabbing，由 manager 显式控制合并时机）
  - `tabbingIdentifier = WorkspaceController.sharedTabbingIdentifier`（同 ID 才能合入同一 tab 组）
  - `tabbingMode = .preferred`（新 window 默认合入 key window 的 tab 组）
  - `addTabbedWindow(_:ordered:)`（在已有 window 上挂新 window 到同 tab 组）
  - `selectNextTab(_:)` / `selectPreviousTab(_:)`（Ctrl+Tab / Ctrl+Shift+Tab，由 `WorkspaceRootView.tabSwitchMonitor` NSEvent local monitor 显式拦截、严格只在自身 keyWindow 时处理）
  - `tabbedWindows`（按 tab bar 顺序枚举，`Cmd+1..9` 经 NSEvent monitor 走 index，不再绑 SwiftUI `.keyboardShortcut`——避免 Settings/alert 为 key 时通过 fallback 操作后台 workspace 的 tab 组）
- **菜单命令访问 keyWindow controller**：用 `keyWorkspaceController()` helper（PathDeckApp.swift 内 private fileprivate）作为 action 内的严格读路径，不要走 `@FocusedValue` 读取实际操作目标。`WorkspaceRootView` 经 `.focusedSceneValue(\.activeWorkspaceController, controller)` 注入仅供 commands 的 `.disabled(...)` 跟随当前 key workspace 的 `selectedURLs` 变化重新计算（Send Path to Terminal / Move to Trash 等需要 selection 才有意义的命令）；action 内仍走 `keyWorkspaceController()` 严格读，避免 Settings 为 key 时通过 FocusedValue 残留指向后台 workspace 误操作。**严格语义**：helper 仅在 `NSApp.keyWindow.windowController is WorkspaceController` 时返回，Settings / 其他面板为 key 时返回 nil，所有文档窗口命令（Toggle Terminal / New Terminal / Send Path / Open Folder / New Folder / Move to Trash / Find / Copy Current Path / Rename Workspace… / Tab N / Next Tab / Previous Tab）随之 no-op；不能 fallback 到 `manager.keyController`，否则用户在 Settings 焦点下按 `Cmd+Delete` 会误删后台 workspace 的选中文件。全局偏好类命令（Toggle Preview Pane / Hidden Files）走 `WorkspacePreferences.shared` / `manager.toggleHidden()`，从 Settings 触发也合理，不受 helper 约束。`New Tab`（⌘T）由 `WorkspaceController.newTabMonitor` 接管：终端焦点 → `createTerminal()` 新建终端 session；其余焦点（文件列表等）→ `manager.openNewWindow(tabbedTo: self.window)` 新建 workspace tab；两分支都 `return nil`。SwiftUI `.keyboardShortcut("t")` 仅作菜单显示 ⌘T + Settings/alert 为 key 时的兜底（monitor 守卫 `keyWindow == self.window` 失败 → `return event` 放行，action 经 `manager.keyController?` fallback 退到 lastActive，允许始终开新 tab）。非终端分支**不能** `return event` 依赖 SwiftUI command——手动 NSWindow + 无 WindowGroup 架构下 first responder 为纯 AppKit `FileNSOutlineView` 时该 command 不派发（与 Next/Prev/⌘1..9 同因；S32 从单一 SwiftUI 视图树迁出时漏改此分支，致焦点在文件列表按 ⌘T 静默失效，2026-06-25 修复）。
- **自定义 workspace 标题**：`viewState.isCustomTitle` + `viewState.customTitle` 由 "Rename Workspace…" 菜单命令（`Cmd+Shift+R`，PathDeckApp.swift `TabCommands`）写入，空字符串 → 清 isCustomTitle 并将 NSWindow.title 回到 `workspace.currentURL.lastPathComponent`；`WorkspaceRootView` 在 `onChange(of: viewState.customTitle)` 和 `workspace.currentURL` 时同步 window.title；持久化经 `manager.persistSession()` 落盘到 `WorkspaceWindowState.isCustomTitle/customTitle`。
- **持久化 key**：
  - 新：`workspaceSessionState`（`WorkspaceSessionState` JSON）
  - 已迁移并清除的旧 key：`fileTabsState` / `activeFileTabID`
  - 仍沿用的全局偏好 key：`sortColumn` / `sortAscending` / `showHidden` / `bottomPanelHeight` / `verticalTabWidth` / `previewPaneVisible`
- **左右 sidebar 都是 per-window**：左 sidebar 在每个 `WorkspaceRootView` 内独立渲染（数据源 `PinnedFolders.shared` 全局共享，UI 实例多份）；右 preview pane 由 `preferences.isPreviewPaneVisible` 全局控制可见性，内容由 per-window `workspace.selectedURLs` 驱动。
- **AppRouter 跨 window 路由**：`AppRouter.pending` 是 FIFO 队列（不是单值令牌）——Finder 多选文件夹 Open With 会一次 enqueue 多条 `.open`，必须全部处理不能后覆盖前。`AppDelegate.applicationDidFinishLaunching` 在 `restoreSession()` 后立即同步调一次 `drainPendingRoutes()`（while 循环 drain 到队列空）处理冷启动累积的 pending（kAEGetURL / `application(_:open:)` 都在 didFinishLaunching 之前触发；先 drain 再判 `controllers.isEmpty` 才开 Home，避免冷启动 URL Scheme 多出一个 Home window），然后调 `observePending()` 用 `withObservationTracking` 注册对后续变化的持续 observation（每次变化在主队列异步 `drainPendingRoutes()` + 重新 arm observer）。`drainPendingRoute`（处理单条）：`.open(url)` 命中 cwd → `makeKeyAndOrderFront` + `workspace.navigate(to:)`；未命中 → `manager.openNewWindow(cwd:tabbedTo: manager.keyController?.window)`（不用 `NSApp.keyWindow`，Settings 为 key window 时会误传非 workspace window）。`.terminal(url, requireConfirmation:)` 必须先 `confirmOpenTerminal` 再创建/激活 window，Cancel 完全阻止外部请求。`.reveal(urls)` 先按首项父目录 `findController(matchingCwd: first.deletingLastPathComponent())` 匹配已有 workspace（避免：已开 /A 和 /B，当前 key 是 /A，reveal /B/file 把 /A workspace 的 currentURL 误改成 /B，既污染 /A 又重复已有的 /B）；未命中再 fallback 到 `keyController ?? controllers.first`；都没有则按父目录 `openNewWindow(cwd:tabbedTo: nil)` 再 reveal，避免冷启动 reveal 路由被消费但无效。Dock reopen（`applicationShouldHandleReopen` 且 `hasVisibleWindows == false`）：优先 `deminiaturize` 已有 controller，只有 controllers 为空才开 Home，避免最小化/隐藏的 workspace 上凭空多出 Home。
- **不要重新引入 SwiftUI `WindowGroup`**：与 NSWindow 自管会争抢 window 生命周期和 state restoration，导致双重 window 或缺失 tabbing。
- **Settings scene 不参与 tabbing**：SwiftUI `Settings { SettingsView() }` 是独立 scene，系统默认不会用 PathDeck workspace 的 `tabbingIdentifier`，无需特殊处理。

## 依赖关系

- 上层依赖：`PathDeckApp.swift` / `AppDelegate.swift`（构造、菜单分发）
- 同层依赖：`AppRouter` / `PinnedFolders` / `RecentFolders`
- 下层依赖：`FileWorkspace/`（`WorkspaceModel` + `SortColumn`）/ `Terminal/`（`TerminalSession` / `TerminalTabState` / `TerminalEngine` / `GhosttyTerminalEngine`）

## 变更日志

- 2026-07-02 **重启持久化补全**：`WorkspacePreferences` 新增 `columnWidths: [String: CGFloat]`（列宽全局偏好）；`WorkspaceGroupState` 新增 `frame: String?`（NSStringFromRect，可选字段兼容旧快照）；`persistSessionImmediately` 记录各组可见窗口 frame，`restoreSession` 对组内首 window `setFrame`（后续 tab 自动沿用组 frame），`WorkspaceManager.validatedOnScreen` 越界防护（不与任一屏幕相交回退默认居中）；`openNewWindow` 新独立窗口继承 `keyController` frame + (24, -24) 级联（开 tab 不继承）；`WorkspaceController` 新增 `windowDidEndLiveResize`/`windowDidMove` → debounced persist。修复既有 bug：init 里 `contentViewController` 赋值会把窗口 resize 到 SwiftUI fitting size（720×480）吞掉 contentRect / 传入 frame，赋值后须重新 `setFrame`（+ frame==nil 时重新 center）。测试 `WindowFramePersistenceTests`。
- 2026-06-25 **Fix ⌘T New Tab 文件焦点失效**：`newTabMonitor` 非终端分支从 `return event`（依赖 SwiftUI `.keyboardShortcut("t")`）改为直接 `manager.openNewWindow(cwd:tabbedTo: self.window)` + `return nil`。根因：S32 从单一 SwiftUI 视图树（`ContentView`）迁到手动 NSWindow + 无 WindowGroup 后，first responder 为纯 AppKit `FileNSOutlineView` 时 SwiftUI command 不派发，⌘T 静默失效；终端焦点走 monitor 兜底不受影响。Next/Prev/⌘1..9 在 S32 已改纯 monitor，唯 New Tab 沿用旧"放行给 SwiftUI"假设被遗漏。`.keyboardShortcut("t")` 保留作菜单 ⌘T 显示 + Settings 焦点兜底。
- 2026-06-18 **S32 NSWindow Tabbing**：模块建立。删 TabManager/FileTab/FileTabBar 自绘 tab 栈，整体迁移到 NSWindow tabbing + per-window state。旧 `fileTabsState` 迁移到 `workspaceSessionState`。
