# S14：Terminal Activity Attribution + Lightweight File Version Snapshots

> 日期：2026-06-15　需求：terminal-attribution-file-versions
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-15-s13-window-layout-skeleton.md`。

## 背景定位

S13 完成窗口布局骨架后，M3（Recent Changes MVP）仅缺 PRD FR-CHANGE-003 终端活跃期间变化归因。M4（透明版本与恢复）尚未开始，其基础是 PRD FR-CHANGE-004 轻量文件版本快照。

S14 合并两个目标：

1. **Part A — 终端活跃期间变化归因**：闭合 M3 里程碑
2. **Part B — 轻量文件版本快照**：M4 地基（仅存储引擎 + 快照触发，不含 diff UI / restore）

## 目标

| 目标 | PRD 关联 | 里程碑 |
|------|----------|--------|
| 文件变化弱关联到活跃终端会话 | FR-CHANGE-003 | 闭合 M3 |
| 文本类文件修改时自动保存轻量版本 | FR-CHANGE-004 | M4 基础 |

## 验证标准（7 个验证点）

### V1：终端归因写入与读取

单元测试：

1. `ChangeStore` v2 migration：写入带 `terminalSessionID` 的事件，读回验证 UUID 正确
2. `ChangeStore` v2 migration：写入无 session ID 的事件，读回验证 nil
3. 向后兼容：v1 存量事件在 v2 schema 下读回 `terminalSessionID` 为 nil

### V2：终端归因 UI

手动验证：

1. 打开终端，`touch foo.txt` → 切到「变化」tab → 该事件行显示终端图标标记
2. 关闭所有终端 tab → 在 Finder 中创建文件 → 「变化」tab 无终端图标
3. 终端运行长命令期间切到「变化」tab 观察 → 新增的变化仍有终端归因（归因不依赖终端 tab 是否是当前活跃 tab）

### V3：版本快照存储

单元测试：

1. `VersionStore`：保存版本 → 读取最新版本 → content 和 hash 正确
2. `VersionStore`：同一 path 保存 12 个版本 → 自动清理至 10 个，最旧的被删除
3. `VersionStore`：连续两次保存相同内容 → 第二次被 hash 去重跳过，版本数不增加
4. `VersionStore`：`pathsWithVersions(in:)` 返回正确路径集合
5. `VersionPolicy`：文本文件 eligible、二进制文件 not eligible、超大文件 not eligible

### V4：版本快照触发

手动验证：

1. 打开含文本文件的目录 → 在外部编辑器修改文件 → 变化面板该条目显示快照标记（📎 小图标）
2. 修改一个 >1MB 的文件 → 无快照标记
3. 修改一个二进制文件（图片）→ 无快照标记
4. 检查 `~/Library/Application Support/in.riverflows.PathDeck/versions.db` 存在且有数据

### V5：回归

全量单测通过（现有 82 + 新增 ≥8 个）。

## 最脆弱假设

**`handleFSEvents` 中对 <1MB 文本文件的同步读取不阻塞 UI。**

`handleFSEvents` 在主线程执行。对每个 `modified`/`added` 事件读取文件内容（<1MB 文本）并计算 SHA256 约需 1-3ms。FSWatcher 有 0.3s coalescing + same-path 去重 + 1s 节流（`recentEventKeys`），单次回调通常 <10 个事件。极端情况（`npm install` 写入大量文本文件到当前目录）可能短暂卡顿。

退路：若实测发现延迟 >50ms，将文件读取 + hash + 写入 VersionStore 移到后台 DispatchQueue，仅保留路径收集在主线程。

## 技术方案

### Part A：终端活跃期间变化归因

#### A1：ChangeEvent 新增字段

`ChangeEvent.swift`：

```swift
struct ChangeEvent: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let fileName: String
    let eventType: ChangeEventType
    let timestamp: Date
    let directory: String
    let terminalSessionID: UUID?    // 新增
}
```

#### A2：ChangeStore schema migration v2

`ChangeStore.swift`，在现有 `migrator.registerMigration("v1")` 之后新增：

```swift
migrator.registerMigration("v2") { db in
    try db.execute(sql: "ALTER TABLE change_events ADD COLUMN terminalSessionID TEXT")
}
```

#### A3：ChangeStore.recordBatch 扩展

```swift
func recordBatch(
    _ events: [(path: String, type: ChangeEventType, directory: String)],
    terminalSessionID: UUID? = nil
) throws {
    // INSERT 语句加 terminalSessionID 列
    // 值为 terminalSessionID?.uuidString
}
```

默认参数保持向后兼容，现有调用无需改动。

#### A4：ChangeStore.recentEvents 读取新列

```swift
let sessionStr: String? = row["terminalSessionID"]
let sessionID = sessionStr.flatMap { UUID(uuidString: $0) }
return ChangeEvent(
    ..., terminalSessionID: sessionID
)
```

#### A5：WorkspaceModel 接收终端上下文

`WorkspaceModel.swift` 新增属性：

```swift
var activeTerminalSessionID: UUID?
```

`handleFSEvents` 中传递给 `recordBatch`：

```swift
try? changeStore?.recordBatch(batch, terminalSessionID: activeTerminalSessionID)
```

#### A6：ContentView 同步终端状态

`ContentView.swift`，在 `workspaceContent` 末尾或 `.onChange` 中同步：

```swift
.onChange(of: activeTerminalID) { _, newID in
    model.activeTerminalSessionID = newID
}
.onChange(of: terminalSessions.count) { _, count in
    if count == 0 { model.activeTerminalSessionID = nil }
}
```

归因策略：只要存在活跃终端 session（`activeTerminalID != nil`），所有文件变化均归因到该 session。不要求终端 tab 是当前活跃 tab——终端运行长命令时用户可能正在看变化列表。

#### A7：ChangeListView 终端归因标记

`ChangeRow` 中，在时间戳左侧加终端图标：

```swift
if event.terminalSessionID != nil {
    Image(systemName: "terminal")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
}
```

文案不做精确归因（不说"由 Terminal 1 产生"），只标记"终端活跃期间"。hover tooltip：「终端活跃期间产生」。

### Part B：轻量文件版本快照

#### B1：VersionStore 新文件

新增 `PathDeck/ChangeJournal/VersionStore.swift`。

使用独立 SQLite 数据库 `versions.db`（与 `changes.db` 分离——版本含大 blob，分库便于独立清理/备份）。

Schema：

```sql
CREATE TABLE file_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL,
    directory TEXT NOT NULL,
    content BLOB NOT NULL,
    contentHash TEXT NOT NULL,
    size INTEGER NOT NULL,
    createdAt DATETIME NOT NULL
);
CREATE INDEX idx_versions_path ON file_versions(path, createdAt DESC);
CREATE INDEX idx_versions_directory ON file_versions(directory);
```

核心方法：

```swift
final class VersionStore {
    static let maxVersionsPerFile = 10
    static let maxFileSize = 1_048_576  // 1MB

