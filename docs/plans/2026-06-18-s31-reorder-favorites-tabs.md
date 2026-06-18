# S31 Reorder — Favorites / 文件 Tab / Terminal Tab 手动拖动排序

> 日期：2026-06-18
> 前置：S30 已合入（Sidebar 单一 Favorites section + seed 默认五项）
> 触发：Sidebar Favorites、文件 Tab Bar、Terminal Tab Bar 三处当前均为只增不可重排，影响日常工作台手感

## 目标

为三个独立列表加上手动拖拽重排序：

1. Sidebar **Favorites** 区块（含 seed 默认五项 + 用户 pinned）
2. **文件 Tab Bar**（横向，`FileTabBar`）
3. **Terminal Tab Bar**（横向 `TerminalTabBar` + 纵向 `VerticalTerminalTabBar` 两套视图，同一数据源）

无新业务能力，是一次交互完整性收敛。三处使用统一的 SwiftUI 原生 reorder API，每域独立 payload 类型，互不混淆。

## 当前实现锚点

| 域 | 数据源 | 视图 | 持久化通道 |
|---|---|---|---|
| Favorites | `PinnedFolders.items: [URL]` + 同序 `bookmarks: [Data]` | `SidebarView` `List` + `Section("Favorites")` + `ForEach` | `PinnedFolders.persist()` |
| 文件 Tab | `TabManager.fileTabs: [FileTab]` | `FileTabBar` `ScrollView(.horizontal)` + `HStack` + `ForEach` | `TabManager.saveTabState()` |
| Terminal Tab | `FileTab.terminalSessionIDs: [UUID]`（per-tab，归属活动文件 Tab） | `TerminalTabBar`（`HStack`）+ `VerticalTerminalTabBar`（`VStack`），通过 `tabManager.activeTabSessions` 提供 | `TabManager.saveTabState()` |

三处持久化基础已就位，缺的仅是 reorder 动作 + 视觉反馈。

## 技术路线（最佳实践）

| # | 决策 | 行为 |
|---|------|------|
| D1 | Pinned 用 SwiftUI `List.onMove(perform:)` | macOS `List` 上 `.onMove` 是原生 reorder 形态，零代码拿到 Finder 一致的插入指示器 + 自动动画 + accessibility |
| D2 | Tab Bar（横/纵 3 套）统一用 `.draggable` + `.dropDestination(for:)` | macOS 26.5（D3）远超 macOS 14 引入版本；`HStack` 容器没有 `List` 的原生 reorder，但 `.draggable` / `.dropDestination` 是同一代 API、风格一致 |
| D3 | 三个域各自定义独立 `Transferable` 类型 | `PinnedItemDragID` / `FileTabDragID` / `TerminalSessionDragID`，靠类型系统阻断跨域 drop |
| D4 | 拖拽视觉反馈：拖起 source 半透明 0.4，hover 目标位置画 2pt accent 插入指示线（横向竖线 / 纵向横线），drop 后 ForEach 自然过渡 | 不撞 active tab 下边 2pt accent underline；与 Safari / iTerm reorder 视觉对齐 |
| D5 | 单 tab 禁用拖拽（`.draggable` 条件挂载） | 单 tab 无可重排目标，避免误触；与现有"单 tab 关闭按钮隐藏"一致 |
| D6 | reorder 不重建 `WorkspaceModel` / `TerminalSession` 实例 | 只重排引用，active ID / anchor cwd / 终端 PTY 全保留；持久化复用现有 `persist()` / `saveTabState()` |

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P0 | Spike | 验证 `List.onMove` 与现有外部 `.onDrop(of: [UTType.fileURL])` 在 Pinned 上共存（D1 是否撞 fileURL drop） | `PathDeck/SidebarView.swift` |
| P1 | Feat | `PinnedFolders.move(from:to:)` + `SidebarView` 挂 `.onMove` | `PathDeck/SidebarView.swift` |
| P2 | Feat | `TabManager.moveFileTab(source:to:)` + `FileTabBar` 接入 drag/drop + 插入指示线 | `PathDeck/TabManager.swift`, `PathDeck/FileTabBar.swift` |
| P3 | Feat | `TabManager.moveTerminalSession(in:source:to:)` + 横/纵两套 Terminal Tab Bar 接入 drag/drop | `PathDeck/TabManager.swift`, `PathDeck/Terminal/TerminalTabBar.swift`, `PathDeck/Terminal/VerticalTerminalTabBar.swift` |
| P4 | Test | reorder 三域单测（顺序 / 持久化 / active ID 保留 / invalid input） | `PathDeckTests/PinnedFoldersReorderTests.swift`（新增）、`PathDeckTests/TabManagerTests.swift`（追加） |
| P5 | Docs | AGENTS.md 三处描述同步 | `AGENTS.md` |

