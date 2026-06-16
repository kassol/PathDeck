# S19–S21 质量加固：writeText 竞态 / 变化归因 / 版本 baseline

> 计划日期：2026-06-16　|　状态：待实现（plan 已 Sir 确认方向，决策 D-a/D-b/D-c/D-d 已批）
> 依赖：S14（归因字段 + VersionStore）、S15（Diff/Restore）、S17（pending buffer + onSurfaceReady）已落地
> 一份文档，三个独立可合并切片。落地顺序 **S19 → S20 → S21**，每块单独 commit、跑全量单测绿后再进下一块。

## 1. 背景与目标

S11–S18 的多轮架构审查链反复标记三处「系统性语义脆弱点」——不是偶发 bug，是模型层面就站不住的逻辑。Sir 在 S18 后选择「先深挖清技术债，不追 Beta、不碰新功能」。本计划把三处脆弱点各做到实现级 decision-complete。

三处债的共性：**核心逻辑都散在 `@Observable` + Timer + 真实系统回调（FSEvents / libghostty）耦合的方法里，无法单测**。因此每块的加固都包含「抽纯函数 → 补临时目录隔离单测」这一外科手术式重构（决策 D-c），把正确性逻辑从不可测的宿主里剥离出来。

| 切片 | 债 | 用户可感知的后果 |
|---|---|---|
| **S19** | 终端 `writeText` 注入在 surface 创建失败时静默丢文本 | 拖文件/发路径到刚新建的终端 tab，偶发无声失败；同周期关两个 tab 只关掉一个 |
| **S20** | 变化归因贴的是「UI 当前选中 tab」，与「谁写了文件」零因果 | Change Journal（差异化核心）的归因是假信号：后台 tab 写文件算到前台、关 tab 后算到相邻 tab |
| **S21** | 版本快照只录「修改后」，进目录不录 baseline | 既存文件第一次被改后，diff/restore 拿不到真正的 before |

## 2. Scope / 非 Scope

**Scope（本计划三切片）**
- S19：surface 创建失败显式回调 + pending 可观测丢弃 + handleSurfaceClose 遍历全部已退出 surface + `PendingTextBuffer` 纯类型化 + 上限防护。
- S20：归因重构为「事件产生时刻捕获终端 session 快照 + cwd 前缀匹配纯函数」，cwd 缺失/不匹配返回 `nil`（绝不乱归因）；`recordBatch` 改 per-event 归因。
- S21：进目录后台异步预录 eligible 文本文件 baseline（字节预算兜底）+ `performRestore` 抽纯函数 + 外部脏三态语义与文案修正。

**非 Scope（明确不做，留独立切片或按需评估）**
- baseline **pin 免清理**（加 `isPinned` 列 + migration v2）——当前靠默认 10 版上限，>10 次写盘才可能淘汰 baseline，概率低，暂不做（见 §7-决策点 2）。
- 终端 view 从未挂 window 时的 pending 根治——属设计层时序，本计划用 `onPendingDropped` 暴露 + 5s 超时兜底，不根治（见 S19 openConcern）。
- 进程级精确归因——PRD §R2 明确接受「不能低成本精确知道哪个进程写了哪个文件」，本计划只做 cwd 弱关联。
- 重启后 per-session `lastActiveAt` 持久化——重启初期归因时序暂缺，靠 cwd 匹配仍能命中，不夹带持久化。

## 3. 已批总体决策

| # | 决策 | 落点 |
|---|---|---|
| D-a | 归因用 cwd 前缀匹配 + 事件时刻捕获，不匹配则 `nil` | S20 |
| D-b | baseline 进目录异步低优先级预录 + 字节预算上限（16MB/目录） | S21 |
| D-c | 归因判定、restore、surface-close 收集等核心逻辑抽纯函数再补单测 | S19/S20/S21 |
| D-d | 顺序 S19 → S20 → S21，三个独立切片各自交付 | 全局 |

## 4. 执行顺序与 phase 独立性（对抗性评审结论）

