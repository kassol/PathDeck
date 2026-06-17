# S26：目录就地折叠/展开（NSOutlineView 迁移）

> 日期：2026-06-17
> 前置：S25 i18n 已合入

## 目标

将文件列表从 `NSTableView` 迁移到 `NSOutlineView`，支持目录就地展开/折叠（Finder list view 核心交互）。

## Scope

| # | 内容 | 涉及文件 |
|---|------|----------|
| 1 | FileItem 扩展树节点能力 | `FileItem.swift` |
| 2 | 新增 OutlineDataSource 管理层级数据 | 新建 `OutlineDataSource.swift` |
| 3 | FileTableView NSTableView → NSOutlineView | `FileTableView.swift`（重写 Coordinator） |
| 4 | FSWatcher 支持已展开子目录刷新 | `FSWatcher.swift` |
| 5 | WorkspaceModel 适配 outline 数据流 | `WorkspaceModel.swift` |

## Not Building

- 多级嵌套展开状态的持久化（本次展开状态仅 session 内有效，关闭/导航后重置）
- Column view / Icon view（后续独立课题）
- 异步目录加载进度指示（大目录直接同步加载，性能不足时再优化）

---

## 架构分析

### 现状

```
WorkspaceModel
  └── items: [FileItem]          ← flat 数组
        ↓
FileTableView (NSTableView)
  └── Coordinator: NSTableViewDataSource/Delegate
        └── numberOfRows / viewForRow     ← row-index based
```

- `FileItem` 是纯值类型，无层级概念
- `WorkspaceModel.reload()` 调 `DirectoryLister.list()` 拿当前目录一层
- `FSWatcher` 只监听 `parent == watchedDir` 的事件
- `FileTableView.Coordinator` 全部用 row index 操作

### 目标

```
WorkspaceModel
  └── outlineDataSource: OutlineDataSource
        └── rootItems: [FileItem]              ← 顶层
        └── children[url]: [FileItem]?         ← 已展开目录的子项缓存
              ↓
FileTableView (NSOutlineView)
  └── Coordinator: NSOutlineViewDataSource/Delegate
        └── child(ofItem:) / isExpandable     ← item-based
```

---

## 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| FileItem 是否持有 children | 否，children 由 OutlineDataSource 管理 | FileItem 保持值类型 + Sendable，层级状态集中管理 |
| 数据源管理 | 新建 `OutlineDataSource` class | 隔离树状态逻辑，不膨胀 WorkspaceModel |
| 子目录加载方式 | 展开时同步加载（DirectoryLister.list） | 简单可靠；单层目录加载 <10ms，不需 async |
| FSWatcher 策略 | 递归监听根目录，按展开状态过滤 | FSEventStream 本身就是递归的，filter 在回调侧做 |
| 排序 | 每层独立排序，与 Finder 一致 | NSOutlineView 的 sortDescriptorsDidChange 天然 per-level |
| 展开动画 | 使用 NSOutlineView 默认动画 | 原生行为，零代码 |
| disclosure triangle | NSOutlineView 内建，`indentationPerLevel = 16` | Finder 风格 |

---

## 详细方案

### Step 1：FileItem 不变

`FileItem` 保持现有结构不动。`isDirectory` 字段已足够让 NSOutlineView 判断 expandable。

### Step 2：OutlineDataSource

新建 `PathDeck/FileWorkspace/OutlineDataSource.swift`：

```swift
final class OutlineDataSource {
    private(set) var rootItems: [FileItem] = []
    /// url → 已加载的子项。nil = 未展开/未加载，[] = 空目录
    private var childrenCache: [URL: [FileItem]] = [:]
    
    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false
    
    /// 加载/刷新根目录
    func loadRoot(_ directory: URL) { ... }
    
    /// 展开目录时加载子项
    func loadChildren(for item: FileItem) -> [FileItem] { ... }
    
    /// 目录折叠时清除缓存
    func clearChildren(for item: FileItem) { ... }
    
    /// FSWatcher 事件命中某个已展开目录时刷新
    func reloadChildren(for directoryURL: URL) -> [FileItem]? { ... }
    
    /// 当前已展开的所有目录 URL（供 FSWatcher 过滤）
    var expandedDirectoryURLs: Set<URL> { ... }
    
    /// NSOutlineViewDataSource 需要的方法
    func numberOfChildren(of item: FileItem?) -> Int { ... }
    func child(index: Int, of item: FileItem?) -> FileItem { ... }
    func isExpandable(_ item: FileItem) -> Bool { item.isDirectory }
}
```