## Not Building

- **跨域拖拽** — Pinned ↔ 文件 Tab、文件 Tab ↔ Terminal Tab 互拖一律 reject
- **拖出窗口 detach 新窗口** — 非本需求
- **拖拽手柄 UI（drag handle icon）** — macOS 原生 reorder 一律按住条目本身拖
- **多选 reorder** — Pinned `List(selection:)` 当前是单选 navigate 语义，多选 reorder 需要先重设 selection 语义；非本需求
- **Tab Bar 横滚到末尾自动追加** — drop 到末尾视为追加到当前可见区末，不做自动滚动
- **reorder 后聚焦逻辑变化** — active 文件 tab / active terminal session 不因 reorder 变化
- **键盘 reorder（如 Cmd+Opt+方向键）** — 非本需求
- **Drag preview 渲染自定义内容** — 用 SwiftUI 默认拖拽预览，不重画

---

## Phase 0：Spike — List.onMove × 外部 onDrop 共存性

### 验证目的

`SidebarView` 当前在 `List` 上挂了 `.onDrop(of: [UTType.fileURL], delegate: SidebarDropDelegate(...))`（接受 Finder 拖入的外部文件夹）。新增 `.onMove(perform:)` 之后需要确认：

| 场景 | 期望 |
|---|---|
| 从 Finder 拖一个文件夹进 Sidebar | 走 `SidebarDropDelegate.performDrop` → `pinnedFolders.add(url)` |
| 在 Sidebar 内拖动一个 Favorites 条目重排 | 走 `.onMove` → `pinnedFolders.move(from:to:)` |
| 两个事件互不吞噬，互不重复触发 | ✅ |

### 验证方式

最小改动挂一个 stub `.onMove { from, to in print("move \(from) → \(to)") }` 在现有 Section 内，跑构建 + 手测两个场景，确认 log 与行为分流正确。Spike 通过即继续 Phase 1；不通过则改方案 A：放弃 List.onMove，三域统一手写 `.draggable` + `.dropDestination(for: PinnedItemDragID.self)`，外部 fileURL drop 改用 `.dropDestination(for: URL.self)`（与 `PinnedItemDragID` 类型隔离）。

### 风险

低。macOS Sonoma 起 `List` 同时挂 `.onMove` 和 `.onDrop` 在公开文档与 sample code 中是常见组合（如 SwiftUI Reminders demo）。

---

## Phase 1：PinnedFolders reorder + List.onMove

### `PinnedFolders` 新增

```swift
func move(from offsets: IndexSet, to destination: Int) {
    items.move(fromOffsets: offsets, toOffset: destination)
    bookmarks.move(fromOffsets: offsets, toOffset: destination)
    persist()
}
```

### `SidebarView` 接入

```swift
Section("Favorites") {
    ForEach(pinnedFolders.items, id: \.self) { url in
        // 现有 HStack / icon / Text / tag / contextMenu 不动
    }
    .onMove { from, to in pinnedFolders.move(from: from, to: to) }
}
```