```
S19 (最独立, 最安全)          S20 (改动面最大)              S21 (最小, 纯增量)
只动 Terminal/ 三文件     删 activeTerminalSessionID      reload 末尾 +1 行
+ 新增 PendingTextBuffer   改 recordBatch 签名(连带          + 新私有方法
+ TerminalSessionTests     ChangeStoreTests 11 处)         + VersionStore 静态函数
                           改 ContentView 推快照            + DiffView 文案/三态
   │                          │                              │
   └── 独立合并、全测绿 ───────┴── 独立合并、全测绿 ──────────┴── 独立合并、全测绿
```

- **S19 先做**：完全独立，无外部依赖，风险最低，热身。
- **S20 居中**：改动面最大、最易引入编译断裂（删字段连带 ContentView、改 `recordBatch` 连带 11 处测试），单独成一个 commit 验证全测试绿再继续。**S20 必须先于 S21**：S20 改 `ContentView`，S21 不碰 `ContentView`，先做 S20 让 `ContentView` 一次性改完。
- **S21 压轴**：4 文件纯增量，无签名破坏、无 schema 迁移。
- **S20 与 S21 在 `WorkspaceModel` 的 hunk 不重叠**（评审逐行确认）：S20 改 `init`(:113-117 FSWatcher 闭包)/`handleFSEvents`(:295-327)/删 `:39`；S21 只在 `reload()`(:240-245) 末尾追加一行 + 新增独立私有方法。无文本冲突。
- 每块合并后跑全量 ~149 单测确认绿，再进下一块。

> 所有 `file:line` 来自实读当前代码（S18 提交点）。切片间会移行，**落地时以实际代码为准，按符号定位而非死记行号**。

---

## 5. S19 — 终端 writeText 竞态

**根因**：`GhosttySurfaceView.swift:99-102` 与 `:137-140` 两条失败 return（app 未初始化 / `ghostty_surface_new` 返回 nil）都不通知 engine（`onSurfaceReady?()` 仅在 `:146` 成功路径调），pending 文本只能等 `GhosttyTerminalEngine.swift:75-80` 盲目 5s `asyncAfter` 静默 NSLog 丢弃；`handleSurfaceClose`(:82-89) 找到首个 `process_exited` surface 即 `return`，同周期多 tab 退出只回调一个。

**改动文件**
- `PathDeck/Terminal/GhosttySurfaceView.swift` — 修改：失败两分支调 `onSurfaceFailed`；成功/失败都清两个回调。
- `PathDeck/Terminal/GhosttyTerminalEngine.swift` — 修改：`pendingTexts` → `pendingBuffers: [UUID: PendingTextBuffer]`；新增 `onPendingDropped` 回调、`handleSurfaceCreationFailure`、token 化可取消超时；`handleSurfaceClose` 遍历全部已退出。
- `PathDeck/Terminal/PendingTextBuffer.swift` — **新建**：纯值类型 buffer。
- `PathDeckTests/PendingTextBufferTests.swift` — **新建**。
- `PathDeckTests/TerminalSessionTests.swift` — 修改：补 close/超时取消断言。

**纯类型与枚举**
```swift
struct PendingTextBuffer {                       // 纯值类型，无 Dispatch/UUID 依赖
    mutating func enqueue(_ text: String) -> EnqueueResult
    mutating func drain() -> [String]            // 返回全部并清空
    var isEmpty: Bool; var totalBytes: Int; var count: Int
    // maxCount=64 / maxBytes=256KB；超限从队头丢最旧；单条超 maxBytes 仍接受（不丢用户唯一输入）
    // byte 计费用 text.utf8.count
}
struct EnqueueResult { let accepted: Bool; let droppedFromOverflow: [String] }
enum SurfaceFailureReason: String { case appNotInitialized, surfaceNewReturnedNil }
enum PendingDropReason { case surfaceCreationFailed, timeout, overflow, sessionClosed }
```

