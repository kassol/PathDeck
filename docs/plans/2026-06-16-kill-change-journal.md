# Dogfood D1：Kill Change Journal

> 状态：Done
> 前置：M5 闭合（S22），进入 dogfood 期
> 目标：移除 Change Journal 全栈（UI + SQLite 存储 + 版本快照 + 终端归因 + Diff），保留 FSWatcher 做文件列表实时刷新

## 背景

M0–M5 全部闭合，进入 dogfood 期。实际使用中 Change Journal（变化列表 + 版本快照 + Diff + Restore）体感鸡肋——有 git repo 的目录以 git 为真相源更自然，没有 git 的目录不需要这套重型机制。

保留的核心能力：**当前目录文件变化感知**。外部进程（Terminal、Finder、AI agent）修改文件时，文件列表必须自动刷新。FSWatcher 是唯一的外部变化检测机制，必须保留并简化。

## Scope

- 删除 `ChangeJournal/` 全部 10 个源文件（含 AGENTS.md）
- 删除 `Settings/ChangesSettingsTab.swift`
- 删除 8 个纯 CJ 测试文件
- 新建 `FileWorkspace/FSWatcher.swift`（简化版，~80 行）
- 编辑 6 个文件剥离 CJ 引用
- 移除 GRDB 包依赖（仅 ChangeStore/VersionStore 使用）
- 更新 Xcode 项目文件（membershipExceptions、包引用）
- 更新根 AGENTS.md

## Non-scope

- Git 状态集成（下一阶段独立课题）
- 文件列表刷新时的选择状态保持优化（已知行为，独立课题）
- 任何新功能

## 设计

### FSWatcher 简化

当前 FSWatcher 的 handler 签名：

```swift
// Before — 携带事件类型、归属目录、终端快照
([(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])]) -> Void
```

简化为纯信号：

```swift
// After — 只通知"有变化，请 reload"
@Sendable () -> Void
```

保留：
- FSEventStream 创建/启动/停止/释放生命周期
- 0.5s coalesce 去抖（`scheduleFlush`）
- `stop()` 时 flush 语义（导航切换不丢最后一批事件的 reload 信号）
- 父目录过滤（`parent == watchedDir`）——只响应当前目录一级变化，避免深层子目录变化触发无效 reload
- `watch(directory:)` 切换监听目录

删除：
- `ChangeEventType` 分类（`classify`/`mergeType`）
- `TerminalActivitySnapshot` / `snapshotProvider`
- per-file pending 字典（简化为 bool 脏标记）

### WorkspaceModel 剥离

删除属性（~10 个）：

| 属性 | 说明 |
|---|---|
| `changes: [ChangeEvent]` | 变化列表数据 |
| `changeIndicators: [String: ChangeEventType]` | 文件行变化指示器 |
| `versionedPaths: Set<String>` | 有版本快照的路径集合 |
| `changeStore: ChangeStore?` | SQLite 事件存储 |
| `versionStore: VersionStore?` | SQLite 版本存储 |
| `indicatorTimers: [String: Timer]` | 指示器自动消失计时器 |
| `terminalSnapshots` + `snapshotsLock` | 终端归因快照 |
| `isPreRecordingBaselines` | 基线预录去重标志 |
| `hiddenCount: Int` | 被忽略规则隐藏的变化数 |

删除方法（~7 个）：
- `refreshChanges()` / `handleFSEvents()` / `snapshotIfEligible()` / `preRecordBaselines()`
- `updateTerminalSnapshots()` / `readTerminalSnapshots()` / `clearExpiredIndicators()`

FSWatcher init 简化：

```swift
// Before
watcher = FSWatcher(
    snapshotProvider: { [weak self] in self?.readTerminalSnapshots() ?? [] }
) { [weak self] events in
    DispatchQueue.main.async { self?.handleFSEvents(events) }
}

// After
watcher = FSWatcher { [weak self] in
    DispatchQueue.main.async { self?.reload() }
}
```

`navigate()` 中的 `clearExpiredIndicators()` 调用一并删除。

### ContentView 简化

`BottomPanelTab` 枚举从三个 case 缩减：

```swift
// Before
enum BottomPanelTab: Hashable {
    case terminal
    case changes
    case diff(path: String)
}

// After — 底部面板 = Terminal，枚举移除
// activeBottomTab 状态变量移除
// 面板可见性仅由 isBottomPanelVisible 控制
```

删除：
- `ChangeListView` / `DiffView` 渲染分支
- `buildSnapshots()` / `updateTerminalSnapshots()` 调用（3 处）
- `BottomPanelBar` 中的"变化"按钮 + 角标 + diff 指示器
- 状态恢复中 `activeBottomTab` 的 save/restore 分支

