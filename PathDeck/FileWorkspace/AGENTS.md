# AGENTS.md — FileWorkspace

> PathDeck 文件工作台模块。就近覆盖根 `AGENTS.md`。

## 职责

Finder-like 文件工作台：目录浏览、路径导航、排序、隐藏文件、右键菜单文件操作（Open/Trash/Rename/New Folder）、Quick Look 预览、打开任意文件夹、文件名搜索。后续扩展：多视图模式、Sidebar、内容搜索。

## 目录结构

| 文件 | 职责 |
|---|---|
| `FileItem.swift` | 文件/目录的值类型 model（`Sendable`） |
| `DirectoryLister.swift` | 无状态目录枚举服务（`nonisolated`，可单测、未来可挪后台） |
| `WorkspaceModel.swift` | `@Observable` 工作区状态：当前目录 + items/allItems + 导航 + 排序 + 隐藏文件 + 选中文件 + 文件操作（trash/rename/newFolder）+ 搜索过滤（`searchQuery`/`isSearching`/`applySearch`/`filterItems`）+ 打开文件夹（`openFolder`）。`SortColumn` 枚举、`sortedItems` 静态排序方法 |
| `FileTableView.swift` | `NSViewRepresentable` 包 `NSTableView`（`FileNSTableView` 子类），承载列表交互 + 右键菜单 + inline rename + Quick Look 预览（QLPreviewPanel 所有权 + 数据源） |
| `RecentFolders.swift` | 最近打开文件夹管理（`@Observable`，UserDefaults 持久化，10 项上限，去重） |
| `SearchBarView.swift` | `NSSearchField` 的 `NSViewRepresentable` 包装，实时回调 + Esc 关闭 |

## 模块规范

- 文件列表用 AppKit `NSTableView`，不用 SwiftUI `Table`：多选 / 拖拽（含 file promise）/ 就地重命名 / type-select / 万级实时增量刷新 / Column 视图等终局需求落在 SwiftUI 结构性弱区。SwiftUI 仅作壳与工具栏。
- 目录 IO 一律走 `DirectoryLister`（`nonisolated`），不在视图层直接读文件系统。
- 列表数据流单向：`WorkspaceModel.items` → `FileTableView`；交互经 `onOpen` 回调 → model 改状态 → 重新 list。
- 不在本模块散用 libghostty / SQLite 符号；跨模块依赖经各自抽象层。

## 依赖关系

- 依赖：Foundation、AppKit、SwiftUI、Observation、QuickLookUI、UniformTypeIdentifiers。
- 被依赖：`ContentView` 装载 `FileTableView` 与 `WorkspaceModel`。

## 变更日志

- 2026-06-14 S7 打开任意文件夹 + 文件名搜索（M1 收尾）：⌘O 打开文件夹（NSOpenPanel）+ Open Recent 菜单（RecentFolders，UserDefaults 持久化，10 项上限）+ 启动恢复上次目录（`lastOpenedFolder`）+ 拖放文件夹到窗口（`.onDrop` + UTType.fileURL）+ ⌘F 搜索栏（NSSearchField，SearchBarView）+ 文件名实时过滤（`localizedCaseInsensitiveContains`，`allItems` → `applySearch()` → `items`）+ Esc 关闭搜索。FileCommands 改为 `replacing: .newItem`（合并 Open + New Folder）；ViewCommands 添加 `replacing: .textEditing`（⌘F）。10 个新单测（RecentFolders×4 + SearchFilter×6），56 个总计全通过。
- 2026-06-14 S4 路径导航 + 排序 + 隐藏文件：路径面包屑栏（可点击段跳转）+ NSTableView 四列列头排序（目录始终在前）+ ⌘⇧. 隐藏文件切换 + ⌘⌥C 复制当前路径。排序职责从 DirectoryLister 移至 WorkspaceModel（`sortedItems` 静态方法）。FocusedValue 用 `@Entry` 宏（macOS 26 SDK）。
- 2026-06-14 S5 右键菜单 + 文件操作落地：NSMenu 右键菜单（单选/多选/空白区域三态）+ Open/Open With…/Trash（⌘⌫）/Rename（Enter 触发 inline editing，`doCommandBy:` 拦截 Esc 取消）/New Folder（⌘⇧N + 自动 rename）/Reveal in Finder/Copy Path。FileNSTableView 子类拦截 Return 键；`menu.autoenablesItems = false`；编辑中跳过 `reloadData()`；`clickedRow` 越界保护。
- 2026-06-14 S6 Quick Look 预览：空格键 toggle `QLPreviewPanel`；`FileNSTableView` 持有 QL 所有权；`Coordinator` 实现 `QLPreviewPanelDataSource`+`Delegate`；`handle` 只转发↑↓箭头 + 显式处理空格关闭。`updateNSView` 加 `itemsChanged` 守卫防止无关 `@Observable` 状态变化触发 `reloadData()` 破坏 QL 面板。
- 2026-06-13 S1 落地：启动即家目录的文件列表（四列元数据 + 系统图标）+ 双击进入 / ⌘↑ 返回上级。