### 关键点

- `items` 与 `bookmarks` 是同序数组，**必须用同一 `IndexSet` + `destination` 同步重排**，否则下次启动 bookmark 解析得到的 URL 与可见顺序不一致（隐蔽 bug）
- 复用现有 `persist()`，不引入新 UserDefaults key
- `seed` 五项默认与用户拖入项视觉与行为完全同质（S30 已确认），reorder 不区分来源

### 风险

- IndexSet 多元素拖拽：SwiftUI `Array.move(fromOffsets:toOffset:)` 标准库实现，多元素同序保持；不再补一层手写逻辑
- 单元素 reorder（items.count == 1）：`List.onMove` 在单元素时不会触发拖拽手势（系统自适应），不需要特判

---

## Phase 2：文件 Tab Bar reorder

### 新增 Transferable 类型

```swift
struct FileTabDragID: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pathDeckFileTab)
    }
}
```

```swift
extension UTType {
    static let pathDeckFileTab = UTType(exportedAs: "in.riverflows.PathDeck.fileTab")
    static let pathDeckTerminalSession = UTType(exportedAs: "in.riverflows.PathDeck.terminalSession")
}
```

注意：自定义 UTType 仅 process 内有效（不进 Info.plist `UTExportedTypeDeclarations`），因为 reorder payload 不跨进程传递；进程内 SwiftUI Transferable 路径无需 system 注册。

### `TabManager` 新增

```swift
func moveFileTab(source: UUID, to destinationIndex: Int) {
    guard let from = fileTabs.firstIndex(where: { $0.id == source }) else { return }
    let clamped = max(0, min(destinationIndex, fileTabs.count))
    fileTabs.move(fromOffsets: IndexSet(integer: from), toOffset: clamped)
    saveTabState()
}
```

> `activeFileTabID` 保持不变；UUID 比对识别 active，数组下标变化不影响。

### `FileTabBar` 接入

每个 `FileTabItem` 挂：

```swift
.draggable(FileTabDragID(id: tab.id))
.dropDestination(for: FileTabDragID.self) { items, location in
    guard let source = items.first?.id, source != tab.id else { return false }
    let targetIndex = onResolveDropIndex(tab.id, location)  // 计算 before/after
    onReorder(source, targetIndex)
    return true
} isTargeted: { hovering in
    dropTargetEdge = hovering ? (location.x < width/2 ? .leading : .trailing) : nil
}
```

drop 边判定（伪代码）：

```swift
private func resolveDropIndex(currentIndex: Int, location: CGPoint, itemWidth: CGFloat) -> Int {
    location.x < itemWidth / 2 ? currentIndex : currentIndex + 1
}
```

插入指示线（每个 FileTabItem `.overlay`）：

```swift
.overlay(alignment: dropTargetEdge == .leading ? .leading : .trailing) {
    if dropTargetEdge != nil {
        Rectangle().fill(Color.accentColor).frame(width: 2)
    }
}
```

source 半透明：通过 `@State var isDragging` + `.onDrag {... isDragging = true}` 不可靠（SwiftUI 没有 onDragEnd 回调）→ 改用 `.opacity(tabManager.draggingFileTabID == tab.id ? 0.4 : 1.0)`，TabManager 暴露 `@MainActor var draggingFileTabID: UUID?`，在 `.draggable` 之外靠 `.onChange(of:)` 拖拽阶段事件或 `DragGesture` 跟踪。

> **细节风险**：SwiftUI `.draggable` 无 onBegin/onEnd 回调，半透明状态难精确同步。备选 = 不做 source 半透明（拖拽过程仍能看清原位置，但视觉略弱）。本 plan 推荐 P2 实现期先按"无 source 半透明"上线，若 Sir 验收觉得手感弱再补 DragGesture overlay 追加。

### `ContentView` 透传

