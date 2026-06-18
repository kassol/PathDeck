# S29 Convergence — 崩溃防御 / 展开态保留 / IME 合成清理

> 日期：2026-06-18
> 前置：S28 已合入（Quality Gate）+ FSWatcher deadlock fix

## 目标

关掉 S23–S28 累积的 medium 风险项，为发布收敛。无新功能，不改用户可见行为（展开态保留和 IME 清理除外，这两个是修正预期行为）。

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P1 | Fix | OutlineDataSource crash 防御 | `OutlineDataSource.swift` |
| P2 | Fix | 搜索模式 flat subscript 守卫 | `FileTableView.swift` |
| P3 | Fix | 本地操作保留展开状态 | `WorkspaceModel.swift` |
| P4 | Fix | IME binding 旁路清 preedit | `GhosttySurfaceView.swift` |
| P5 | Fix | resignFirstResponder 清 IME 态 | `GhosttySurfaceView.swift` |
| P6 | Test | 新增 + 回归测试 | `OutlineDataSourceTests.swift`, `WorkspaceModelTests.swift` |

## Not Building

- `buildInputKey` composing 恒 false — 仅影响裸键 binding 在合成中被旁路，常规 modifier 组合不受影响，改了反而可能改变 libghostty 行为
- 搜索模式切换 crash — 审计确认 `numberOfChildren` 在 flat 模式对非 nil item 返回 0，NSOutlineView 不会请求 stale FileNode 的 children，FALSE ALARM
- 线程安全重写 — FSWatcher handler 经 `DispatchQueue.main.async` 中转，OutlineDataSource 纯主线程，无竞态
- GhosttySurfaceView 单元测试 — 依赖 libghostty C API + surface 生命周期，无法在 headless 单测中运行，IME 修复走手动验证

---

## Phase 1：OutlineDataSource crash 防御

### 问题

`child(index:of:)` (OutlineDataSource.swift:102-107) 对 `childrenCache[node.item.url]` 做 force unwrap + 无 bounds check。当 NSOutlineView 缓存的 child count 与 `childrenCache` 不同步时（如 `loadRoot` 清空 cache 后、`reloadItem` 尚未执行前的微窗口），force unwrap 或越界访问崩溃。

### 方案

```swift
func child(index: Int, of node: FileNode?) -> FileNode {
    if let node {
        guard let children = childrenCache[node.item.url],
              index < children.count else {
            return FileNode(FileItem(
                url: node.item.url.appendingPathComponent("__placeholder__"),
                name: "", isDirectory: false, size: nil, modifiedDate: nil, kind: ""))
        }
        return children[index]
    }
    guard index < rootNodes.count else {
        return FileNode(FileItem(
            url: URL(fileURLWithPath: "/"), name: "", isDirectory: false,
            size: nil, modifiedDate: nil, kind: ""))
    }
    return rootNodes[index]
}
```

返回占位 node 而不是 crash。NSOutlineView 随后会通过 `reloadItem` 获取正确数据，占位 node 被丢弃。

---

## Phase 2：搜索模式 flat subscript 守卫

### 问题

FileTableView.swift:278 `FlatFileNode(item: flatItems[index])` 无 bounds check，与 `itemForRow` (264) 的守卫不一致。

### 方案

```swift
func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if isSearching {
        guard index < flatItems.count else {
            return FlatFileNode(item: FileItem(
                url: URL(fileURLWithPath: "/"), name: "", isDirectory: false,
                size: nil, modifiedDate: nil, kind: ""))
        }
        return FlatFileNode(item: flatItems[index])
    }
    return self.outlineDataSource.child(index: index, of: item as? FileNode)
}
```

---

## Phase 3：本地操作保留展开状态

### 问题

`newFolder()` / `renameItem()` / `trashItems()` / `toggleHidden()` 调用 `reload()` → `outlineDataSource.loadRoot()` → `childrenCache.removeAll()`。展开的子目录全部折叠。

FSWatcher 触发的刷新正确使用 `refreshRoot`（保留展开态），本地操作应保持一致。

### 方案

OutlineDataSource 新增 `refreshAll`，刷新根层 + 所有已展开子目录缓存：

```swift
/// 刷新根层 + 所有已缓存的展开子目录。保留展开状态，但内容全量更新。
func refreshAll(_ directory: URL) {
    refreshRoot(directory)
    for url in Array(childrenCache.keys) {
        _ = reloadChildren(for: url)
    }
}
```

WorkspaceModel 拆分 `reload()` 和 `navigate(to:)`：

```swift
func reload() {
    let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
    allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
    applySearch()

    outlineDataSource.sortColumn = sortColumn
    outlineDataSource.sortAscending = sortAscending
    outlineDataSource.showHidden = showHidden
    outlineDataSource.refreshAll(currentURL)    // ← 保留展开态，全量刷新
    syncWatcherExpandedDirs()
}

func navigate(to url: URL) {
    currentURL = url.standardizedFileURL
    searchQuery = ""
    isSearching = false
    reload()                                    // reload 内部已用 refreshAll
    outlineDataSource.loadRoot(currentURL)      // 导航切目录时再清空展开态
    syncWatcherExpandedDirs()
    watcher?.watch(directory: currentURL)
}
```

