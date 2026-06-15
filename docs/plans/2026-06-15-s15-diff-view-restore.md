# S15：Diff View + Restore Previous Version

> Sprint：S15  
> 里程碑：M4（透明版本与恢复）  
> 前置：S14 VersionStore 已落地（versions.db，content blob 存储，hash 去重，per-file 10 版本上限）  
> PRD 对应：FR-CHANGE-005（Diff / Before After）、FR-CHANGE-006（恢复上一版）

---

## 目标

用户在 Recent Changes 面板中，对有版本快照的文件可以：查看修改前后差异（inline diff）→ 恢复到上一版。闭合 M4 的核心用户面功能。

## 不做

- Side-by-side diff（P1 验收标准提及，但 MVP 先只做 inline diff；side-by-side 作为后续增强，inline diff 的数据层完全复用）
- 从 Preview Pane 打开版本比较（当前无独立 Preview Pane，待 M5 多视图模式后再补）
- Settings 窗口 / 隐私设置（S16 范围）
- 版本列表浏览（仅做"比较上一版"单入口，不做完整版本历史列表选择）

---

## 方案

### 1. VersionStore 扩展：读取 content

当前 `VersionStore.versions(for:)` 和 `latestVersion(for:)` 只返回 metadata（`FileVersion` 不含 `content`）。diff 和 restore 需要读取 blob 内容。

**改动**：

- 新增 `VersionStore.versionContent(id:) -> Data?`：按 id 读取单条 content blob。
- 新增 `VersionStore.latestVersionWithContent(for:) -> (FileVersion, Data)?`：读最新版本及其 content（restore 场景用，一次查询完成）。
- `FileVersion` 保持不含 content——避免列表查询时加载大量 blob。

**文件**：`PathDeck/ChangeJournal/VersionStore.swift`

### 2. DiffEngine：纯 Swift 文本 diff

inline diff 需要逐行比较两段文本，产出 `[DiffLine]`（added / deleted / unchanged）。

**方案选型**：

- ~~第三方 diff 库~~：无必要引入新依赖，逐行 LCS diff 复杂度低
- **自实现**：Myers diff 算法（O((N+M)D) 时间，D = 差异行数）。产出类型：

```swift
enum DiffLineType { case added, deleted, unchanged }
struct DiffLine: Identifiable {
    let id: Int  // 全局序号
    let type: DiffLineType
    let text: String
    let oldLineNumber: Int?  // 旧文件行号（deleted/unchanged 有值）
    let newLineNumber: Int?  // 新文件行号（added/unchanged 有值）
}

enum DiffEngine {
    static func diff(old: String, new: String) -> [DiffLine]
}
```

**文件**：`PathDeck/ChangeJournal/DiffEngine.swift`（新增）

### 3. DiffView：inline diff 展示

SwiftUI 视图，在底部面板区域内展示 diff 结果。入口：从 ChangeListView 的版本快照行点击打开。

**交互流程**：

```
ChangeListView 中点击有快照的行
  → 读当前文件内容 + VersionStore 最新快照内容
  → DiffEngine.diff(old: snapshot, new: current)
  → 切换底部 changes 面板为 DiffView
  → 顶部显示文件名 + "比较上一版" 标题 + 关闭按钮 + 恢复按钮
  → 下方 ScrollView 展示 inline diff（行号 + 增删色标 + 代码文本）
```

**视觉规格**（依据 design.md）：

- added 行：`systemGreen` tint 底 `rgba(48,209,88,0.13)`
- deleted 行：`systemRed` tint 底（`rgba(255,69,58,0.13)`）
- unchanged 行：无底色
- 行号：monospaced，secondary 色
- 代码文本：`.system(size: 12, design: .monospaced)`
- 行高：固定 20pt

**组件结构**：

```
DiffView
├── DiffHeaderBar（文件名 + 关闭按钮 + "恢复上一版" 按钮）
└── ScrollView
    └── LazyVStack
        └── DiffLineRow × N
```

**文件**：`PathDeck/ChangeJournal/DiffView.swift`（新增）

### 4. Restore：恢复上一版

从 DiffView 头部的"恢复上一版"按钮触发。

**流程**：

1. 弹出确认 Alert："将 {filename} 恢复到 {timestamp} 的版本？"
2. 确认后：
   a. 读取快照 content（已在 DiffView 上下文中持有）
   b. 将当前文件内容作为新快照保存（恢复前自动快照，确保可撤销）
   c. 将快照 content 写入文件路径（`Data.write(to:)`）
   d. 写入成功后，恢复操作本身作为一条 `modified` 事件进入 Change Journal
   e. 刷新 UI

**关键约束**（来自 PRD FR-CHANGE-006 验收标准）：