**实现步骤**
1. `GhosttySurfaceView`：在 `onSurfaceReady` 旁新增 `var onSurfaceFailed: ((SurfaceFailureReason) -> Void)?`（**不改 `onSurfaceReady` 签名**，避免触动不设回调的 `TerminalSmokeView`；新增独立回调是最小改动）。
2. 两条失败分支在 `NSLog` 后插 `onSurfaceFailed?(.appNotInitialized / .surfaceNewReturnedNil); onSurfaceFailed = nil; onSurfaceReady = nil` 再 return；成功路径在 `onSurfaceReady = nil` 同处补 `onSurfaceFailed = nil`。
3. `GhosttyTerminalEngine`：`pendingTexts` 改 `pendingBuffers: [UUID: PendingTextBuffer]`；新增 `onPendingDropped: ((UUID, Int, PendingDropReason) -> Void)?`（public var，挂在具体类**不入 `TerminalEngine` 协议**——`ContentView` 以具体类型持有 engine，保持协议最小）。
4. `terminalView(for:)` 内补 `view.onSurfaceFailed = { [weak self] r in self?.handleSurfaceCreationFailure(id: id, reason: r) }`。
5. 新增 `handleSurfaceCreationFailure`：`drain` pending → 非空则 `onPendingDropped?(id, n, .surfaceCreationFailed)` → 取消超时。**失败立即显式丢弃并上报，不再等 5s**。
6. `writeText` else 分支：`enqueue` 返回溢出则 `onPendingDropped?(id, n, .overflow)`。
7. 超时 token 化：新增 `pendingTimeoutTokens: [UUID: UUID]`，`asyncAfter` 闭包先校验 token 再 drain；超时丢弃调 `onPendingDropped?(id, n, .timeout)`。新增 `cancelPendingTimeout(_:)`，在 flush/失败/`closeSession` 调用（避免 close 后 5s 残留闭包误触发）。
8. `handleSurfaceClose` 去 `return`，**先收集后回调**防遍历中改集合：`var exited=[]; for (id,v) in surfaceViews { if let s=v.surface, ghostty_surface_process_exited(s) { exited.append(id) } }; for id in exited { onSessionClose?(id) }`（`onSessionClose→ContentView.closeTerminalTab→closeSession` 会改 `surfaceViews`，故先快照 id）。
9. **测试缝（评审补强）**：把「找出全部已退出 session」抽成纯函数 `static func exitedSessionIDs(from: [(id: UUID, exited: Bool)]) -> [UUID]`，engine 里只做 `surface → bool` 的映射——让多 tab 退出全回调这条核心修复脱离 libghostty 可单测。
10. **Blocker（评审）**：要 `@testable` 断言的 `pendingBuffers` / `pendingTimeoutTokens` 必须从 `private` 降为 `internal`（Swift `@testable` 只暴露 `internal` 不暴露 `private`）。这是本切片自引入的测试缝，先做否则单测写不了。
11. `ContentView` setupEngineCallbacks：挂 `terminalEngine.onPendingDropped = { id,n,r in NSLog(...) }`（最小实现仅日志，不引入未被要求的 UI 提示）。

**测试矩阵**

| 用例 | given → expect | 文件 |
|---|---|---|
| `enqueuePreservesFIFOOrder` | enqueue a/b/c → drain==[a,b,c]，drain 后 isEmpty | PendingTextBufferTests |
| `enqueueOverflowDropsOldestByCount` | maxCount=2，a/b/c → droppedFromOverflow==[a]，drain==[b,c] | PendingTextBufferTests |
| `enqueueOverflowDropsOldestByBytes` | maxBytes=4，三条各 2B → totalBytes≤4，最旧逐出 | PendingTextBufferTests |
| `singleTextExceedingMaxBytesStillAccepted` | maxBytes=4，单条 8B → 仍接受，drain 返回该条 | PendingTextBufferTests |
| `exitedSessionIDsReturnsAllExited` | [(A,true),(B,false),(C,true)] → [A,C]（**多 tab 退出核心修复**） | TerminalSessionTests |
| `onPendingDroppedFiresOnOverflow` | 注入 onPendingDropped，灌超限 → reason==.overflow（评审补漏） | TerminalSessionTests |
| `closeSessionDropsPendingAndCancelsTimeout` | create→writeText 入队→close → pendingBuffers 无此 id，5s 内 timeout 不触发（@testable 断 pendingTimeoutTokens） | TerminalSessionTests |

**手动走查**（单测测不到——依赖真实 `ghostty_surface_t`）
- 新建终端 tab 后立即拖路径到终端区 → surface 就绪后路径正确注入、顺序对、无丢失。
- 同周期关两个 tab（两 tab 内几乎同时 `exit`）→ 两个 tab 都被移除（验证遍历全部已退出）。
- 快速向未就绪 tab 灌 >64 条或 >256KB → Console 出现 `.overflow` 丢弃日志，最旧丢、最新留并最终注入。

