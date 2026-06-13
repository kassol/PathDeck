# AGENTS.md — FileWorkspace

> PathDeck 文件工作台模块。就近覆盖根 `AGENTS.md`。

## 职责

Finder-like 文件浏览：枚举目录、展示文件列表、目录进出导航。产品主心智的承载层，后续 Preview / 多视图 / 搜索 / 右键操作在此扩展。

## 目录结构

| 文件 | 职责 |
|---|---|
| `FileItem.swift` | 文件/目录的值类型 model（`Sendable`） |
| `DirectoryLister.swift` | 无状态目录枚举服务（`nonisolated`，可单测、未来可挪后台） |
| `WorkspaceModel.swift` | `@Observable` 工作区状态：当前目录 + items + 导航方法（MainActor） |
| `FileTableView.swift` | `NSViewRepresentable` 包 `NSTableView`，承载列表交互 |

## 模块规范

- 文件列表用 AppKit `NSTableView`，不用 SwiftUI `Table`：多选 / 拖拽（含 file promise）/ 就地重命名 / type-select / 万级实时增量刷新 / Column 视图等终局需求落在 SwiftUI 结构性弱区。SwiftUI 仅作壳与工具栏。
- 目录 IO 一律走 `DirectoryLister`（`nonisolated`），不在视图层直接读文件系统。
- 列表数据流单向：`WorkspaceModel.items` → `FileTableView`；交互经 `onOpen` 回调 → model 改状态 → 重新 list。
- 不在本模块散用 libghostty / SQLite 符号；跨模块依赖经各自抽象层。

## 依赖关系

- 依赖：Foundation、AppKit、SwiftUI、Observation。
- 被依赖：`ContentView` 装载 `FileTableView` 与 `WorkspaceModel`。

## 变更日志

- 2026-06-13 S1 落地：启动即家目录的文件列表（四列元数据 + 系统图标）+ 双击进入 / ⌘↑ 返回上级。