- 恢复前展示确认 ✓
- 恢复操作本身也进入 Change Journal ✓（FSEvents 自然会捕获写入，但主动 record 一条确保时序准确）
- 恢复后可再次撤销到恢复前版本 ✓（步骤 2b 保证）
- 删除文件若无快照，只展示删除记录，不承诺恢复 ✓（入口不展示）

**文件**：restore 逻辑直接写在 `DiffView.swift` 内（视图局部 action，不需独立模块）

### 5. ContentView / ChangeListView 集成

**ChangeListView 改动**：

- 有版本快照的行（`hasVersion == true`）新增点击行为：触发 `onDiff` 回调（替代当前的 `onNavigate` 仅导航）
- 区分两种点击：单击行仍导航到文件；点击版本快照图标（`doc.on.doc`）打开 diff

**ContentView 改动**：

- 底部面板新增第三态：`BottomPanelTab` 加 `.diff(path: String)` case
- 当 `activeBottomTab == .diff` 时显示 `DiffView`，传入 path + versionStore 引用
- DiffView 关闭时回到 `.changes` tab

**WorkspaceModel 改动**：无。DiffView 直接接收 `VersionStore` 引用和文件路径，自行读取数据。

---

## 文件清单

| 文件 | 动作 | 改动摘要 |
|---|---|---|
| `PathDeck/ChangeJournal/VersionStore.swift` | 修改 | +`versionContent(id:)` +`latestVersionWithContent(for:)` |
| `PathDeck/ChangeJournal/DiffEngine.swift` | **新增** | Myers diff 算法，`DiffLine` 类型 |
| `PathDeck/ChangeJournal/DiffView.swift` | **新增** | Inline diff 视图 + restore 确认 + 恢复逻辑 |
| `PathDeck/ChangeJournal/ChangeListView.swift` | 修改 | 版本快照图标可点击 → `onDiff` 回调 |
| `PathDeck/ContentView.swift` | 修改 | `BottomPanelTab.diff` + DiffView 集成 + BottomPanelBar diff tab 展示 |
| `PathDeckTests/DiffEngineTests.swift` | **新增** | diff 算法单测 |
| `PathDeckTests/VersionStoreTests.swift` | 修改 | +content 读取测试 |

共 7 个文件（3 新增 4 修改），约 400-500 行新增代码。

---

## 测试计划

### 单元测试（必须）

**DiffEngineTests**（新增，≥ 8 case）：
- 两段相同文本 → 全 unchanged
- 空文本 vs 非空 → 全 added 或全 deleted
- 单行修改 → 1 deleted + 1 added
- 多行新增/删除/混合
- 行号正确性验证
- 大文本性能（1000+ 行不超时）

**VersionStoreTests**（扩展，+3 case）：
- `versionContent(id:)` 返回正确 blob
- `latestVersionWithContent(for:)` 返回最新版本及内容
- 不存在的 id 返回 nil

### 手动验证（视觉/交互，无法单测）

1. 打开工作区 → 修改一个文本文件 → 底部 Changes 面板出现该文件 + 版本快照图标
2. 点击版本快照图标 → 底部面板切换为 DiffView → 显示 inline diff（绿色 added / 红色 deleted）
3. 点击"恢复上一版" → 确认弹窗 → 确认 → 文件内容恢复 → Changes 面板新增一条 modified 记录
4. 再次点击版本快照图标 → DiffView 显示"恢复前版本"（即刚才的修改）可再次恢复（验证可撤销）
5. 对无快照的文件 → 不显示版本快照图标 → 无 diff 入口

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| 大文件 diff 卡顿 | VersionStore 已限 ≤1MB 文本，Myers diff 在 1MB 文本下可控 | 超 5000 行截断显示 + 提示 |
| 恢复写入失败（权限/磁盘满） | 文件损坏 | 先写临时文件 → rename 原子替换；失败 Alert 不删临时文件 |
| `BottomPanelTab.diff` 引入 associated value 影响现有 `Hashable` | 编译错误 | `BottomPanelTab` 已 `Hashable`，associated value 的 `String` 也 `Hashable`，无问题 |

---

## Xcode 工程注意事项

新增 `DiffEngine.swift` 和 `DiffView.swift` 在 `PathDeck/ChangeJournal/` 下。该目录是 synchronized group，新 `.swift` 文件自动纳入 build。但需在 `PBXFileSystemSynchronizedBuildFileExceptionSet` 中确认无冲突——当前排除列表只含 `AGENTS.md`，`.swift` 不受影响，无需额外操作。

新增 `DiffEngineTests.swift` 在 `PathDeckTests/` 下，同理自动纳入 test target。