`FileTabBar(onReorder: { tabManager.moveFileTab(source: $0, to: $1) })`，签名加一个回调。

### 单 tab 守卫（D5）

```swift
.draggable(FileTabDragID(id: tab.id))
.disabled(tabs.count <= 1)  // 或直接条件挂载 .draggable
```

`.disabled` 仅影响 draggable，不影响 onTapGesture（select），因为 `.draggable` 在 SwiftUI 内是手势，不是 view modifier 链上的全局禁用；实际验证：用 `if tabs.count > 1 { item.draggable(...) } else { item }` 条件 view 树更稳。

### 边界

- drop 到自己：`source != tab.id` 短路，返回 false 不动数据
- drop 到 "+" 新建按钮：按钮本身不挂 dropDestination，drop 落空 → 系统 cancel 动画
- drop 到 tab bar 空白处（ScrollView 末尾）：本期不支持"drop 到末尾"专用区，必须 drop 在某个 tab 上完成 reorder

---

## Phase 3：Terminal Tab Bar reorder（横 + 纵 两套视图）

### 数据层

```swift
func moveTerminalSession(in tabID: UUID, source: UUID, to destinationIndex: Int) {
    guard let tabIdx = fileTabs.firstIndex(where: { $0.id == tabID }) else { return }
    var ids = fileTabs[tabIdx].terminalSessionIDs
    guard let from = ids.firstIndex(of: source) else { return }
    let clamped = max(0, min(destinationIndex, ids.count))
    ids.move(fromOffsets: IndexSet(integer: from), toOffset: clamped)
    fileTabs[tabIdx].terminalSessionIDs = ids
    // activeTerminalID 不动；terminalSessions dict 不动
    saveTabState()
}
```

### `TerminalTabBar`（横向）接入

完全镜像 Phase 2 的横向方案：
- payload = `TerminalSessionDragID(id: session.id)`
- drop 边判定按 `location.x < width/2`
- 插入指示线竖直 2pt accent
- 单 session 禁用 draggable

回调签名：`onReorder: (UUID, Int) -> Void`，ContentView 透传到 `tabManager.moveTerminalSession(in: activeTabID, source:to:)`。

### `VerticalTerminalTabBar`（纵向）接入

方向参数化：
- drop 边判定按 `location.y < height/2`（落上半 = before，下半 = after）
- 插入指示线水平 2pt accent，alignment 切换 `.top` / `.bottom`
- 其余逻辑与横向一致

### 边界

- reorder 不切换 active terminal session（即使 active 被拖到别的位置）
- terminal anchor cwd（属于 FileTab，不属于 session）不受影响
- session 的 ghostty PTY / surface 不重建（数组顺序变化不触发 view identity 变化，`ForEach(sessions) { ... }` 用 `session.id`，view tree 自动维持）

---

## Phase 4：测试

### 新增 `PathDeckTests/PinnedFoldersReorderTests.swift`

