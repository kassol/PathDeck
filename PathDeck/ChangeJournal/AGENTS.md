# AGENTS.md — ChangeJournal

> 文件变化感知与记录模块。就近覆盖根 `AGENTS.md`。

## 职责

监听当前工作区目录的文件增删改（FSEvents），写入 SQLite（GRDB），提供变化列表 UI + 终端活跃期间变化归因 + 轻量文件版本快照。

## 目录结构

| 文件 | 职责 |
|---|---|
| `ChangeEvent.swift` | 变化事件值类型 model（`Sendable`，不依赖 GRDB）+ `ChangeTimeGroup` 枚举 + `grouped()` 时间分组纯函数 + `terminalSessionID` 归因字段 |
| `ChangeStore.swift` | GRDB 封装：WAL 模式 SQLite（`changes.db`）初始化、schema migration（v1+v2）、批量写入（含终端归因）、按目录查询 |
| `VersionStore.swift` | GRDB 封装：独立 SQLite（`versions.db`）文件版本快照存储、hash 去重、per-file 上限清理、eligibility 判定 |
| `FSWatcher.swift` | FSEvents 封装（`nonisolated`，后台 DispatchQueue）：监听指定目录、事件 flag 分类、回调通知 |
| `ChangeListView.swift` | SwiftUI 变化列表视图：类型过滤 + 时间分组 + 行点击定位 + 忽略规则编辑 popover + 终端归因图标 + 版本快照图标 |
| `IgnoreRules.swift` | 忽略规则工具：默认模式 + 用户自定义 glob（UserDefaults）+ `fnmatch` 匹配 |

## 模块规范

- GRDB 依赖隔离在 `ChangeStore` / `VersionStore` 内，`ChangeEvent` / `FileVersion` 不引用任何 GRDB 类型。
- SQLite 模式：`journal_mode = WAL` + `synchronous = NORMAL` + `busy_timeout = 5s` + `auto_vacuum = INCREMENTAL`。进程 crash 不丢不坏；仅极端 OS crash 可能丢最后一个 WAL frame（对 change journal 可接受）。
- 数据库路径：`~/Library/Application Support/in.riverflows.PathDeck/changes.db`（事件）、`versions.db`（版本快照，独立数据库，含大 blob）。
- FSWatcher 是 `nonisolated final class: @unchecked Sendable`，C 回调在后台 DispatchQueue 触发，通过 handler 闭包派发结果。调用方（`WorkspaceModel`）dispatch 到主队列后写入 ChangeStore + 刷新 UI。
- 事件分类用 FSEvents flag 组合 + `FileManager.fileExists` ground truth 兜底。文件和目录事件均处理（`kFSEventStreamEventFlagItemIsFile` + `kFSEventStreamEventFlagItemIsDir`）。
- Schema migration 由 GRDB `DatabaseMigrator` 管理，版本化、幂等。

## 依赖关系

- 依赖：Foundation、GRDB（SPM）、CryptoKit（仅 VersionStore SHA256）、SwiftUI（仅 ChangeListView）。
- 被依赖：`WorkspaceModel` 持有 `FSWatcher` + `ChangeStore` + `VersionStore`；`ContentView` 装载 `ChangeListView`。
- 与 `FileWorkspace`、`Terminal` 无相互依赖。

## 变更日志

- 2026-06-15 S14 终端活跃期间变化归因 + 轻量文件版本快照：`ChangeEvent` 新增 `terminalSessionID` 归因字段；`ChangeStore` v2 migration 加列 + `recordBatch` 接受 `terminalSessionID` 参数；新增 `VersionStore`（独立 `versions.db`，`saveVersion` hash 去重 + per-file 10 版本上限自动清理 + `isEligible` 文本类 ≤1MB 判定）；`ChangeListView` 新增终端归因图标 + 版本快照图标 + `versionedPaths` 参数；`WorkspaceModel` 新增 `activeTerminalSessionID` / `versionStore` / `versionedPaths` / `snapshotIfEligible`。M3 闭合，M4 基础落地。90 个单测通过（新增 ChangeStoreTests ×3 + VersionStoreTests ×5）。
- 2026-06-14 S11 变化忽略规则落地：新增 `IgnoreRules.swift`（默认 13 个噪音模式 + 用户自定义 glob + `fnmatch(FNM_CASEFOLD)` 匹配）。`WorkspaceModel.handleFSEvents` 过滤新事件不入库；`refreshChanges` 过滤历史事件不显示 + `hiddenCount` 属性。`ChangeListView` 新增齿轮按钮 + `IgnoreRulesPopover`（查看/编辑规则）+ 底部「已隐藏 N 项」指示。Debug/Release build + 78 个单测通过（新增 IgnoreRulesTests ×6）。
- 2026-06-14 S10 变化面板增强 + FSWatcher coalescing：`ChangeEvent.swift` 新增 `ChangeTimeGroup` 枚举 + `grouped()` 时间分组纯函数（刚刚/5分钟内/今天/更早）+ `nsColor` 属性；`ChangeListView.swift` 重写为类型过滤（全部/新增/修改/删除 FilterBar）+ 时间分组 Section + 行点击选中回调；`FSWatcher.handleRawEvents` 新增 same-path coalescing（同一批次回调中同一 path 只取首条成功分类事件，根因：`touch` 的 `open(O_CREAT)` + `utimes()` 产生 created+modified 两条独立 FSEvents）。
- 2026-06-14 S5 修复：`handleRawEvents` 加 `kFSEventStreamEventFlagItemIsDir` 处理——目录创建/删除事件此前被 `guard isFile` 过滤掉；`classify` 从 `private` 改为 `static`（internal）以便单测。
- 2026-06-14 S3 落地：FSEvents 监听 + SQLite 事件写入 + 变化列表 UI。
