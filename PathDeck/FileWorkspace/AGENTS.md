# AGENTS.md — FileWorkspace

> PathDeck 文件工作台模块。就近覆盖根 `AGENTS.md`。

## 职责

Finder-like 文件工作台：目录浏览、路径导航、排序、隐藏文件、右键菜单文件操作（Open/Trash/Rename/New Folder/Copy/Paste/Move/Duplicate）、Quick Look 预览、打开任意文件夹、文件名搜索、Send Path to Terminal、拖拽文件到终端、FSEvents 实时目录刷新（FSWatcher）、Preview Pane（右侧文件预览面板）。后续扩展：多视图模式、内容搜索。

## 目录结构

| 文件 | 职责 |
|---|---|
| `FileItem.swift` | 文件/目录的值类型 model（`Sendable`） |
| `DirectoryLister.swift` | 无状态目录枚举服务（`nonisolated`，可单测、未来可挪后台） |
| `WorkspaceModel.swift` | `@Observable` 工作区状态：当前目录 + items/allItems + 导航 + 排序 + 隐藏文件 + 选中文件 + 文件操作（trash/rename/newFolder/pasteFiles/duplicateItems）+ 搜索过滤 + 打开文件夹 + `reveal(_ fileURLs: [URL])`（跨目录导航首项父目录 + 同父目录多选高亮，外部入口/Open Selection 用）+ `revealSelection`（命令式多选+滚动信号）。持有 FSWatcher 做目录实时刷新。多实例设计：S32 起每个 `WorkspaceController`（即每个 NSWindow workspace）独立持有一个实例，`init(root:sortColumn:sortAscending:showHidden:)` 必传 root，不读 UserDefaults；sort/showHidden 由全局 `WorkspacePreferences` 单实例统一管理，所有 window 共享 |
| `FSWatcher.swift` | FSEvents 文件变化监听器：递归监听根目录 → 0.5s coalesce 去抖 → 传 dirty 目录集合回调；支持 `setExpandedDirectories` 匹配已展开子目录事件 |
| `OutlineDataSource.swift` | `NSOutlineView` 树状数据层（`FileNode` 引用包装 + rootNodes/childrenCache + nodePool identity 复用 + per-level 排序 + 递归 clear）|
| `FileTableView.swift` | `NSViewRepresentable` 包 `NSOutlineView`（`FileNSOutlineView` 子类），目录就地展开/折叠 + 搜索 flat 降级 + 右键菜单 + inline rename + Quick Look + 拖拽源 |
| `RecentFolders.swift` | 最近打开文件夹管理（`@Observable`，UserDefaults 持久化，10 项上限，去重） |
| `SearchBarView.swift` | `NSSearchField` 的 `NSViewRepresentable` 包装，实时回调 + Esc 关闭 |
| `ShellEscape.swift` | POSIX shell 路径转义纯函数（单引号包裹，Send Path to Terminal 用） |
| `PreviewPane.swift` | 右侧文件预览面板：QLThumbnail 缩略图 + 元数据表（Kind/Size/Where/Created/Modified）+ Quick Actions（Send Path / Copy Path）；⌘⇧P toggle |

## 模块规范

- 文件列表用 AppKit `NSOutlineView`（S26 从 `NSTableView` 迁移），不用 SwiftUI `Table`：多选 / 拖拽 / 就地重命名 / type-select / 目录就地展开/折叠 / 万级实时增量刷新等需求落在 SwiftUI 结构性弱区。SwiftUI 仅作壳与工具栏。
- 目录 IO 一律走 `DirectoryLister`（`nonisolated`），不在视图层直接读文件系统。
- 列表数据流单向：`WorkspaceModel.items` → `FileTableView`；交互经 `onOpen` 回调 → model 改状态 → 重新 list。
- 不在本模块散用 libghostty 符号；跨模块依赖经各自抽象层。

## 依赖关系

- 依赖：Foundation、AppKit、SwiftUI、Observation、QuickLookUI、QuickLookThumbnailing、UniformTypeIdentifiers。
- 被依赖：`Workspace/WorkspaceRootView` 装载 `FileTableView`；`Workspace/WorkspaceController` 持有 per-window `WorkspaceModel` 实例。

