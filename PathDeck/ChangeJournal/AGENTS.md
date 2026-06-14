# AGENTS.md — ChangeJournal

> 文件变化感知与记录模块。就近覆盖根 `AGENTS.md`。

## 职责

监听当前工作区目录的文件增删改（FSEvents），写入 SQLite（GRDB），提供变化列表 UI。产品 Change Journal 能力的基础层，后续 ignore 规则 / 变化聚合 / Terminal 关联归因在此扩展。

## 目录结构

| 文件 | 职责 |
|---|---|
| `ChangeEvent.swift` | 变化事件值类型 model（`Sendable`，不依赖 GRDB）+ `ChangeTimeGroup` 枚举 + `grouped()` 时间分组纯函数 |
| `ChangeStore.swift` | GRDB 封装：WAL 模式 SQLite 初始化、schema migration、批量写入、按目录查询 |
| `FSWatcher.swift` | FSEvents 封装（`nonisolated`，后台 DispatchQueue）：监听指定目录、事件 flag 分类、回调通知 |
| `ChangeListView.swift` | SwiftUI 变化列表视图：类型过滤 + 时间分组 + 行点击定位 + 忽略规则编辑 popover |
| `IgnoreRules.swift` | 忽略规则工具：默认模式 + 用户自定义 glob（UserDefaults）+ `fnmatch` 匹配 |

## 模块规范

- GRDB 依赖隔离在 `ChangeStore` 内，`ChangeEvent` 不引用任何 GRDB 类型。
- SQLite 模式：`journal_mode = WAL` + `synchronous = NORMAL` + `busy_timeout = 5s` + `auto_vacuum = INCREMENTAL`。进程 crash 不丢不坏；仅极端 OS crash 可能丢最后一个 WAL frame（对 change journal 可接受）。
- 数据库路径：`~/Library/Application Support/in.riverflows.PathDeck/changes.db`。
- FSWatcher 是 `nonisolated final class: @unchecked Sendable`，C 回调在后台 DispatchQueue 触发，通过 handler 闭包派发结果。调用方（`WorkspaceModel`）dispatch 到主队列后写入 ChangeStore + 刷新 UI。
- 事件分类用 FSEvents flag 组合 + `FileManager.fileExists` ground truth 兜底。文件和目录事件均处理（`kFSEventStreamEventFlagItemIsFile` + `kFSEventStreamEventFlagItemIsDir`）。
- Schema migration 由 GRDB `DatabaseMigrator` 管理，版本化、幂等。

## 依赖关系

- 依赖：Foundation、GRDB（SPM）、SwiftUI（仅 ChangeListView）。
- 被依赖：`WorkspaceModel` 持有 `FSWatcher` + `ChangeStore`；`ContentView` 装载 `ChangeListView`。
- 与 `FileWorkspace`、`Terminal` 无相互依赖。

## 变更日志

- 2026-06-14 S11 变化忽略规则落地：新增 `IgnoreRules.swift`（默认 13 个噪音模式 + 用户自定义 glob + `fnmatch(FNM_CASEFOLD)` 匹配）。`WorkspaceModel.handleFSEvents` 过滤新事件不入库；`refreshChanges` 过滤历史事件不显示 + `hiddenCount` 属性。`ChangeListView` 新增齿轮按钮 + `IgnoreRulesPopover`（查看/编辑规则）+ 底部「已隐藏 N 项」指示。Debug/Release build + 78 个单测通过（新增 IgnoreRulesTests ×6）。
- 2026-06-14 S10 变化面板增强 + FSWatcher coalescing：`ChangeEvent.swift` 新增 `ChangeTimeGroup` 枚举 + `grouped()` 时间分组纯函数（刚刚/5分钟内/今天/更早）+ `nsColor` 属性；`ChangeListView.swift` 重写为类型过滤（全部/新增/修改/删除 FilterBar）+ 时间分组 Section + 行点击选中回调；`FSWatcher.handleRawEvents` 新增 same-path coalescing（同一批次回调中同一 path 只取首条成功分类事件，根因：`touch` 的 `open(O_CREAT)` + `utimes()` 产生 created+modified 两条独立 FSEvents）。
- 2026-06-14 S5 修复：`handleRawEvents` 加 `kFSEventStreamEventFlagItemIsDir` 处理——目录创建/删除事件此前被 `guard isFile` 过滤掉；`classify` 从 `private` 改为 `static`（internal）以便单测。
- 2026-06-14 S3 落地：FSEvents 监听 + SQLite 事件写入 + 变化列表 UI。