内部调用 `DirectoryLister.list()` + `WorkspaceModel.sortedItems()` 复用排序逻辑。

### Step 3：FileTableView 重写

核心改动：

| Before (NSTableView) | After (NSOutlineView) |
|---|---|
| `NSTableView` | `NSOutlineView` |
| `NSTableViewDataSource` | `NSOutlineViewDataSource` |
| `NSTableViewDelegate` | `NSOutlineViewDelegate` |
| `numberOfRows(in:)` | `outlineView(_:numberOfChildrenOfItem:)` |
| `viewFor tableColumn: row:` | `outlineView(_:viewFor:item:)` |
| `items[row]` | `item as! FileItem` |
| `tv.selectedRowIndexes` → `items[i]` | `tv.selectedRowIndexes` → `tv.item(atRow:) as? FileItem` |
| `tv.reloadData()` | `tv.reloadItem(nil, reloadChildren: true)` 或精确 reload |

**需要逐一迁移的 Coordinator 功能**：

1. **DataSource**：`numberOfChildren` / `child` / `isExpandable` — 代理到 OutlineDataSource
2. **Cell rendering**：`viewFor tableColumn item` — 与现有逻辑相同，只是入参从 row 变为 item
3. **Selection**：`outlineViewSelectionDidChange` — 从 `selectedRowIndexes` 映射到 `FileItem`
4. **Double click**：检查 item 类型，目录进入 / 文件打开
5. **Context menu**：`menuNeedsUpdate` — 从 `clickedRow` 获取 item（`outlineView.item(atRow:)`）
6. **Sort**：`sortDescriptorsDidChange` — 调 OutlineDataSource 重排各层
7. **Drag**：`pasteboardWriterForRow` → `pasteboardWriterForItem`（NSOutlineView 没有 row-based drag API，改用 `outlineView(_:pasteboardWriterForItem:)`）
8. **Rename**：inline editing 逻辑不变，row → item 映射调整
9. **Quick Look**：QLPreviewPanel dataSource/delegate 不变
10. **Reveal selection**：`selectRowIndexes` 需先找 item 的 row（`outlineView.row(forItem:)`）

**展开/折叠回调**：

```swift
func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
    // 触发子目录加载
    guard let fileItem = item as? FileItem else { return false }
    _ = dataSource.loadChildren(for: fileItem)
    return true
}

func outlineViewItemDidExpand(_ notification: Notification) {
    // 更新 FSWatcher 监听范围
    updateWatcherScope()
}

func outlineViewItemDidCollapse(_ notification: Notification) {
    guard let fileItem = notification.userInfo?["NSObject"] as? FileItem else { return }
    dataSource.clearChildren(for: fileItem)
    updateWatcherScope()
}
```

### Step 4：FSWatcher 适配

当前 `handleRawEvents` 只匹配 `parent == watchedDir`。迁移后需匹配所有已展开目录：

```swift
func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
    let watchedDirs = expandedDirectories  // 根目录 + 已展开的子目录
    var dirtyDirs: Set<String> = []
    
    for (path, flag) in zip(paths, flags) {
        let isFile = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
        let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
        guard isFile || isDir else { continue }
        let parent = (path as NSString).deletingLastPathComponent
        if watchedDirs.contains(parent) {
            dirtyDirs.insert(parent)
        }
    }
    
    guard !dirtyDirs.isEmpty else { return }
    // coalesce 后回调，传 dirtyDirs 给 WorkspaceModel 做精确 reload
}
```

**FSEventStream 本身已经是递归监听**（`kFSEventStreamCreateFlagFileEvents` 监听整棵树），现在只是回调过滤逻辑从"单目录匹配"扩展为"展开集合匹配"。不需要重建 stream。

关键改动：
- `FSWatcher.handler` 签名改为 `@Sendable (Set<String>) -> Void`，传入 dirty 目录集合
- `WorkspaceModel` 收到 dirty 目录后，只 reload 对应层级（`outlineView.reloadItem(dirItem, reloadChildren: true)`）