**回滚**：`git checkout PathDeck/Terminal/GhosttySurfaceView.swift PathDeck/Terminal/GhosttyTerminalEngine.swift PathDeckTests/TerminalSessionTests.swift && rm -f PathDeck/Terminal/PendingTextBuffer.swift PathDeckTests/PendingTextBufferTests.swift`（pbxproj 未改）。

**评审已纠偏**：缺陷清单里「deinit 不清 pending」非真实缺陷——`deinit` 时对象整体释放，`pendingBuffers` 随之消亡，不存在泄漏。真正要修的是 `closeSession` 已清 pending 但未取消超时（本方案已修）。

---

## 6. S20 — 变化归因纯函数化 + cwd 匹配

**根因**：`WorkspaceModel.swift:307` 在 FSWatcher flush 时刻（事件产生后 ≥0.5s）读 `activeTerminalSessionID`，该字段由 `ContentView.swift:88` `onChange(activeTerminalID)` 赋值 = UI 当前选中 tab，与「谁写了文件」无因果；coalesce 窗口内切/关 tab 会把整批事件贴成切换后的值（关 tab 时 `ContentView.swift:330-332` `activeTerminalID` 跳相邻 tab）。

**改动文件**
- `PathDeck/ChangeJournal/TerminalAttribution.swift` — **新建**：纯归因函数 + `TerminalActivitySnapshot` 值类型。
- `PathDeck/ChangeJournal/FSWatcher.swift` — 修改：handler 签名加 `snapshots`；`handleRawEvents` 入队时刻捕获快照；pending 并存 per-path 快照；flush/stop 随 batch 带出。
- `PathDeck/FileWorkspace/WorkspaceModel.swift` — 修改：加锁的 `terminalSnapshots` + `snapshotProvider`；`handleFSEvents` 改 per-event 快照走纯函数归因；删 `:39` `activeTerminalSessionID`。
- `PathDeck/ContentView.swift` — 修改：`onChange(activeTerminalID)`/`onCwdChange`/`createTerminalTab`/`closeTerminalTab` 推送快照到 model。
- `PathDeck/ChangeJournal/ChangeStore.swift` — 修改：`recordBatch` 改 per-event `terminalSessionID`（batch 元组加字段，去整批单一参数）。
- `PathDeckTests/TerminalAttributionTests.swift` — **新建**：纯函数全场景。
- `PathDeckTests/ChangeStoreTests.swift` — 修改：适配 `recordBatch` 新签名。

**纯类型与函数**
```swift
struct TerminalActivitySnapshot: Sendable {       // 供 FSWatcher 后台队列搬运
    let id: UUID; let cwd: URL?; let lastActive: Date   // cwd==nil 显式表达「未知→不归因」
}
enum TerminalAttribution {
    // eventPath 在某 snapshot.cwd 前缀下则命中；多命中取 lastActive 最大者；无命中/全 nil → nil
    static func attribute(eventPath: String, snapshots: [TerminalActivitySnapshot]) -> UUID?
}
```
前缀匹配：标准化路径后 `ep == cp || ep.hasPrefix(cp + "/")`（用 `cp + "/"` 边界对齐，避免 `/work/proj-backup` 误配 `/work/proj`）。

