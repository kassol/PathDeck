# AGENTS.md — ChangeJournal

> 文件变化感知与记录模块。就近覆盖根 `AGENTS.md`。

## 职责

监听当前工作区目录的文件增删改（FSEvents），写入 SQLite（GRDB），提供变化列表 UI。产品 Change Journal 能力的基础层，后续 ignore 规则 / 变化聚合 / Terminal 关联归因在此扩展。

## 目录结构

| 文件 | 职责 |
|---|---|
| `ChangeEvent.swift` | 变化事件值类型 model（`Sendable`，不依赖 GRDB） |
| `ChangeStore.swift` | GRDB 封装：WAL 模式 SQLite 初始化、schema migration、批量写入、按目录查询 |
| `FSWatcher.swift` | FSEvents 封装（`nonisolated`，后台 DispatchQueue）：监听指定目录、事件 flag 分类、回调通知 |
| `ChangeListView.swift` | SwiftUI 变化列表视图（type icon + 文件名 + 相对时间） |

## 模块规范

- GRDB 依赖隔离在 `ChangeStore` 内，`ChangeEvent` 不引用任何 GRDB 类型。
- SQLite 模式：`journal_mode = WAL` + `synchronous = NORMAL` + `busy_timeout = 5s` + `auto_vacuum = INCREMENTAL`。进程 crash 不丢不坏；仅极端 OS crash 可能丢最后一个 WAL frame（对 change journal 可接受）。
- 数据库路径：`~/Library/Application Support/in.riverflows.PathDeck/changes.db`。
- FSWatcher 是 `nonisolated final class: @unchecked Sendable`，C 回调在后台 DispatchQueue 触发，通过 handler 闭包派发结果。调用方（`WorkspaceModel`）dispatch 到主队列后写入 ChangeStore + 刷新 UI。
- 事件分类用 FSEvents flag 组合 + `FileManager.fileExists` ground truth 兜底。
- Schema migration 由 GRDB `DatabaseMigrator` 管理，版本化、幂等。

## 依赖关系

- 依赖：Foundation、GRDB（SPM）、SwiftUI（仅 ChangeListView）。
- 被依赖：`WorkspaceModel` 持有 `FSWatcher` + `ChangeStore`；`ContentView` 装载 `ChangeListView`。
- 与 `FileWorkspace`、`Terminal` 无相互依赖。

## 变更日志

- 2026-06-14 S3 落地：FSEvents 监听 + SQLite 事件写入 + 变化列表 UI。