    init(databasePath: String) throws { ... }
    convenience init() throws { ... }  // ~/Library/Application Support/.../versions.db

    /// 保存版本。hash 去重：若最新版本 hash 相同则跳过。超出 maxVersionsPerFile 自动清理最旧的。
    func saveVersion(path: String, directory: String, content: Data, hash: String) throws { ... }

    /// 查询某文件的版本列表（不含 content blob，仅元数据）
    func versions(for path: String, limit: Int = 10) throws -> [FileVersion] { ... }

    /// 查询某文件最新版本元数据（不含 content blob）
    func latestVersion(for path: String) throws -> FileVersion? { ... }

    /// 查询某目录下有快照的路径集合
    func pathsWithVersions(in directory: String) throws -> [String] { ... }
}
```

`FileVersion` 值类型（同文件内 private 提升为 internal）：

```swift
struct FileVersion: Identifiable, Sendable {
    let id: Int64
    let path: String
    let directory: String
    let contentHash: String
    let size: Int
    let createdAt: Date
}
```

#### B2：VersionPolicy 判定

`VersionStore.swift` 内 static 方法，不单独建文件：

```swift
extension VersionStore {
    static func isEligible(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]),
              let contentType = values.contentType,
              let fileSize = values.fileSize else { return false }
        return contentType.conforms(to: .text) && fileSize <= maxFileSize
    }
}
```

`UTType.text` 覆盖纯文本、源代码、JSON、YAML、XML、HTML、CSS、Markdown、CSV 等 PRD 列出的所有类型。不需要维护显式类型列表。

#### B3：SHA256 哈希

`VersionStore.swift` 内 private extension：

```swift
import CryptoKit

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
```

#### B4：WorkspaceModel 集成版本快照

`WorkspaceModel.swift` 新增：

```swift
private var versionStore: VersionStore?
private(set) var versionedPaths: Set<String> = []
```

`init` 中初始化：

```swift
do {
    versionStore = try VersionStore()
} catch {
    NSLog("[PathDeck] VersionStore init failed: \(error)")
}
```

`handleFSEvents` 中，对 accepted 事件触发快照（在 `recordBatch` 之后）：

```swift
for event in accepted where event.type == .added || event.type == .modified {
    snapshotIfEligible(path: event.path)
}
```

快照方法：

```swift
private func snapshotIfEligible(path: String) {
    let url = URL(fileURLWithPath: path)
    guard VersionStore.isEligible(url: url),
          let content = try? Data(contentsOf: url) else { return }
    let hash = content.sha256Hex
    try? versionStore?.saveVersion(
        path: path,
        directory: currentURL.path(percentEncoded: false),
        content: content,
        hash: hash
    )
}
```

`refreshChanges` 末尾追加：

```swift
versionedPaths = Set((try? versionStore?.pathsWithVersions(in: dir)) ?? [])
```

#### B5：ChangeListView 版本标记

`ChangeListView` 新增 `versionedPaths: Set<String>` 参数。

`ChangeRow` 中，在终端图标右侧、时间戳左侧：

```swift
if versionedPaths.contains(event.path) {
    Image(systemName: "doc.on.doc")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .help("已保存版本快照")
}
```

`ContentView` 调用处传入 `model.versionedPaths`。

#### B6：saveVersion 内部逻辑

```
1. SELECT contentHash FROM file_versions WHERE path = ? ORDER BY createdAt DESC LIMIT 1
2. if latestHash == hash → return (去重)
3. INSERT INTO file_versions (...) VALUES (...)
4. SELECT count(*) FROM file_versions WHERE path = ?
5. if count > maxVersionsPerFile →
   DELETE FROM file_versions WHERE id IN (
     SELECT id FROM file_versions WHERE path = ? ORDER BY createdAt ASC LIMIT (count - max)
   )