**实现步骤**
1. 新建 `TerminalAttribution.swift`：`attribute` 用 `standardizedFileURL.path(percentEncoded:false)` 标准化两侧，收集命中后 `.max(by:{ $0.lastActive < $1.lastActive })?.id`。
2. `ChangeStore.recordBatch`：元组 `(path,type,directory)` → `(path,type,directory,terminalSessionID: UUID?)`，删方法级 `terminalSessionID` 参数；循环内 per-event `INSERT`。
3. `FSWatcher`：handler 签名加 `snapshots: [TerminalActivitySnapshot]`；新增 `snapshotProvider: () -> [TerminalActivitySnapshot]`（init 参数）+ `pendingSnapshots: [String: [TerminalActivitySnapshot]]`。
4. **入队时刻捕获**：在 `pending[path] = mergeType(...)` 同处，**仅当 `pendingSnapshots[path] == nil`** 时 `pendingSnapshots[path] = snapshotProvider()`（首次见 path = 最接近写入时刻，coalesce 后续不覆盖——直接消除「coalesce 跨 tab 切换污染」根因）。`snapshotProvider` 在后台 queue 调用，须 thread-safe。
5. flush/stop：batch 改 `pending.map { (path:$0.key, type:$0.value, snapshots: pendingSnapshots[$0.key] ?? []) }`；清空时一并 `pendingSnapshots.removeAll()`。
6. `WorkspaceModel`：新增 `private let snapshotsLock = NSLock()` + `private var terminalSnapshots: [TerminalActivitySnapshot]`；`func updateTerminalSnapshots(_:)`（加锁写）+ `readTerminalSnapshots()`（加锁读返回副本）。watcher init 传 `snapshotProvider: { [weak self] in self?.readTerminalSnapshots() ?? [] }`。
7. `handleFSEvents`：删 `:307` `terminalSessionID: activeTerminalSessionID`；对每个 accepted event 调 `TerminalAttribution.attribute(eventPath:snapshots:)` 得 per-event sessionID，组装四元组 batch。
8. 删 `WorkspaceModel.swift:39` `activeTerminalSessionID`（已无引用）。
9. `ContentView` `onChange(activeTerminalID)`：改调 `model.updateTerminalSnapshots(buildSnapshots())`。新增私有 `buildSnapshots()` 把 `terminalSessions` 映射为快照——active 那个 `lastActive=Date()`（now），其余沿用各自 `currentCwd` 与已存 `lastActiveAt`。**`TerminalSession` 增 `var lastActiveAt: Date?`（默认 nil）**，active 切换时给新 active 打戳 now。
10. `onCwdChange` / `createTerminalTab` / `closeTerminalTab`：任一改动 `terminalSessions` 后都调 `updateTerminalSnapshots(buildSnapshots())`（cwd 变化也要刷新）。
11. **Blocker（评审）**：`recordBatch` 改 per-event 后，`ChangeStoreTests` 全部 `recordBatch` 调用点（约 `:20/:35/:51/:55/:69-72/:83/:93/:108/:123/:137/:141`）须同步改：旧三元组补第四字段 `terminalSessionID: nil`；**特别注意 `:69-72` 的 `batch` 局部变量是 `[(path,type,directory)]` 数组、`map` 闭包要补 `terminalSessionID: nil`**；`terminalSessionIDWrittenAndRead`/`v1EventsReadBack` 改为 per-event 第四字段传 sessionID。不改则整个测试 target 不编译。

**测试矩阵**

| 用例 | given → expect | 文件 |
|---|---|---|
| `attributeMatchesSingleSessionUnderCwd` | cwd=/work/proj, event=/work/proj/a.txt → 该 id | TerminalAttributionTests |
| `attributeMultiSessionPicksMostRecentlyActive` | 两 session 同 cwd，lastActive 一早一晚 → 较晚者 | TerminalAttributionTests |
| `attributeNoSessionUnderCwdReturnsNil` | cwd=/other, event=/work/proj/a.txt → nil | TerminalAttributionTests |
| `attributeNilCwdReturnsNil` | cwd=nil → nil | TerminalAttributionTests |
| `attributeEmptySnapshotsReturnsNil` | snapshots=[]（非终端来源） → nil | TerminalAttributionTests |
| `attributePrefixBoundaryNotFooledBySiblingDir` | cwd=/work/proj, event=/work/proj-backup/a.txt → nil | TerminalAttributionTests |
| `attributeEventEqualsCwdItself` | cwd=/work/proj, event=/work/proj → 该 id | TerminalAttributionTests |
| `attributeNestedCwd…`（tie-break） | /work 与 /work/proj 都命中 → 见 §7-决策点 1 锁定语义 | TerminalAttributionTests |
| `recordBatchPerEventSessionID` | 两 event：sessionID=X / nil → 读回首条 X、次条 nil | ChangeStoreTests |

**测试缝缺口（评审标记，需补）**：「coalesce 不覆盖首次快照」的防污染核心逻辑在 fileprivate `handleRawEvents`，依赖真实 FSEventStream，难直接单测。补法：把 nil-coalescing 决策测出来——`mergeSnapshot(existing: [Snapshot]?, provider: () -> [Snapshot]) -> [Snapshot]`（existing 非 nil 则原样返回，nil 则调 provider），单测「第二次不覆盖」。