## 变更日志

- 2026-07-02 列宽/排序持久化：`FileTableView` 新增 `initialColumnWidths`/`initialSortColumn`/`initialSortAscending`（仅 makeNSView 读取：建列应用持久化列宽、列头排序指示箭头对齐持久化排序，原硬编码 name↑）+ `onColumnResize` 回调（`outlineViewColumnDidResize` 委托 → `WorkspacePreferences.columnWidths`；`columnSetupFinished` 旗标抑制建列期间的同步触发）。测试见 `FileTableColumnWidthTests`。
- 2026-07-02 列宽还原 bug 修复：`FileTableView` 的 `NSOutlineView` 设 `autoresizesOutlineColumn = false`。默认 true 时 `reloadItem(nil, reloadChildren: true)` 内部会把 outline column（name 列）resize 到适配内容（KVO 调用栈实锤），用户手动调整的列宽在任何 reload 路径（删除/重命名/新建/FSWatcher 外部变更）都会被还原到 minWidth。回归测试 `FileTableColumnWidthTests`（真 NSWindow + 完整 WorkspaceRootView + runloop pump，断言列宽保持 + NSOutlineView 实例不被重建）。
- 2026-06-30 S35 File Edit Actions：`FileNSOutlineView` 实现标准 Cocoa action selector（`copy:`/`paste:`/`moveItemHere:`/`duplicate:`）+ `validateUserInterfaceItem`，Edit 菜单 pasteboard section 手动重建（Copy/Paste/Move Item Here ⌘⌥V/Duplicate ⌘D/Select All/Copy Current Path）。`WorkspaceModel` 新增 `pasteFiles(_:operation:)`（copy/move + Finder 式 " copy" 重名递增）+ `duplicateItems()`。右键菜单追加 Duplicate（文件选中时）和 Paste（空白区）。`appReservedShortcuts` 新增 `"d"` 避免终端拦截 ⌘D。NSPasteboard 双类型写入（`.fileURL` + `.string`）。
- 2026-06-18 S32 NSWindow Tabbing：宿主层 file tab 升级为系统 NSWindow tabbing；本模块 `WorkspaceModel` 的所有权从 `TabManager.workspaceModels` 字典迁到 per-window `Workspace/WorkspaceController.workspace`，每个 NSWindow 持有一份独立实例（含独立 FSWatcher）。`sort/showHidden` 改由全局 `Workspace/WorkspacePreferences` 单实例统一管理，所有 window 共享 + `WorkspaceManager.applySort/toggleHidden` 同步给所有 controller 的 workspace。`FileTableView` 装载点从 `ContentView` 迁到 `Workspace/WorkspaceRootView`。
- 2026-06-18 S29 Convergence：`OutlineDataSource` 新增 `refreshAll`（根+所有展开子目录全量刷新）+ `child(index:of:)` 越界返回 inert placeholder 防崩溃。`WorkspaceModel.reload()` 改用 `refreshAll`（本地操作保留展开态），`navigate()` 独立路径走 `loadRoot`。搜索模式 flat subscript 加 bounds guard。`FSWatcher.stop()` 修复 `deinit` 在自身 queue 上触发 `queue.sync` 死锁（`DispatchSpecificKey` 检测已在目标 queue）。测试修复 `reloadChildrenPrunesDeletedNestedCache` URL 尾部斜杠不匹配。
- 2026-06-17 S26 目录就地折叠/展开：NSTableView→NSOutlineView 迁移。新增 `OutlineDataSource.swift`（`FileNode` + 树状数据层 + `refreshRoot` 保留展开状态 + `reloadChildren` 裁剪嵌套删除缓存）。`FileTableView` 全面重写 Coordinator（NSOutlineViewDataSource/Delegate），搜索模式 `FlatFileNode` flat 降级 + dirty reload 全量刷新。`FSWatcher` handler 改为 `(Set<String>) -> Void` + `setExpandedDirectories`，模型层所有展开变更同步 watcher scope。拖拽源 local + non-local mask。`WorkspaceModel` 持有 `OutlineDataSource` + `dirtyDirectories` 精确刷新。
- 2026-06-17 S25 i18n：全量硬编码中文字符串提取为英文 key + zh-Hans 翻译。`FileTableView` 列头 / 右键菜单、`WorkspaceModel` 新建文件夹名、`SearchBarView` 占位文本、`PreviewPane` 元数据标签均走 `String(localized:)` / `LocalizedStringKey`。
- 2026-06-17 S24 UX Polish：`FileTableView` 列宽 `lastColumnOnlyAutoresizingStyle` + 各列 `minWidth`；移除右键菜单"在 Finder 中显示" + `menuRevealInFinder`；`PreviewPane` 移除 `onRevealInFinder` 参数，"Reveal in Finder" 按钮替换为 "Copy Path"。
- 2026-06-17 S23 WorkspaceModel 多实例适配：移除 `defaults` 参数 + `lastFolderKey` + `isBottomPanelVisible` + didSet 持久化；`init(root:sortColumn:sortAscending:showHidden:)` 必传 root，sort/showHidden 由 TabManager 统一管理和持久化。
- 2026-06-16 D1 Kill Change Journal：移除 ChangeJournal 全栈（UI + SQLite + 版本快照 + 终端归因 + Diff），FSWatcher 简化后迁入本模块（纯信号回调，无事件分类），WorkspaceModel 剥离 ~10 属性 + ~7 方法，FileTableView 移除变化色点，PreviewPane 移除版本 section，移除 GRDB 依赖。
- 2026-06-16 S18 `WorkspaceModel` 新增 `reveal(_ fileURLs: [URL])`：navigate 到首项父目录 → 设 `selectedURLs` + `revealSelection`。表格选择信号升级为 `revealSelection: [URL]?`，`FileTableView` 用 `IndexSet` 一次性选中全部行 + 滚动首项。供外部入口（Finder Services Reveal/Open Selection / URL Scheme）跨目录定位文件用。
- 2026-06-15 S17 `WorkspaceModel` 注入 `defaults: UserDefaults` 参数（默认 `.standard`），隔离测试；sortColumn/sortAscending/showHidden 通过 didSet 持久化到 `defaults`，init 时恢复。
- 2026-06-15 S16 新增 `PreviewPane.swift`（右侧预览面板：QLThumbnail + 元数据 + Quick Actions）；`ContentView` 改为 HStack 分栏；⌘⇧P toggle。
- 2026-06-15 S13 `isTerminalVisible` → `isBottomPanelVisible` 语义重命名（底部面板承载终端）。
- 2026-06-14 S10 拖拽到终端：`FileTableView` 新增 `pasteboardWriterForRow`（文件行可拖出）。`ContentView` 终端面板加 `.onDrop` 接收文件拖放。
- 2026-06-14 S9 Send Path to Terminal：右键菜单「发送路径到终端」（单选/多选，shell-escaped）+ ⌘⇧T 快捷键。新增 `ShellEscape.swift`。
- 2026-06-14 S7 打开任意文件夹 + 文件名搜索（M1 收尾）：⌘O 打开文件夹 + Open Recent + 启动恢复 + 拖放文件夹 + ⌘F 搜索栏 + 文件名实时过滤 + Esc 关闭搜索。
- 2026-06-14 S5 右键菜单 + 文件操作落地：NSMenu 右键菜单（单选/多选/空白区域三态）+ Open/Open With…/Trash/Rename/New Folder/Copy Path。~~Reveal in Finder~~ S24 killed。
- 2026-06-14 S4 路径导航 + 排序 + 隐藏文件：路径面包屑栏 + NSTableView 四列列头排序 + ⌘⇧. 隐藏文件 + ⌘⌥C 复制路径。
- 2026-06-14 S6 Quick Look 预览：空格键 toggle `QLPreviewPanel`；`updateNSView` 加 `itemsChanged` 守卫。
- 2026-06-13 S1 落地：启动即家目录的文件列表（四列元数据 + 系统图标）+ 双击进入 / ⌘↑ 返回上级。