```swift
import Testing
import Foundation
@testable import PathDeck

@Suite
struct PinnedFoldersReorderTests {
    private func makeWithItems(_ count: Int) -> (PinnedFolders, UserDefaults, String) {
        let suiteName = "PathDeckTests-reorder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // 用 tmp 目录创真实存在的子目录，确保 bookmark 创建成功
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-reorder-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for i in 0..<count {
            let dir = tmp.appendingPathComponent("item\(i)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // 先写入空数组 → 走"不 seed"分支
        defaults.set([Data](), forKey: "pinnedFolderBookmarks")
        let folders = PinnedFolders(userDefaults: defaults)
        for i in 0..<count {
            folders.add(tmp.appendingPathComponent("item\(i)"))
        }
        return (folders, defaults, suiteName)
    }

    @Test
    func moveSwapsItemsAndBookmarksInSync() {
        let (folders, _, suite) = makeWithItems(3)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let originalFirst = folders.items[0]
        folders.move(from: IndexSet(integer: 0), to: 3)  // 把第一项移到末尾
        #expect(folders.items.last == originalFirst)
        // bookmark 同步：重新构造一次实例（走 loadFromBookmarks）应顺序一致
    }

    @Test
    func movePersistsAfterReorder() {
        let (folders, defaults, suite) = makeWithItems(3)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        folders.move(from: IndexSet(integer: 0), to: 3)
        let reordered = folders.items
        let reloaded = PinnedFolders(userDefaults: defaults)
        #expect(reloaded.items == reordered)
    }

    @Test
    func moveSingleItemNoop() {
        let (folders, _, suite) = makeWithItems(1)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let before = folders.items
        folders.move(from: IndexSet(integer: 0), to: 0)  // 自身位置
        #expect(folders.items == before)
    }

    @Test
    func moveMultipleItems() {
        let (folders, _, suite) = makeWithItems(5)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let original = folders.items
        folders.move(from: IndexSet([0, 1]), to: 5)  // 前两项移到末尾
        #expect(folders.items.suffix(2) == [original[0], original[1]])
    }
}
```

### `TabManagerTests.swift` 追加

```swift
@Test func moveFileTabChangesOrder() {
    let tm = makeBareManager()
    let a = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let b = tm.createTab(at: URL(fileURLWithPath: "/Users"))
    let c = tm.createTab(at: URL(fileURLWithPath: "/"))
    tm.moveFileTab(source: a, to: 3)  // a 移到末尾
    #expect(tm.fileTabs.map(\.id) == [b, c, a])
}

@Test func moveFileTabPreservesActiveID() {
    let tm = makeBareManager()
    let a = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let b = tm.createTab(at: URL(fileURLWithPath: "/Users"))
    tm.activeFileTabID = a
    tm.moveFileTab(source: a, to: 2)
    #expect(tm.activeFileTabID == a)
}

@Test func moveFileTabPreservesWorkspaceModels() {
    let tm = makeBareManager()
    let a = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let b = tm.createTab(at: URL(fileURLWithPath: "/Users"))
    let modelA = tm.workspaceModels[a]
    let modelB = tm.workspaceModels[b]
    tm.moveFileTab(source: a, to: 2)
    #expect(tm.workspaceModels[a] === modelA)
    #expect(tm.workspaceModels[b] === modelB)
}

@Test func moveFileTabInvalidSourceNoop() {
    let tm = makeBareManager()
    let a = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let b = tm.createTab(at: URL(fileURLWithPath: "/Users"))
    let before = tm.fileTabs.map(\.id)
    tm.moveFileTab(source: UUID(), to: 0)
    #expect(tm.fileTabs.map(\.id) == before)
}

@Test func moveTerminalSessionChangesOrder() {
    let tm = makeBareManager()
    let tabID = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let s1 = UUID(); let s2 = UUID(); let s3 = UUID()
    tm.addTerminalSession(.init(id: s1, title: "T1", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.addTerminalSession(.init(id: s2, title: "T2", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.addTerminalSession(.init(id: s3, title: "T3", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.moveTerminalSession(in: tabID, source: s1, to: 3)
    let tab = tm.fileTabs.first { $0.id == tabID }!
    #expect(tab.terminalSessionIDs == [s2, s3, s1])
}

@Test func moveTerminalSessionPreservesActiveID() {
    let tm = makeBareManager()
    let tabID = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let s1 = UUID(); let s2 = UUID()
    tm.addTerminalSession(.init(id: s1, title: "T1", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.addTerminalSession(.init(id: s2, title: "T2", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.setActiveTerminal(s2)
    tm.moveTerminalSession(in: tabID, source: s2, to: 0)
    let tab = tm.fileTabs.first { $0.id == tabID }!
    #expect(tab.activeTerminalID == s2)
}

@Test func moveTerminalSessionDoesNotMutateSessionsDict() {
    let tm = makeBareManager()
    let tabID = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let s1 = UUID(); let s2 = UUID()
    tm.addTerminalSession(.init(id: s1, title: "T1", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    tm.addTerminalSession(.init(id: s2, title: "T2", cwd: URL(fileURLWithPath: "/tmp")), to: tabID)
    let before = tm.terminalSessions
    tm.moveTerminalSession(in: tabID, source: s1, to: 2)
    #expect(tm.terminalSessions.keys == before.keys)
}

@Test func saveTabStatePersistsReorderedSequence() {
    let suite = UserDefaults(suiteName: "TabManagerTests.\(UUID().uuidString)")!
    let tm = TabManager(defaults: suite)
    let a = tm.createTab(at: URL(fileURLWithPath: "/tmp"))
    let b = tm.createTab(at: URL(fileURLWithPath: "/Users"))
    tm.moveFileTab(source: a, to: 2)
    // saveTabState 已在 moveFileTab 内调用
    // 用同一 suite 构造新 TabManager 走 restoreTabState(terminalEngine:)
    let tm2 = TabManager(defaults: suite)
    let engine = StubTerminalEngine()  // 既有测试工具
    tm2.restoreTabState(terminalEngine: engine)
    #expect(tm2.fileTabs.map(\.id) == [b, a])
}
```

