# S3：FSEvents 监听 + SQLite 事件写入

> 日期：2026-06-14　需求：fsevents-sqlite（M0 切片 S3）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-13-s2-libghostty-smoke.md`。

## 背景定位（M0 切片路线）

| 切片 | 内容 | 状态 |
|---|---|---|
| S1 | 启动即家目录 + NSTableView 文件列表 + 进出目录 | 已完成 ✓ |
| S2 | libghostty 嵌入冒烟 | 已完成 ✓ |
| **S3** | **FSEvents 监听 demo + SQLite 事件写入 demo** | **完成 ✓** |

S3 是 M0（技术验证）的最后一块。完成后 M0 三项验收标准全部达成：

1. ✓ 能在 App 内打开真实 Terminal（S2）
2. → 能监听当前文件夹新增/修改/删除（S3）
3. → 能把变化写入 SQLite 并显示在简单列表中（S3）

## 目标与验证标准

App 监听当前目录的文件增删改，变化写入 SQLite，显示在简单列表中，文件列表自动刷新。

可验证（手动）：

1. 打开 App，进入某目录。
2. 在 Finder 或终端里 `touch newfile.txt` → 文件列表自动出现 `newfile.txt`，底部 changes 列表显示一条 "added" 记录。
3. 修改该文件（`echo x >> newfile.txt`）→ changes 列表显示 "modified"。
4. 删除该文件（`rm newfile.txt`）→ 文件列表消失，changes 列表显示 "deleted"。
5. 切换目录 → watcher 跟随新目录，changes 列表展示新目录的记录。
6. 退出重开 → 历史记录从 SQLite 恢复显示。

## 新增依赖

**GRDB.swift**（SPM，MIT）——Swift SQLite 封装。通过 Xcode SPM 引入（`Package Dependencies`）。

选 GRDB 而非裸 `sqlite3` C API：ChangeJournal 是会持续增长的模块（M3 变化聚合 / ignore 规则 / 关联归因），GRDB 的迁移、类型安全查询、DatabaseRegionObservation 在后续切片有价值。

## SQLite 模式与数据安全

这是本切片最需要谨慎的技术决策。ChangeJournal 的写入场景：FSEvents 回调在后台 DispatchQueue 触发，需要写入 SQLite；主线程读取展示。并发读写 + 进程随时可能被杀。

### 选型：WAL 模式 + PRAGMA synchronous = NORMAL

| 配置 | 值 | 理由 |
|---|---|---|
| `journal_mode` | `WAL` | 允许并发读写（readers 不阻塞 writer），crash-safe |
| `synchronous` | `NORMAL`（WAL 模式默认值） | 进程 crash 不丢数据；仅在极端 OS crash / 断电时可能丢最后一个 WAL frame。对 change journal 可接受——丢一条事件记录不影响文件系统真实状态 |
| `busy_timeout` | 5000ms | 写冲突时自旋等待而非立即 `SQLITE_BUSY` 报错 |
| `auto_vacuum` | `INCREMENTAL` | 长期运行后不留空洞，配合定期 `incremental_vacuum` |

### 不用的模式及原因

| 模式 | 为什么不用 |
|---|---|
| `synchronous = OFF` | 进程 crash 即损坏，不可接受 |
| `synchronous = FULL` | WAL 下每次写都 fsync，对高频 FSEvents 写入有性能风险，收益（抗 OS crash）对 change journal 不值 |
| `journal_mode = DELETE`（默认） | 读写互斥，FSEvents 高频写入时阻塞主线程读取 |
| `DatabasePool` | GRDB 的 Pool 用独立 reader connection，M0 单目录场景 `DatabaseQueue`（串行写 + 读）已够用，Pool 是 M3+ 的优化项 |

### 防御措施

- **GRDB `DatabaseQueue`**：所有数据库访问经 `DatabaseQueue.write {}` / `DatabaseQueue.read {}` 串行化，消除应用层并发 bug。FSEvents 回调 dispatch 到主队列后再写入，与读取天然串行。
- **事务粒度**：每批 FSEvents 回调（一次 `FSEventStreamCallback` 可返回多个路径）包在一个 `write` 事务内，要么全写入要么全回滚。
- **Schema migration**：GRDB `DatabaseMigrator` 管理，每个 migration 带版本号，幂等，未来加字段不碎库。
- **数据库路径**：`~/Library/Application Support/in.riverflows.PathDeck/changes.db`。目录不存在时创建。不放 tmp、不放 Caches（会被系统清）。

## 新增模块：`PathDeck/ChangeJournal/`

| 文件 | 职责 |
|---|---|
| `ChangeEvent.swift` | 值类型 model：`id`(Int64 自增) / `path`(String) / `fileName`(String) / `eventType`(enum: added/modified/deleted) / `timestamp`(Date) / `directory`(String) |
| `ChangeStore.swift` | GRDB 封装：`DatabaseQueue` 初始化（WAL + NORMAL）、schema migration、写入事件、按目录查询最近 N 条、清理旧记录 |
| `FSWatcher.swift` | FSEvents 封装：`FSEventStreamCreate` + `kFSEventStreamCreateFlagFileEvents`，监听指定目录，解析事件 flag 判断类型，回调通知。`watch(directory:)` / `stop()` 生命周期 |
| `ChangeListView.swift` | 简单 SwiftUI List 或 NSTableView，显示 type icon + 文件名 + 相对时间 |
| `AGENTS.md` | 模块文档 |

## 改动现有文件

| 文件 | 改动 |
|---|---|
| `WorkspaceModel.swift` | 持有 `FSWatcher` + `ChangeStore`；目录切换时 `watcher.watch(newDir)` + 刷新 changes 查询；watcher 回调触发 `reload()` + 写入 ChangeStore |
| `ContentView.swift` | 底部加 `ChangeListView`，用 `VSplitView` 或 SwiftUI `VStack` 分割文件列表与变化列表 |
| `PathDeck.xcodeproj` | SPM 依赖 GRDB；`ChangeJournal/AGENTS.md` 加入 `membershipExceptions` |

## FSEvents 技术要点

### 事件类型判断

FSEvents 的 flag 是位掩码组合，不是互斥枚举。一次回调可能同时带 `kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified`。判断逻辑：

```
if flags contains ItemRemoved && 文件不存在 → deleted
if flags contains ItemCreated && 文件存在   → added
if flags contains ItemModified              → modified
if flags contains ItemRenamed               → 检查文件存在性：存在 → added（rename 目标），不存在 → deleted（rename 源）
```

文件存在性检查是 FSEvents 事件分类的标准做法——flag 组合不总可靠，`FileManager.fileExists` 作为 ground truth 兜底。

### Stream 配置

- `latency`：0.3s（攒批间隔，平衡实时性与写入频率）
- `kFSEventStreamCreateFlagFileEvents`：逐文件粒度（不加则只有目录级）
- `kFSEventStreamCreateFlagUseCFTypes`：回调参数用 CFArray/CFString
- `kFSEventStreamCreateFlagNoDefer`：首个事件立即回调，不等 latency 窗口

### 生命周期

`FSWatcher` 持有 `FSEventStreamRef`。`watch(directory:)` 时 stop 旧 stream + 创建新 stream + schedule 到后台 DispatchQueue。`deinit` 时 `stop()` + `invalidate()` + `release()`。

回调是 `@convention(c)` 的 C 函数指针，context 经 `UnsafeMutableRawPointer` 传 `FSWatcher` 实例（`Unmanaged.passUnretained`）。

## Scope

- FSEvents 监听当前目录（一层，不递归子目录）
- 事件写入 SQLite（WAL 模式）
- 底部简单列表展示（type icon + 文件名 + 时间）
- 目录切换时 watcher 跟随 + 查询切换
- 文件列表自动刷新

## Non-scope

- 不做 ignore 规则（`.gitignore` / `.DS_Store` 过滤等）
- 不做 diff / preview
- 不做跨目录聚合
- 不做 Terminal 活跃期间的弱关联归因
- 不接 ChangeJournal 到 Terminal 模块
- 不做 DatabasePool 优化
- 不做变化列表的筛选 / 分组 / 搜索
- 不做旧记录自动清理策略（M3 考虑）

## 验证

- 自动：单元测试覆盖 `ChangeStore`（写入 / 查询 / migration）+ `FSWatcher` 事件解析逻辑（可 mock 或用临时目录实测）。
- 构建：Debug/Release clean build 通过。
- GUI 冒烟：人工在 Xcode 走查上述 6 项验收标准。

## 工作量

约 5 个新文件 + 3 个改动文件，~400-500 行新代码。

## 实现顺序

1. Xcode SPM 引入 GRDB
2. `ChangeEvent` model
3. `ChangeStore`（初始化 + migration + 读写）+ 单元测试
4. `FSWatcher`（事件监听 + 类型判断）
5. `WorkspaceModel` 接入 watcher + store
6. `ChangeListView` + `ContentView` 底部布局
7. `ChangeJournal/AGENTS.md` + pbxproj membershipExceptions
8. clean build + 单元测试 + GUI 走查