**手动走查**
- 开两 tab，A cwd=工作区、B cwd=别处；在 A 里 `touch` 文件 → 切到 B → changes 列表刷新 → 该文件归因到 **A**（当前代码错归到 B）。
- Finder 直接在工作区新建文件（无终端 cwd 落在此或 cwd 未上报）→ changes 行**不显示终端图标**（sessionID=nil）。
- 关闭正在写文件的活跃 tab → 延迟事件不被归到跳转后的相邻 tab；该 tab 已不在快照里则归 nil。

**回滚**：`git checkout` 还原 5 个改动文件 + 删 `TerminalAttribution.swift`/`TerminalAttributionTests.swift`。**无 schema 变更**（`terminalSessionID` 列 S14 已存在，本切片只改写入来源），回滚后旧行为恢复、DB 兼容。

---

## 7. S21 — 版本 baseline 预录 + restore 纯函数化

**根因**：`WorkspaceModel.swift:310-311` `snapshotIfEligible` 只在写盘后的 `.added/.modified` FSEvent 回调里触发，app 进目录（`navigate→reload`，`:133-141`/`:240-245`）对既存文件从不录基线，第一次外部修改时 store 里只有「修改后」，`DiffView.loadDiff`(:124-129) 拿不到真 before；`performRestore`(:148-171) 全在 `@State` 内、零端到端测试。

**改动文件**
- `PathDeck/FileWorkspace/WorkspaceModel.swift` — 修改：`reload()` 末尾触发 `preRecordBaselines()`；新增私有 `preRecordBaselines()`。
- `PathDeck/ChangeJournal/VersionStore.swift` — 修改：新增静态 `recordBaselines`（预录批处理 + 字节预算）与 `enum FileRestore`（restore 文件操作）；类加 `@unchecked Sendable`。
- `PathDeck/ChangeJournal/DiffView.swift` — 修改：`loadDiff` 区分外部脏三态 + 文案；`performRestore` 改调静态纯函数。
- `PathDeckTests/VersionStoreTests.swift` — 修改：新增 `recordBaselines` 与 `FileRestore` 端到端单测（临时目录）。

**纯函数**
```swift
// 只对从未快照过的文件（latestVersion==nil）录基线，建立真 before；累计 ≤ byteBudget 后停
static func recordBaselines(_ store: VersionStore, urls: [URL], directory: String,
                            byteBudget: Int) -> (recorded: Int, skipped: Int, truncated: Bool)

// 复刻 performRestore 的纯文件操作：读当前→saveVersion(快照当前态保证可撤销)→atomic 写→replaceItemAt
enum FileRestore { static func restore(store: VersionStore, path: String, snapshotContent: Data) throws }
```