```

步骤 1-5 在同一个 `dbQueue.write` 事务中执行。

## 改动文件清单

| 文件 | 改动 |
|------|------|
| `PathDeck/ChangeJournal/ChangeEvent.swift` | 新增 `terminalSessionID: UUID?` 字段 |
| `PathDeck/ChangeJournal/ChangeStore.swift` | v2 migration 加列 + `recordBatch` 加参数 + `recentEvents` 读新列 |
| `PathDeck/ChangeJournal/ChangeListView.swift` | `ChangeRow` 加终端归因图标 + 版本快照图标；新增 `versionedPaths` 参数 |
| `PathDeck/ChangeJournal/VersionStore.swift` | **新增**：版本存储引擎 + FileVersion 值类型 + VersionPolicy + SHA256 |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 新增 `activeTerminalSessionID` + `versionStore` + `versionedPaths` + `snapshotIfEligible` |
| `PathDeck/ContentView.swift` | 终端 session ID 同步到 model + ChangeListView 传入 versionedPaths |
| `PathDeckTests/ChangeStoreTests.swift` | v2 migration 测试（3 个 case） |
| `PathDeckTests/VersionStoreTests.swift` | **新增**：版本存储测试（5 个 case） |

## 不改动

| 文件 | 理由 |
|------|------|
| `Terminal/*` | 终端模块不变，仅由 ContentView 读取 session ID |
| `ChangeJournal/FSWatcher.swift` | 事件分类不变，归因在上层 WorkspaceModel 处理 |
| `ChangeJournal/IgnoreRules.swift` | 忽略规则不变 |
| `SidebarView.swift` | 不涉及 |
| `PathDeckApp.swift` | 不涉及 |

## Non-scope

| 排除项 | 原因 |
|--------|------|
| Diff UI（inline / side-by-side） | S16 单独切片，依赖本切片的版本存储 |
| Restore Previous Version | S17 单独切片 |
| 版本总量上限 / 磁盘配额 / 自动清理策略 | M4 设置面板（FR-SETTINGS-002）|
| 敏感目录排除（~/.ssh 等） | M4 隐私设置（FR-SETTINGS-003）|
| 版本内容下载 / 读取 API | Diff UI 需要时再加 `fetchContent(versionID:)` |
| 终端精确命令归因 | PRD 明确不做（NG4），仅弱关联到活跃 session |
| 终端 cwd 与工作区匹配检查 | 当前 FSWatcher 仅监听 currentURL 一级目录，天然限定范围 |
| 新增 AGENTS.md 到 xcodeproj membershipExceptions | 本切片无新 .md 文件需排除 |

## 实现顺序

1. `ChangeEvent.swift` — 新增 `terminalSessionID` 字段
2. `ChangeStore.swift` — v2 migration + recordBatch 扩展 + recentEvents 读取
3. `WorkspaceModel.swift` — 新增 `activeTerminalSessionID` 属性 + 传递给 recordBatch
4. `ContentView.swift` — 同步 activeTerminalID → model.activeTerminalSessionID
5. `ChangeListView.swift` — 终端归因图标
6. `PathDeckTests/ChangeStoreTests.swift` — 归因相关测试（3 case）
7. Build + 全量单测 → **Part A 完成，M3 闭合**
8. `VersionStore.swift` — 新增版本存储引擎
9. `PathDeckTests/VersionStoreTests.swift` — 版本存储测试（5 case）
10. `WorkspaceModel.swift` — 集成 versionStore + snapshotIfEligible + versionedPaths
11. `ChangeListView.swift` — 版本快照图标 + versionedPaths 参数
12. `ContentView.swift` — ChangeListView 传入 model.versionedPaths
13. Build + 全量单测 → **Part B 完成，M4 基础落地**
14. 更新 `ChangeJournal/AGENTS.md` 变更日志
15. 更新根 `AGENTS.md` 变更日志
16. GUI 走查（V2 + V4 手动验证项）

## 工作量

1 个新源文件 + 5 个改动源文件 + 1 个新测试文件 + 1 个改动测试文件。~200 行新代码（VersionStore ~120 + 测试 ~80）+ ~60 行改动代码（ChangeStore/ChangeEvent/WorkspaceModel/ContentView/ChangeListView）。