### Step 5：WorkspaceModel 适配

- `items` 属性改为仅代表根目录的 flat 列表（向后兼容搜索等功能）
- 新增对 `OutlineDataSource` 的持有
- `reload()` 改为调 `outlineDataSource.loadRoot(currentURL)`
- `navigate(to:)` 清空 OutlineDataSource 缓存
- 搜索模式下仍用 flat 列表（搜索结果不显示层级，与 Finder 一致）

---

## 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| NSOutlineView item identity | NSOutlineView 用 `isEqual` 比较 item，FileItem 是 struct 但每次 reload 重建实例 | FileItem 已实现 Hashable（基于 url），NSOutlineView 需要引用类型或稳定指针。**方案**：OutlineDataSource 内部用 `class FileNode` 包装，外部仍暴露 FileItem |
| node_modules / .git 等巨型目录展开 | 10k+ 子项加载慢，UI 卡顿 | 展开前 `contentsOfDirectory` count check，超阈值（如 5000）显示确认或截断 |
| 搜索模式与 outline 冲突 | 搜索结果是 flat 列表，不应显示 disclosure triangle | 搜索模式切回 flat 数据源（`outlineView.reloadData()` 清空层级） |
| 拖拽 API 差异 | NSOutlineView 没有 `pasteboardWriterForRow`，需用 item-based API | 实现 `outlineView(_:pasteboardWriterForItem:)` |
| updateNSView 刷新时机 | NSOutlineView reloadData 会丢失展开状态 | 精确 reload：根据 FSWatcher 返回的 dirty 目录，只 `reloadItem` 对应节点 |

### 最大风险：NSOutlineView item identity

NSOutlineView 内部持有 item 引用，要求跨 reload 同一目录的 item 保持 identity 一致。`FileItem` 是 struct，每次 `DirectoryLister.list()` 生成新实例。

**解决方案**：引入 `FileNode` 引用类型包装：

```swift
final class FileNode: NSObject {
    let item: FileItem
    init(_ item: FileItem) { self.item = item }
    
    override var hash: Int { item.url.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileNode else { return false }
        return item.url == other.item.url
    }
}
```

`OutlineDataSource` 管理 `FileNode` 实例池，reload 时复用同 URL 的 node（更新 item 属性），新增/删除的 node 增删。NSOutlineView 看到的始终是稳定的 `FileNode` 引用。

---

## 验证

### 自动化测试

- OutlineDataSource 单元测试（临时目录隔离）：
  - `loadRoot` 正确返回排序后的文件列表
  - `loadChildren` 正确加载子目录
  - `clearChildren` 清除缓存
  - `reloadChildren` 刷新后反映文件系统变更
  - 排序应用到每一层
- FSWatcher 单元测试：
  - 子目录事件被正确匹配到已展开集合

### 手动验证

| 操作 | 预期结果 |
|------|----------|
| 点击目录 disclosure triangle | 子项缩进显示，带 disclosure triangle |
| 再次点击折叠 | 子项消失 |
| 展开目录后在终端新建文件 | 文件自动出现在展开的子目录下 |
| 展开 node_modules（如有） | 正常显示，不卡死 |
| 搜索模式 | 结果为 flat 列表，无 disclosure triangle |
| 右键展开目录中的子项 | 上下文菜单正常（Open/Rename/Trash/Copy Path） |
| 拖拽展开目录中的文件到终端 | 路径正确插入 |
| 双击子目录 | 导航进入该目录（非展开） |
| 窗口缩放 | 列宽自适应不受影响（S24 lastColumnOnly 仍生效） |
| 排序切换 | 每层独立排序 |

---

## 实现顺序

1. **FileNode + OutlineDataSource**：新建文件，实现数据层，写单元测试
2. **FileTableView 迁移**：NSTableView → NSOutlineView，Coordinator 协议切换，保留全部功能
3. **FSWatcher 扩展**：handler 签名改为传 dirty 目录集合，回调精确刷新
4. **WorkspaceModel 适配**：持有 OutlineDataSource，navigate/reload/search 逻辑调整
5. **集成测试 + 手动验证**

每步完成后 build + 跑测试，Step 2 是最大改动（~300 行重写），需格外仔细。