> `StubTerminalEngine` 沿用 `TabManagerTests.swift` 现有测试基础设施；若未定义，本 plan 新增最小桩。

### 现有测试不动

`PinnedFoldersSeedTests` / `PinnedFoldersBookmarkTests` / 其它 `TabManagerTests` 用例保持不动。

---

## Phase 5：文档同步

`AGENTS.md` 三处需要改：

1. **行 47**（sprint 累计描述末尾追加）：
   - 追加：`S31 Reorder：Sidebar Favorites（List.onMove）+ 文件 Tab Bar + Terminal Tab Bar（横/纵）手动拖拽排序，三域各自 Transferable payload 隔离，复用既有持久化通道。`

2. **行 56**（SidebarView 描述）：
   - 旧：`Sidebar（统一 Favorites 区块）+ PinnedFolders bookmark 持久化（首次启动 seed 默认五项，删空不恢复）`
   - 新：`Sidebar（统一 Favorites 区块，List.onMove 手动重排）+ PinnedFolders bookmark 持久化（首次启动 seed 默认五项，删空不恢复）`

3. **行 82**（Sidebar 扩展路线 P2 段）：
   - 旧含 `~~Pinned 拖拽重排序~~` 一项 → 在合入后改为 `✅ S31`

4. **变更日志**（行 50 附近）：
   - 新增条目：`2026-06-18 **S31 Reorder**：三域手动拖拽排序。SidebarView Pinned 用 `List.onMove(perform:)` + `PinnedFolders.move(from:to:)` 同序重排 items/bookmarks；FileTabBar 与 Terminal TabBar（横/纵）用 `.draggable(FileTabDragID/TerminalSessionDragID)` + `.dropDestination(for:)` + 插入指示线 + 半透明 source；`TabManager.moveFileTab` / `moveTerminalSession` 不重建 WorkspaceModel/Session，active ID 不变，复用 `saveTabState()` 持久化。N 个新单测。`

子目录 `AGENTS.md`：

- `PathDeck/Terminal/AGENTS.md` 若有 TabBar 接口契约段落，追加一句"`onReorder: (UUID, Int) -> Void` 由宿主透传到 `TabManager.moveTerminalSession`，session 数组顺序变化不重建 PTY / surface"。否则不动。

---

## 验证

### 自动（必须）

```bash
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck build
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PathDeckTests/PinnedFoldersReorderTests \
  -only-testing:PathDeckTests/TabManagerTests \
  test
```

### 手动（Xcode 内跑，分三域逐项）