**实现步骤**
1. `VersionStore.swift:15` `final class VersionStore` → `final class VersionStore: @unchecked Sendable`（`dbQueue` 线程安全，加标注以能被 `DispatchQueue.global` 闭包安全捕获，不引入 actor，符合 D2 预留 Sendable 方向）。〔落地核对：确认 `dbQueue` 的实际类型与线程安全保证〕
2. 新增 `recordBaselines`：遍历 urls，`isEligible` 且 `store.latestVersion(for:)==nil`（**只录从未快照过的，避免用进目录时的当前态覆盖更早真基线**）才读盘；累加 `content.count`，`> byteBudget` 则 `truncated=true; break`，否则 `saveVersion`；返回计数供 log。
3. 新增 `enum FileRestore.restore`：`Data(contentsOf:)` 读当前 → `saveVersion`（快照当前态）→ 写 `.<name>.pathdeck-restore` 临时文件 `.atomic` → `FileManager.replaceItemAt`；失败清理临时文件并 rethrow。
4. `WorkspaceModel.swift:240-245` `reload()` 末尾（`refreshChanges()` 后）追加 `preRecordBaselines()`。
5. 新增私有 `preRecordBaselines()`：`guard let store = versionStore`；`urls = allItems.filter{ !$0.isDirectory }.map(\.url)`（**用 `allItems` 不用 `items`** —— 见 Blocker）；`DispatchQueue.global(qos:.background).async { let r = VersionStore.recordBaselines(store, urls:urls, directory:dir, byteBudget: 16*1024*1024); if r.truncated { NSLog(...) } }`（捕获值类型 URL 数组 + dir + store 引用，**不回主线程改 `@Observable`**，`versionedPaths` 由后续 FSEvent 触发的 reload 刷新）。
6. `DiffView.loadDiff`(:123-134) 引入 `isExternallyDirty` `@State`：`latest.contentHash == currentHash` → 磁盘=最新快照，比 `previousVersionWithContent`，`isExternallyDirty=false`；`latest` 存在但 hash≠current → 外部脏，`latest` 即上一已知态，`isExternallyDirty=true`；`latest==nil` → `result=nil`，errorMessage 置「当前内容尚未建立版本基线」。
7. `DiffView`(:40-47/:74-83) `isExternallyDirty==true` 时 alert message 追加「恢复前会自动快照当前内容」，消除「恢复上一版」把未捕获改动当「上一版丢弃」的误导。
8. `performRestore`(:148-171) 改：`guard let snapshotContent else { return }; do { try FileRestore.restore(store: versionStore, path: path, snapshotContent: snapshotContent); onRestored?() } catch { restoreError = ... }`（UI 绑定留 DiffView，文件操作下沉 FileRestore）。
9. **测试缝（评审补强）**：`loadDiff` 的三态版本选择抽 `static func selectBaseline(latest:current:previous:) -> (version: …?, isExternallyDirty: Bool)`，单测三态逻辑，否则无回归保护。
10. **Blocker（评审）**：`preRecordBaselines` 用 `allItems` 而非 `items`——`items` 是搜索过滤后子集，带 `searchQuery` 进目录会漏录被过滤文件的基线。
11. 清理策略（`VersionStore.swift:94-104` 按 `createdAt ASC` 删最旧）**本切片不改**（见决策点 2）。

**测试矩阵**

| 用例 | given → expect | 文件 |
|---|---|---|
| `recordBaselinesRecordsEligibleTextFiles` | a.txt/b.json/c.png，store 空 → recorded==2 skipped==1，c.png 无快照 | VersionStoreTests |
| `recordBaselinesSkipsAlreadySnapshotted` | 先 save a.txt="old"，改盘="new"，调 recordBaselines → a.txt skipped，store 仍只有"old"（**保住真 before**） | VersionStoreTests |
| `recordBaselinesRespectsByteBudget` | 3 个各 10B，budget=15 → truncated==true，recorded<3 | VersionStoreTests |
| `fileRestoreReplacesContentAndSnapshotsCurrent` | 盘="current"、快照="snapshot" → 盘读出"snapshot"，store 新增 hash==sha256("current")，无残留临时文件 | VersionStoreTests |
| `fileRestoreThrowsForMissingFile` | path 不存在 → 抛错，无副作用、无临时文件残留 | VersionStoreTests |
| `selectBaselineExternallyDirtyUsesLatest` | latest.hash≠current → (latest, isExternallyDirty=true) | VersionStoreTests |

**手动走查**
- 进入含 `.txt/.md` 的既存目录（PathDeck 从未打开过）→ 外部编辑器改一个文件 → 回 PathDeck 看 diff：能看到真实「改动前→改动后」（预录基线生效），而非「无可用版本快照」。
- 对从未快照、当前也无更早版本的文件触发 diff → 提示「当前内容尚未建立版本基线」而非误导的可点「恢复上一版」。
- 外部脏场景点恢复 → alert 提示「恢复前会自动快照当前内容」，恢复后版本列表既有目标版本也有「恢复前」版本（可再 diff 回退）。
- 进入大目录（>16MB 文本）→ UI 不卡顿（background 线程）+ Console 出现 truncated log。

**回滚**：`git checkout` 还原 4 文件。无 schema migration、无 pbxproj 改动、无新增源文件，纯增量、零残留。

**评审已纠偏**：缺陷描述「外部脏时实际丢弃未捕获改动」**不准确**——`DiffView.swift:153-156` 写入前已先 `saveVersion` 当前态，当前态可撤销；真问题只是「恢复上一版」文案误导。本切片修文案 + 三态区分，不改可撤销机制。

---

## 8. 最脆弱假设（premise collapse）