`BottomPanelBar` 简化为始终显示 `TerminalTabBar`，不再做 tab 切换。

### FileTableView / PreviewPane

- `FileTableView`：删除 `changeIndicators` 参数及圆点指示器渲染（~3 处引用）
- `PreviewPane`：删除 `versionedPaths` / `onDiff` / 版本 section（~5 处引用）

### Settings

- 删除 `ChangesSettingsTab.swift` 整文件
- `SettingsView.swift` 删除 Changes tab（TabView 只剩 Terminal）

### 测试

**整删 8 文件**：
`ChangeStoreTests` · `ChangeTimeGroupTests` · `DiffEngineTests` · `FSWatcherClassifyTests` · `IgnoreRulesTests` · `TerminalAttributionTests` · `VersionStoreTests` · `FSWatcherTests`

**编辑 1 文件**：
`SettingsDefaultsTests.swift` — 删除 3 个 VersionStore 相关断言

**新建 1 文件**：
`FSWatcherTests.swift` — 测试简化后的 watch/coalesce/signal 行为

### Xcode 项目

- 移除 GRDB `XCRemoteSwiftPackageReference` + `productRef`（4 处 pbxproj 引用）
- 移除 `ChangeJournal/AGENTS.md` 的 `membershipExceptions` 条目

### 文档

- 根 `AGENTS.md`：四大支柱改为三大（删 Change Journal）、目录索引移除 `ChangeJournal/`、变更日志追加本次
- `docs/prd.md`：不改（PRD 是产品定义，保留历史记录；M3/M4 标注为 killed 由后续文档同步处理）

## 文件清单（25 文件）

### 删除（19 文件）

```
PathDeck/ChangeJournal/AGENTS.md
PathDeck/ChangeJournal/ChangeEvent.swift
PathDeck/ChangeJournal/ChangeStore.swift
PathDeck/ChangeJournal/VersionStore.swift
PathDeck/ChangeJournal/DiffEngine.swift
PathDeck/ChangeJournal/DiffView.swift
PathDeck/ChangeJournal/ChangeListView.swift
PathDeck/ChangeJournal/IgnoreRules.swift
PathDeck/ChangeJournal/TerminalAttribution.swift
PathDeck/ChangeJournal/FSWatcher.swift
PathDeck/Settings/ChangesSettingsTab.swift
PathDeckTests/ChangeStoreTests.swift
PathDeckTests/ChangeTimeGroupTests.swift
PathDeckTests/DiffEngineTests.swift
PathDeckTests/FSWatcherClassifyTests.swift
PathDeckTests/FSWatcherTests.swift
PathDeckTests/IgnoreRulesTests.swift
PathDeckTests/TerminalAttributionTests.swift
PathDeckTests/VersionStoreTests.swift
```

### 新建（1 文件）

```
PathDeck/FileWorkspace/FSWatcher.swift
```

### 编辑（6 文件）

```
PathDeck/FileWorkspace/WorkspaceModel.swift
PathDeck/ContentView.swift
PathDeck/FileWorkspace/FileTableView.swift
PathDeck/FileWorkspace/PreviewPane.swift
PathDeck/Settings/SettingsView.swift
PathDeckTests/SettingsDefaultsTests.swift
```

### 项目/文档（2 文件）

```
PathDeck.xcodeproj/project.pbxproj
AGENTS.md
```

## 验证

```bash
# 编译
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build

# 单测（预计从 203 降至 ~150）
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck \
  -only-testing:PathDeckTests -destination 'platform=macOS,arch=arm64' test
```

手动验证：
1. 打开任意目录 → 在外部 Terminal 执行 `touch newfile.txt` → 文件列表应在 ~1s 内出现 newfile.txt
2. 导航到其他目录 → 旧目录变化不触发刷新
3. Settings 窗口只剩 Terminal tab
4. 底部面板只有 Terminal，无"变化"按钮

## 风险

| 风险 | 缓解 |
|---|---|
| FSWatcher 简化时遗漏父目录过滤 → 深层变化频繁触发无效 reload | 新 FSWatcher 保留 `parent == watchedDir` 守卫 |
| pbxproj 手动编辑 GRDB 引用出错 → build 失败 | 编辑后立即 `xcodebuild build` 验证 |
| 遗漏某个 CJ 类型引用 → 编译失败 | 删除前 grep 全量确认，编辑后立即编译 |

## 未来方向（不在本次 scope）

Git 状态集成：有 `.git` 的目录以 `git status` 为真相源，文件列表标注 modified/untracked/staged 状态。没有 `.git` 的目录不做任何变化标注。这是一个独立的功能切片，不依赖本次移除的任何代码。