| 场景 | 操作 | 预期 |
|---|---|---|
| Pinned-1 | sidebar 拖第 2 项到第 4 项 | 顺序改变，松手后无闪烁 |
| Pinned-2 | 场景 1 后重启 App | 新顺序保留 |
| Pinned-3 | 从 Finder 拖一个新文件夹进 sidebar 末尾 | 走 SidebarDropDelegate，**追加**而非 reorder（验证 D1 spike 结论） |
| Pinned-4 | 单条目时尝试拖拽 | 无响应（List 自适应单条目无 reorder） |
| Pinned-5 | 拖一个条目到自己位置 | 无变化，无报错 |
| FileTab-1 | 3 个文件 tab，拖第 1 个到第 3 个右半边 | 顺序变 [2,3,1]，重启保留 |
| FileTab-2 | active tab 是第 2 个，拖第 1 个到末尾 | active 仍是原来那个（UUID 比对） |
| FileTab-3 | 单 tab 时尝试拖拽 | 无拖拽响应 |
| FileTab-4 | 拖 tab 到"+"按钮上 | 无响应（"+" 不挂 drop） |
| FileTab-5 | 终端 tab 上挂载的文件 tab 拖动后 | 终端 PTY 不重建（输入历史保留） |
| TermTab-横-1 | 横向 Terminal Tab Bar，2 sessions，拖第 1 个到第 2 个右边 | 顺序交换 |
| TermTab-横-2 | reorder 后切到别的文件 tab 再切回来 | 顺序保留 |
| TermTab-横-3 | reorder 后重启 App | 顺序保留 |
| TermTab-纵-1 | 切到 Terminal-first 模式，纵向 tab bar 拖动第 1 个到第 2 个下半边 | 顺序交换 |
| TermTab-纵-2 | 纵向 reorder 后切横向 | 顺序一致 |
| 跨域-1 | 拖一个文件 tab 到 sidebar | 无响应（类型不匹配） |
| 跨域-2 | 拖一个 terminal session 到文件 tab bar | 无响应 |
| 跨域-3 | 拖一个 sidebar 条目到 tab bar | 无响应（fileURL ≠ PinnedItemDragID 类型） |

---

## 回滚

- 改动隔离在 `SidebarView.swift` / `FileTabBar.swift` / `TerminalTabBar.swift` / `VerticalTerminalTabBar.swift` / `TabManager.swift` + 一个新测试文件 + AGENTS.md
- 回滚命令：`git revert <s31 commit>` 即可恢复 reorder 前形态
- 用户侧数据影响：reorder 写入的顺序变化仅影响 UserDefaults 中数组顺序，回滚后旧版本读到的"已被 reorder 过"的顺序仍是合法顺序（既不丢条目也不复制条目），无 data corruption

---

## Open Questions

| # | 问题 | 实现期决议方式 |
|---|---|---|
| Q1 | Source 半透明状态在 SwiftUI `.draggable` 上是否能精确同步 | Phase 0 spike 末尾顺手验证；不行则 P2/P3 默认不做 source 半透明，仅保留插入指示线 |
| Q2 | `List.onMove` 在 sidebar style 下是否需要额外手势/EditMode 配置 | Phase 0 spike 验证；如需 EditMode 则评估方案 A（手写 .draggable）回退 |
| Q3 | `.dropDestination(for: UUID.self)` 是否能稳定接收 process 内 Transferable | macOS 26.5 + Swift 5.0 兼容性已在 SwiftUI Reminders 等官方 sample 中验证，不预设阻塞；spike 期间一并实测 |

## Acceptance

- Phase 0 spike 通过（或确认走方案 A 回退路径）
- Phase 1–5 全部交付
- 新增单测全绿（PinnedFoldersReorderTests + TabManagerTests 追加用例）
- 手动验证 17 个场景全部通过
- AGENTS.md 三处描述同步 + 变更日志条目就位
- commit message 遵循仓库规范（英文，中性指代，无个人称谓）