**S20 load-bearing 假设**：归因依赖 `TerminalActivitySnapshot.cwd` 准确，而 cwd 靠 OSC 7 同步——若 shell 未装 shell-integration、或 `cd` 后 OSC 7 未及时上报，cwd 会 stale 或缺失。

**deform 设计使其在假设失效时仍安全**：纯函数把「不做虚假精确归因」固化进类型——`cwd: URL?` 用 Optional 表达未知，`attribute` 在 `cwd==nil` 或不匹配时一律返回 `nil`。**宁可不归因，绝不错归因**。这恰好兑现 PRD §R2，且 cwd stale 时最坏结果是「该归没归」而非「错归到无关 tab」——比现状（恒贴 UI 选中 tab）严格更好。

新建 tab 的兜底：`createTerminalTab` 时 `currentCwd = initialCwd = model.currentURL`（已是有效 cwd），OSC 7 上报前快照 cwd 即为该值，归因可命中——`buildSnapshots` 必须用 `currentCwd` 而非 nil。

## 9. 待 Sir 拍板的遗留语义抉择（不阻塞落地，按推荐实现，review plan 时顺带定）

**决策点 1 — 嵌套 cwd 的 tie-break**
两个 tab，A cwd=`/work`、B cwd=`/work/proj`，事件 `/work/proj/a.txt` 同时命中两者。已批 D-a 字面是「多命中取最近活跃」，可能归给父目录终端 A。但**子目录终端 B 直觉上更可能是写入者**。
- **我的推荐**：tie-break 改为「优先最深 cwd 前缀，同深度再取最近活跃」（命中集先按 cwd 路径长度降序、再按 lastActive 降序）。只是 `attribute` 内一行排序键调整，更符合直觉。
- 若 Sir 坚持字面 D-a「纯最近活跃」，去掉路径长度排序键即可。`attributeNestedCwd…` 测试断言按最终定论锁定。

**决策点 2 — baseline 是否 pin 免清理**
当前不 pin，靠默认 `maxVersionsPerFile=10`，需 >10 次写盘才可能把 baseline（per-file 第 1 版）淘汰，概率低。
- **我的推荐**：暂不 pin。pin 需加 `isPinned` 列 + migration v2 + 清理 SQL 排除 pinned，属独立切片，本计划不夹带。若实测 baseline 被淘汰再开 `D-c-pin` 切片。

## 10. 工程注意

- **新增 .swift 源文件**（`PendingTextBuffer.swift`、`TerminalAttribution.swift`）在 `PathDeck/` 子目录下，被 `PBXFileSystemSynchronizedRootGroup` **自动纳入 build，无需改 pbxproj**。`membershipExceptions` 仅用于排除同名 `AGENTS.md`/`Info.plist`，`.swift` 不冲突。测试文件同理随 `PathDeckTests` 同步纳入。
- **本 plan 文档**在 `docs/plans/` 下，`docs/` 不进 build，无需 pbxproj 改动。
- 每块落地后更新对应子目录 `AGENTS.md` 变更日志（`Terminal/`、`ChangeJournal/`、`FileWorkspace/`）+ 根 `AGENTS.md` 变更日志。

## 11. 验证命令

```bash
# 每块合并后跑全量单测（跳过会拉起 GUI 的 UITests），确认 ~149→更多 全绿再进下一块
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -only-testing:PathDeckTests test
# 涉及 synchronized group 资源/新文件时用 clean build 暴露同名冲突
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug clean build
```

不自动启动 GUI app（Sir 自行在 Xcode 跑手动走查）。自动验证限 build + 单测。

---

## 附：对抗性评审最终结论

> 三块方向均正确、根因定位经代码核对全部属实（S19 的 deinit 非缺陷、S21 的 performRestore 不丢数据等自我纠偏诚实）。均**非 ready-to-implement 的唯一原因**是每块各有一项落地 blocker + 核心修复缺自动化测试缝——已全部吸收进本 plan（S19：private→internal + `exitedSessionIDs` 纯函数；S20：补全 `ChangeStoreTests` 11 处 + `mergeSnapshot` 测试缝；S21：`allItems` 不用 `items` + `selectBaseline` 纯函数）。**无方向级返工。**
</content>
</invoke>
