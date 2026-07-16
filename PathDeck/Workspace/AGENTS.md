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
├── WorkspaceViewState.swift     per-window @Observable: mode / isTerminalVisible / activeTerminalID / terminalAnchorCwd / isCustomTitle / customTitle / isSidebarVisible / isPreviewPaneVisible（S36 起 per-window）/ isShortcutOverlayVisible + isCommandPaletteVisible（瞬态不持久化）
├── CloseHistory.swift           Close History（S37）：CloseHistoryStack @Observable 泛型 LIFO（上限 10、仅进程内）+ ClosedTerminalRecord / ClosedWindowRecord（weak hostGroup 归位目标）
├── CommandPaletteFilter.swift   Palette subsequence fuzzy 匹配纯函数（词首 3 / 连续 2 / 散点 1，同分保持原序）
├── CommandPaletteView.swift     Command Palette 浮层（⌘⇧P）：内容派生自 ShortcutRegistry.paletteSpecs，不可用置灰，↑↓/↩/Esc 键盘交互
├── WorkspacePreferences.swift   全局 @Observable 单实例: sort / showHidden / bottomPanelHeight / verticalTabWidth / columnWidths（didSet 自持久化）；isPreviewPaneVisible 自 S36 起仅作新窗口默认种子，不再有写入方
├── ShortcutOverlayHoldTracker.swift  长按 ⌘ 浮窗纯状态机（800ms 阈值/按键取消/鼠标隐藏/松开复位），schedule 可注入供单测同步驱动
├── ShortcutOverlayView.swift    快捷键浮窗视图：内容由 ShortcutRegistry 派生，三列分组材质卡片，纯展示 allowsHitTesting(false)
├── TerminalSessionStore.swift   per-window @Observable [TerminalSession]: append / remove / rename / updateCwd / move
├── WorkspaceController.swift    NSWindowController: 持 workspace + viewState + store + closedTerminals；tabbingIdentifier + tabbingMode = .preferred；createTerminal / closeTerminal(recordHistory:) / reopenClosedTerminal；Palette show/dismiss（记录并还原 first responder）；promptRenameWorkspace / sendSelectionPathToTerminal（S37 自菜单层迁入）；windowDidBecomeKey → 通知 manager；S38 起仅剩长按 ⌘ 浮窗的观察型 monitor（键位派发全部移交全局 CommandDispatch）
├── WorkspaceManager.swift       全 controller 注册中心 + TerminalEngine 单实例宿主 + persistSession debounce 100ms + closedWindows（全局窗口 Close History）/ reopenClosedWindow + installCommandMonitor（S38 全局唯一 keystroke monitor adapter：NSEvent → KeyStroke + 语境 → 根目录 CommandDispatch.resolve → 命令表 action；`dispatchCommand(for:context:)` 的 context 为测试缝）
├── WorkspaceSessionState.swift  WorkspaceWindowState（per-window 持久化 schema）+ WorkspaceSessionState（含 windows 顺序 + keyWindowIndex）
├── WorkspacePersistence.swift   UserDefaults 持久化封装；旧 `fileTabsState` + `activeFileTabID` 一次性迁移
└── WorkspaceRootView.swift      per-window SwiftUI root：NavigationSplitView（columnVisibility ↔ viewState.isSidebarVisible）+ workspace content + Shortcut Overlay 挂载（onAppear/onDisappear 装卸浮窗观察 monitor；键位派发 monitor 自 S38 起全局唯一，见 WorkspaceManager）
```

## 模块规范

- **TerminalEngine 单实例**：由 `WorkspaceManager` strong 持有；`WorkspaceController` 仅 weak（`engineHandle` 计算属性兜底）。session ID 全局唯一；engine 的 `onSessionClose` / `onCwdChange` / `onTitleChange` / `onPathLinkClick` 经 manager 反查 owner controller 派发，禁止 controller 直接订阅 engine。`windowWillClose` 必须同步卸载 `contentViewController`：关闭后 runloop 残留的 SwiftUI 渲染不得再触碰 `engineHandle`（engine 生命周期短于 controller 的场景——如单测局部 manager——会命中 fatalError，CI 慢时序实测踩过）。
- **持久化 debounce + 关键节点 flush**：`WorkspaceManager.persistSession()` 走 100ms debounce 合并日常变化（rename/reorder/cwd/mode 切换等经 `WorkspaceController` 包装方法触发）；关 window（`controllerWillClose`）和 app 退出（`AppDelegate.applicationWillTerminate`）都改调 `persistSessionImmediately()` 立即写盘，避免快速关闭/退出时丢最近变化导致重启复原已关 window。视图层 `WorkspacePersistenceModifier` 监听 controller 的 `store.sessions.count` / `viewState.isTerminalVisible/mode/activeTerminalID` / `workspace.currentURL` 变化触发 debounce 路径。
- **lastActiveControllerID 兜底**：manager 维护 `lastActiveControllerID: ObjectIdentifier?`，在 `controllerDidBecomeKey` 更新、在 `controllerWillClose` 清空。`keyController` computed 与持久化 `keyGroupIndex` 的判定优先看 `window.isKeyWindow`；Settings / NSAlert / 其他非 workspace 面板抢走 key window 时所有 workspace.isKeyWindow 都为 false，此时退到 lastActive 标识"用户视角的当前 workspace"，避免无脑 fallback 到 `controllers.first` 污染恢复目标与外部路由的 `tabbedTo` 入参（典型场景：激活第 2 个 workspace → 开 Settings → Quit，重启应仍回到第 2 个 workspace 所在 group）。
- **NSWindow tabbing 关键 API**：
  - `NSWindow.allowsAutomaticWindowTabbing = false`（启动前设置，关掉系统自动 tabbing，由 manager 显式控制合并时机）
  - `tabbingIdentifier = WorkspaceController.sharedTabbingIdentifier`（同 ID 才能合入同一 tab 组）
  - `tabbingMode = .preferred`（新 window 默认合入 key window 的 tab 组）
  - `addTabbedWindow(_:ordered:)`（在已有 window 上挂新 window 到同 tab 组）
  - `selectNextTab(_:)` / `selectPreviousTab(_:)`（Ctrl+Tab / Ctrl+Shift+Tab，S38 起经全局 CommandDispatch 派发，targetPolicy 严格 key workspace）
  - `tabbedWindows`（按 tab bar 顺序枚举，`Cmd+1..9` 行为在命令表 `selectTabN.indexedAction`，经 CommandDispatch 严格 key workspace 派发，菜单 Tab 1–9 点击同源——避免 Settings/alert 为 key 时操作后台 workspace 的 tab 组）
- **菜单命令访问 keyWindow controller**：S37 起菜单 action 统一经 `runCommand(id)` 查 `ShortcutRegistry` 命令表执行——`runCommand` 内部仍以 `keyWorkspaceController()` 严格解析 controller（下述语义不变：workspace 型命令收 nil no-op，responder-chain / 全局偏好型照常执行），改动作先改注册表。用 `keyWorkspaceController()` helper（PathDeckApp.swift 内 private fileprivate）作为 action 内的严格读路径，不要走 `@FocusedValue` 读取实际操作目标。`WorkspaceRootView` 经 `.focusedSceneValue(\.activeWorkspaceController, controller)` 注入仅供 commands 的 `.disabled(...)` 跟随当前 key workspace 的 `selectedURLs` 变化重新计算（Send Path to Terminal / Move to Trash 等需要 selection 才有意义的命令）；action 内仍走 `keyWorkspaceController()` 严格读，避免 Settings 为 key 时通过 FocusedValue 残留指向后台 workspace 误操作。**严格语义**：helper 仅在 `NSApp.keyWindow.windowController is WorkspaceController` 时返回，Settings / 其他面板为 key 时返回 nil，所有文档窗口命令（Toggle Terminal / New Terminal / Send Path / Open Folder / New Folder / Move to Trash / Find / Copy Current Path / Rename Workspace… / Tab N / Next Tab / Previous Tab）随之 no-op；不能 fallback 到 `manager.keyController`，否则用户在 Settings 焦点下按 `Cmd+Delete` 会误删后台 workspace 的选中文件。全局偏好类命令（Hidden Files）走 `manager.toggleHidden()`，从 Settings 触发也合理，不受 helper 约束；Toggle Sidebar / Toggle Preview Pane 自 S36 起是 per-window 状态，同样走 helper 严格读。keystroke 派发（⌘T 双语义分流等）自 S38 起统一走全局 CommandDispatch monitor（见根目录 `CommandDispatch.swift` 与 ADR-0002），菜单 `.keyboardShortcut` 从命令表 match 派生、仅作显示与非 workspace keyWindow 时的兜底——「SwiftUI command 在纯 AppKit first responder 下不派发」（S32 ⌘T 静默失效根因）不再是逐键需要评估的问题，新增可派发快捷键默认 `dispatchVia: .monitor`。
- **自定义 workspace 标题**：`viewState.isCustomTitle` + `viewState.customTitle` 由 "Rename Workspace…" 菜单命令（`Cmd+Shift+R`，PathDeckApp.swift `TabCommands`）写入，空字符串 → 清 isCustomTitle 并将 NSWindow.title 回到 `workspace.currentURL.lastPathComponent`；`WorkspaceRootView` 在 `onChange(of: viewState.customTitle)` 和 `workspace.currentURL` 时同步 window.title；持久化经 `manager.persistSession()` 落盘到 `WorkspaceWindowState.isCustomTitle/customTitle`。
- **持久化 key**：
  - 新：`workspaceSessionState`（`WorkspaceSessionState` JSON）
  - 已迁移并清除的旧 key：`fileTabsState` / `activeFileTabID`
  - 仍沿用的全局偏好 key：`sortColumn` / `sortAscending` / `showHidden` / `bottomPanelHeight` / `verticalTabWidth` / `columnWidths` / `previewPaneVisible`（S36 起语义降级为新窗口默认种子）
- **左右 sidebar 都是 per-window（含显隐，S36）**：左 Sidebar 在每个 `WorkspaceRootView` 内独立渲染（数据源 `PinnedFolders.shared` 全局共享，UI 实例多份），显隐经 `viewState.isSidebarVisible` ↔ `NavigationSplitView(columnVisibility:)` 绑定（系统 toolbar toggle 与 ⌘B 菜单命令都收敛到这一个绑定）；右 Preview Pane 显隐由 `viewState.isPreviewPaneVisible` per-window 控制（⌘⇧B / toolbar 按钮），内容由 per-window `workspace.selectedURLs` 驱动。两者随 session 快照持久化（`WorkspaceWindowState.isSidebarVisible/isPreviewPaneVisible` 可选字段兼容旧快照）；`WorkspacePreferences.isPreviewPaneVisible` 只剩「新窗口/旧快照默认值」一个用途。
- **长按 ⌘ 快捷键浮窗（S36）**：`WorkspaceController.overlayMonitor` 一个观察型 NSEvent local monitor（flagsChanged + keyDown + 三键 mouseDown，永远 return event 不吞，终端修饰键转发不受影响），严格 `keyWindow == self.window`，事件喂给 `ShortcutOverlayHoldTracker` 状态机，可见性经 `viewState.isShortcutOverlayVisible` 驱动 `WorkspaceRootView` 的 overlay；`windowDidResignKey` 兜底收起（⌘⇥ 切走时松 ⌘ 的 flagsChanged 不会送达本窗口）。浮窗内容全部来自 `ShortcutRegistry`（根目录），不得在视图里硬编码键位。
- **AppRouter 跨 window 路由**：`AppRouter.pending` 是 FIFO 队列（不是单值令牌）——Finder 多选文件夹 Open With 会一次 enqueue 多条 `.open`，必须全部处理不能后覆盖前。`AppDelegate.applicationDidFinishLaunching` 在 `restoreSession()` 后立即同步调一次 `drainPendingRoutes()`（while 循环 drain 到队列空）处理冷启动累积的 pending（kAEGetURL / `application(_:open:)` 都在 didFinishLaunching 之前触发；先 drain 再判 `controllers.isEmpty` 才开 Home，避免冷启动 URL Scheme 多出一个 Home window），然后调 `observePending()` 用 `withObservationTracking` 注册对后续变化的持续 observation（每次变化在主队列异步 `drainPendingRoutes()` + 重新 arm observer）。`drainPendingRoute`（处理单条）：`.open(url)` 命中 cwd → `makeKeyAndOrderFront` + `workspace.navigate(to:)`；未命中 → `manager.openNewWindow(cwd:tabbedTo: manager.keyController?.window)`（不用 `NSApp.keyWindow`，Settings 为 key window 时会误传非 workspace window）。`.terminal(url, requireConfirmation:)` 必须先 `confirmOpenTerminal` 再创建/激活 window，Cancel 完全阻止外部请求。`.reveal(urls)` 先按首项父目录 `findController(matchingCwd: first.deletingLastPathComponent())` 匹配已有 workspace（避免：已开 /A 和 /B，当前 key 是 /A，reveal /B/file 把 /A workspace 的 currentURL 误改成 /B，既污染 /A 又重复已有的 /B）；未命中再 fallback 到 `keyController ?? controllers.first`；都没有则按父目录 `openNewWindow(cwd:tabbedTo: nil)` 再 reveal，避免冷启动 reveal 路由被消费但无效。Dock reopen（`applicationShouldHandleReopen` 且 `hasVisibleWindows == false`）：优先 `deminiaturize` 已有 controller，只有 controllers 为空才开 Home，避免最小化/隐藏的 workspace 上凭空多出 Home。
- **不要重新引入 SwiftUI `WindowGroup`**：与 NSWindow 自管会争抢 window 生命周期和 state restoration，导致双重 window 或缺失 tabbing。
- **Settings scene 不参与 tabbing**：SwiftUI `Settings { SettingsView() }` 是独立 scene，系统默认不会用 PathDeck workspace 的 `tabbingIdentifier`，无需特殊处理。

## 依赖关系

- 上层依赖：`PathDeckApp.swift` / `AppDelegate.swift`（构造、菜单分发）
- 同层依赖：`AppRouter` / `PinnedFolders` / `RecentFolders`
- 下层依赖：`FileWorkspace/`（`WorkspaceModel` + `SortColumn`）/ `Terminal/`（`TerminalSession` / `TerminalTabState` / `TerminalEngine` / `GhosttyTerminalEngine`）

## 变更日志

- 2026-07-16 **S39 FR-BRIDGE-003 #5 ⌘Click Locate 接线**：`WorkspaceManager.setupEngineCallbacks` 新增 `engine.onPathLinkClick` → `handleEnginePathLinkClick` 反查 owner controller；`WorkspaceController` 新增 `locate(_ link: PathLink)`（目录 → `workspace.navigate`，文件 → `workspace.reveal(takingFocus: false)`——Locate 不夺焦，ADR-0003）；`WorkspaceRootView` 向 `FileTableView` 透传 `revealTakesFocus`。检测逻辑见 `ContextBridge/AGENTS.md`，视图侧拦截见 `Terminal/AGENTS.md`。
- 2026-07-04 **S38 Command Dispatch 收拢**：删 `WorkspaceController` 的 closeTabMonitor / newTabMonitor / reopenMonitor / paletteMonitor / tabSwitchMonitor 五个键位 monitor（`installShortcutMonitors` 只剩浮窗 hold-tracker 观察 monitor）；`WorkspaceManager` 新增 `installCommandMonitor` / `dispatchCommand(for:context:)`（全局唯一 keystroke adapter，AppDelegate 启动装载；context 参数为测试缝，nil 时从 NSApp.keyWindow 实算 target + 焦点语境：GhosttySurfaceView → terminal、NSText field editor → textEditing 放行、其余 → file）。决策逻辑在根目录 `CommandDispatch.resolve`（R1 仲裁），键位元数据单源见 `ShortcutRegistry`（ADR-0002）。测试 `CommandMonitorAdapterTests`（合成 NSEvent 直调，@Suite(.serialized) 真窗口）。
- 2026-07-03 **S37 Command Palette + Reopen Closed Tab**：新增 `CloseHistory.swift`（@Observable 泛型 LIFO 栈 + 两种 record）、`CommandPaletteFilter.swift`（fuzzy 纯函数，`CommandPaletteFilterTests` 10 例）、`CommandPaletteView.swift`。`WorkspaceController` 增 `closedTerminals` 栈 / `closeTerminal(recordHistory:)`（engine exit 回调传 false）/ `reopenClosedTerminal`（恢复 cwd/标题/位置）/ Palette show-dismiss 焦点管理 / `reopenMonitor` + `paletteMonitor`（⌘⇧T 双语义分流、⌘⇧P，同 ⌘T monitor 模式）/ `lastKnownTabGroup` 存活期缓存（**windowWillClose 时窗口已脱离 tabGroup**，组关系只能在 becomeKey/resignKey + 程序化 addTabbedWindow 后缓存；测试与非活跃 app 下 key 事件不触发，必须有显式刷新路径）。`WorkspaceManager` 增 `closedWindows` 栈（`controllerWillClose` 捕获 windowStateFor + frame + hostGroup）/ `reopenClosedWindow`（restoreController 重建，原组存活 addTabbedWindow 归位否则按 frame 独立恢复）。窗口类测试用 `@Suite(.serialized)`（Swift Testing 默认并行下真窗口 tabbing 互相干扰 flaky）。测试 `CloseHistoryTests` 12 例。
- 2026-07-03 **S36 快捷键收束 + 浮窗 + 状态迁移**：新增 `ShortcutOverlayHoldTracker`（纯状态机，`ShortcutOverlayHoldTrackerTests` 9 例）与 `ShortcutOverlayView`；`WorkspaceController` 增 `overlayMonitor`（观察型，四类事件合一）+ `windowDidResignKey` 收起浮窗。`WorkspaceViewState` 增 `isSidebarVisible/isPreviewPaneVisible/isShortcutOverlayVisible`；`WorkspaceWindowState` 增两个可选字段（旧快照解码为 nil，restore 回退默认：sidebar=true、preview=旧全局偏好）；`WorkspacePersistenceModifier` 监听两个新字段。菜单侧 Toggle Sidebar（⌘B，新增）/ Toggle Preview Pane（⌘⇧B，原 ⌘⇧P）改走 `keyWorkspaceController()` 严格读（原 Preview 走全局 `WorkspacePreferences`，已随状态迁移改判据——Settings 为 key 时 no-op 属预期）。持久化兼容测试见 `WorkspacePersistenceTests.sidebarAndPreviewPaneFieldsRoundTripAndTolerateLegacySnapshots`。
- 2026-07-02 **重启持久化补全**：`WorkspacePreferences` 新增 `columnWidths: [String: CGFloat]`（列宽全局偏好）；`WorkspaceGroupState` 新增 `frame: String?`（NSStringFromRect，可选字段兼容旧快照）；`persistSessionImmediately` 记录各组可见窗口 frame，`restoreSession` 对组内首 window `setFrame`（后续 tab 自动沿用组 frame），`WorkspaceManager.validatedOnScreen` 越界防护（不与任一屏幕相交回退默认居中）；`openNewWindow` 新独立窗口继承 `keyController` frame + (24, -24) 级联（开 tab 不继承）；`WorkspaceController` 新增 `windowDidEndLiveResize`/`windowDidMove` → debounced persist。修复既有 bug：init 里 `contentViewController` 赋值会把窗口 resize 到 SwiftUI fitting size（720×480）吞掉 contentRect / 传入 frame，赋值后须重新 `setFrame`（+ frame==nil 时重新 center）。测试 `WindowFramePersistenceTests`。
- 2026-06-25 **Fix ⌘T New Tab 文件焦点失效**：`newTabMonitor` 非终端分支从 `return event`（依赖 SwiftUI `.keyboardShortcut("t")`）改为直接 `manager.openNewWindow(cwd:tabbedTo: self.window)` + `return nil`。根因：S32 从单一 SwiftUI 视图树（`ContentView`）迁到手动 NSWindow + 无 WindowGroup 后，first responder 为纯 AppKit `FileNSOutlineView` 时 SwiftUI command 不派发，⌘T 静默失效；终端焦点走 monitor 兜底不受影响。Next/Prev/⌘1..9 在 S32 已改纯 monitor，唯 New Tab 沿用旧"放行给 SwiftUI"假设被遗漏。`.keyboardShortcut("t")` 保留作菜单 ⌘T 显示 + Settings 焦点兜底。
- 2026-06-18 **S32 NSWindow Tabbing**：模块建立。删 TabManager/FileTab/FileTabBar 自绘 tab 栈，整体迁移到 NSWindow tabbing + per-window state。旧 `fileTabsState` 迁移到 `workspaceSessionState`。