注意 `navigate` 先 `reload()`（更新 allItems/search），再 `loadRoot`（清空展开态覆盖 `refreshAll` 的结果）。这比内联更简洁，但有一次多余的 refreshAll。如果性能敏感，可改为 navigate 直接调 loadRoot 跳过 refreshAll：

```swift
func navigate(to url: URL) {
    currentURL = url.standardizedFileURL
    searchQuery = ""
    isSearching = false
    let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
    allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
    applySearch()
    outlineDataSource.sortColumn = sortColumn
    outlineDataSource.sortAscending = sortAscending
    outlineDataSource.showHidden = showHidden
    outlineDataSource.loadRoot(currentURL)
    syncWatcherExpandedDirs()
    watcher?.watch(directory: currentURL)
}
```

推荐后者（避免多余刷新）。

### 验证

- 新建文件夹后，已展开的子目录仍保持展开
- 切换隐藏文件后，展开态保留且隐藏文件在子目录中也正确显示/隐藏
- 删除展开子目录中的文件后，列表立即更新
- 导航到新目录时，展开态正确清空

---

## Phase 4+5：IME 合成期按键处理（对齐 Ghostty 原生）

### 问题

S28 原方案用 `ghostty_surface_key_is_binding` 在 `performKeyEquivalent` 中 gate 合成期按键。
但 Ctrl+C 在 libghostty 中不是 config binding（它是产生 ETX 的原始按键），导致 `is_binding`
返回 false，合成中 Ctrl+C 无反应。

### 参考实现

调研 Ghostty 原生和 cmux 的 IME 处理，两者完全一致：

1. 合成期 Ctrl+key 不在 `performKeyEquivalent` 拦截，流向 `keyDown`
2. `keyDown` 的 binding 快速路径用 `!hasMarkedText()` 守卫——合成期跳过
3. 合成期所有按键走 `interpretKeyEvents` → IME 先处理
4. `interpretKeyEvents` 后，合成态下单个控制符（< 0x20）抑制转发（Ghostty 的
   `shouldSuppressComposingControlInput` 模式）
5. `is_binding` 仅在 `performKeyEquivalent` 的非合成路径使用，与 IME 正交

### 方案

三处改动：

**`performKeyEquivalent`**：合成中非 Cmd 键 → `return super`（流向 keyDown）

```swift
if markedText != nil {
    return super.performKeyEquivalent(with: event)
}
```

**`keyDown` binding 快速路径**：加 `markedText == nil` 守卫

```swift
if markedText == nil {
    let key = buildInputKey(from: event, action: action)
    var bindingFlags = ghostty_binding_flags_e(rawValue: 0)
    if ghostty_surface_key_is_binding(surface, key, &bindingFlags) {
        sendKeyEvent(event, action: action, surface: surface)
        return
    }
}
```

**`keyDown` interpretKeyEvents 后**：抑制合成期单个控制符

```swift
if hadMarkedTextBeforeInterpret {
    let scalars = text.unicodeScalars
    if let first = scalars.first,
       scalars.index(after: scalars.startIndex) == scalars.endIndex,
       first.value < 0x20 {
        continue
    }
}
```

**`clearComposition()` helper** 保留，仅用于 `resignFirstResponder`（切焦点时清理残留合成态）。

### 行为变化

| 场景 | S28 行为 | S29 行为（对齐 Ghostty） |
|------|---------|------------------------|
| 合成中 Ctrl+C | 无反应（is_binding=false） | IME 取消合成，不发 SIGINT。再按一次发 SIGINT |
| 合成中 ESC | IME 取消合成 | 同左 |
| 合成中 Ctrl+G | 取决于 is_binding | IME 处理，控制符抑制 |
| 切焦点时残留 preedit | preedit 残留 | clearComposition 清理 |

---

## Phase 6：测试

### OutlineDataSource

- `child(index:of:)` 越界返回占位 node 不 crash
- `refreshRoot` 保留展开态、裁剪已删除目录

### WorkspaceModel

- `reload()` 后 `expandedDirectoryURLs` 不为空（验证用 `refreshRoot`）
- `navigate(to:)` 后 `expandedDirectoryURLs` 为空（验证用 `loadRoot`）

### IME（手动验证）

1. 打开终端，切换到中文输入法
2. 输入拼音 "zhong"，preedit 显示候选
3. 按 Ctrl+C → IME 取消合成（preedit 消失），终端不收到 SIGINT（对齐 Ghostty）
4. 再按 Ctrl+C（此时无合成态）→ 终端收到 SIGINT
5. 再次输入拼音，按 ESC → 合成取消
6. 点击文件列表切走焦点 → preedit 应清除
7. 点回终端 → 无残留合成态，可正常输入

---

## 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| crash 防御用占位 node vs fatalError | 占位 node | 生产环境不能因 UI 时序抖动崩溃，占位 node 被下一帧 reload 覆盖 |
| reload 拆分 vs 新增 refreshReload 方法 | 拆分 reload + navigate 各自内联 | 避免增加方法数，两处逻辑差异仅一行（loadRoot vs refreshRoot） |
| clearComposition 放 helper vs 内联 | helper | 两处调用（binding 旁路 + resign），复用且语义清晰 |

## 风险

- `refreshAll` 遍历所有已展开子目录做 `reloadChildren`，在深层级大量展开时有性能开销。当前产品最多 2-3 层展开，可接受。如果未来支持深层级，考虑只刷新 dirty 路径。
