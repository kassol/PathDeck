# S10：拖拽到终端 + 变化感知增强

> 日期：2026-06-14　需求：drag-to-terminal + change-journal-upgrade（M2 切片 S10）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s9-send-path-to-terminal.md`。

## 背景定位（M2 第三切片）

S9 完成了 Context Bridge 首个功能（右键 / ⌘⇧T 发送路径到终端）。S10 从两个方向推进：

1. **Context Bridge 补完**：拖拽文件到终端（FR-BRIDGE-002），与 S9 共同构成「文件→终端」路径流转的完整交互闭环（菜单/快捷键 + 拖拽）。
2. **Change Journal 从原始日志升级为可操作面板**：当前 `ChangeListView` 是平铺的 event list，无分组、无过滤、不可交互——用户看到变化但无法据此行动。S10 补上时间分组、类型过滤、点击定位、文件列表变化标记，使「终端跑命令→看到变化→定位文件」闭环成立。

| M2 切片 | 内容 | 覆盖 PRD |
|---|---|---|
| S8 ✅ | Terminal Panel 嵌入主窗口 | FR-TERM-001/002 |
| S9 ✅ | Send Path to Terminal | FR-BRIDGE-001 |
| **S10** | **拖拽到终端 + 变化面板增强 + 文件列表变化标记** | **FR-BRIDGE-002 + FR-CHANGE-002（部分）** |
| S11（后续） | 多 Terminal Tab / Terminal cwd 同步 | FR-TERM-003 / FR-BRIDGE-004 |

## 验证标准（5 个验证点）

### V1：拖拽文件到终端

手动验证：
1. 从文件列表拖一个文件到终端面板 → 终端光标处出现 shell-escaped 绝对路径
2. 从文件列表拖多个文件到终端面板 → 空格分隔的多条转义路径
3. 包含空格、引号、中文的文件名 → 路径正确转义（复用 ShellEscape）
4. 终端面板隐藏时 → 无 drop target（拖拽到底部无响应；用右键 / ⌘⇧T 替代）
5. 拖拽过程中终端区域出现视觉 drop 反馈（系统默认高亮即可）

单元测试：ShellEscape 已有 10 个测试覆盖转义逻辑，不新增。

### V2：变化事件时间分组

手动验证：
1. 在终端 `touch foo.txt` → 变化面板「刚刚」组出现 foo.txt
2. 等待 1 分钟 → foo.txt 移入「5 分钟内」组
3. 重新打开 App → 历史事件按「今天」/「更早」分组
4. 空分组不显示
5. 每个分组可折叠/展开，默认全展开

单元测试：时间分组纯函数 `ChangeEvent.grouped(events:relativeTo:)` — 4 个用例（刚刚/5 分钟内/今天/更早 边界）。

### V3：变化类型过滤

手动验证：
1. 面板顶部有 segmented control：全部 / 新增 / 修改 / 删除
2. 选「新增」→ 只显示 added 事件（图标 + 颜色一致）
3. 选「删除」→ 只显示 deleted 事件
4. 过滤后分组仍正确（如过滤后「刚刚」无事件则该组隐藏）
5. 切换过滤器保持流畅，无闪烁

单元测试：过滤是 trivial 的 `Array.filter`，不单独测。

### V4：变化条目点击定位

手动验证：
1. 点击一条变化条目（新增/修改类型）→ 文件浏览器跳转到该文件所在目录并选中该文件
2. 如果已在该目录 → 不重复 navigate，直接选中
3. 点击一条 deleted 条目 → 跳转到该文件原所在目录（文件不存在则仅跳转，不选中）
4. 点击后搜索栏如果开启则关闭（避免搜索过滤导致定位的文件不可见）
5. 文件浏览器滚动到选中行可见

单元测试：`WorkspaceModel.navigateAndSelect(path:)` — 2 个用例（文件存在 → selectedURLs 被设置；文件不存在 → selectedURLs 为空）。

### V5：文件列表变化标记

手动验证：
1. 在终端 `touch newfile.txt` → 文件列表中 newfile.txt 名称列左侧出现绿色小圆点
2. `echo x >> existing.txt` → existing.txt 出现橙色小圆点
3. 30 秒后圆点自动消失（下次 reloadData 时清除过期标记）
4. 圆点颜色与变化面板图标颜色一致（绿=新增，橙=修改）
5. 删除事件不在文件列表标记（文件已不存在）

单元测试：`WorkspaceModel.changeIndicators` 过期清理逻辑 — 1 个用例（插入标记 → 模拟 31 秒后 → 调用清理 → 标记消失）。

## 最脆弱假设

**SwiftUI `.onDrop` 修饰符在 `TerminalPanelView`（NSViewRepresentable 包裹 GhosttySurfaceView）上能正常接收 file URL drop。**

依据：`GhosttySurfaceView` 未调用 `registerForDraggedTypes`，不会抢占 drag destination。SwiftUI 的 `.onDrop` 在 hosting 层注册 drag types，与内部 NSView 不冲突。如果实测发现 libghostty 内部注册了 drag destination（可能性低——它不处理文件拖放），退路是在 `ContentView` 用一个覆盖在终端上方的透明 drop zone overlay。

## 技术方案

### Part 1：文件列表拖拽源

`FileTableView.Coordinator` 实现 `NSTableViewDataSource` 的 pasteboard writer 方法，使文件行可拖出：

```swift
func tableView(_ tableView: NSTableView,
               pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
    guard row < items.count else { return nil }
    return items[row].url as NSURL
}
```

`NSURL` 已遵循 `NSPasteboardWriting`，自动写入 `NSPasteboard.PasteboardType.fileURL`。无需额外代码。

### Part 2：终端 drop target

在 `ContentView` 中，给终端面板添加 SwiftUI `.onDrop` 修饰符：

```swift
TerminalPanelView(cwd: model.currentURL, engine: terminalEngine)
    .frame(height: model.isTerminalVisible ? terminalHeight : 0)
    .clipped()
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        handleTerminalDrop(providers)
    }
```

`handleTerminalDrop` 从 providers 提取 file URLs → `ShellEscape.escapeMultiple` → `terminalEngine.writeText`。

终端隐藏时（height: 0 + clipped），用户拖不到该区域，天然不触发——无需额外守卫。

### Part 3：变化事件时间分组

在 `ChangeEvent.swift` 中新增时间分组枚举和纯函数：

```swift
enum ChangeTimeGroup: CaseIterable {
    case justNow    // < 60s
    case fiveMin    // 60s ~ 5min
    case today      // 5min ~ 今日结束
    case earlier    // 昨日及更早

    var label: String { ... }
}

extension ChangeEvent {
    static func grouped(_ events: [ChangeEvent],
                         relativeTo now: Date = .init())
        -> [(group: ChangeTimeGroup, events: [ChangeEvent])]
    {
        // 按 timestamp 降序已保证，分桶后保持组内顺序
        // 空桶不返回
    }
}
```

`relativeTo` 参数支持单测注入固定时间。

### Part 4：ChangeListView 重写

替换当前平铺 List 为分组 + 过滤结构：

```swift
struct ChangeListView: View {
    let events: [ChangeEvent]
    var onNavigate: ((ChangeEvent) -> Void)?

    @State private var filter: ChangeEventType? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 过滤器
            FilterBar(filter: $filter)

            // 分组列表
            let filtered = events.filter { ... }
            let groups = ChangeEvent.grouped(filtered)
            List {
                ForEach(groups, id: \.group) { section in
                    Section(section.group.label) {
                        ForEach(section.events) { event in
                            ChangeRow(event: event)
                                .contentShape(Rectangle())
                                .onTapGesture { onNavigate?(event) }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
```

`FilterBar` 是一个简单的 HStack + Button/Picker（segmented 风格），4 个选项。选中态用高亮色。

`ChangeRow` 保持现有行样式（type icon + fileName + relative time），外加整行可点击。

### Part 5：变化条目点击定位

`WorkspaceModel` 新增方法：

```swift
func navigateAndSelect(path: String) {
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()

    if isSearching {
        isSearching = false
        searchQuery = ""
    }

    if dir.standardizedFileURL != currentURL.standardizedFileURL {
        navigate(to: dir)
    }

    let exists = FileManager.default.fileExists(atPath: path)
    selectedURLs = exists ? [url] : []
}
```

`ContentView` 把 `onNavigate` 接线到 model：

```swift
ChangeListView(events: model.changes) { event in
    model.navigateAndSelect(path: event.path)
}
```

注意：navigate 后需要 `FileTableView` 滚动到选中行。当前 `updateNSView` 的 `pendingRenameURL` 逻辑已有 scroll 到行的模式，新增一个类似的 `pendingSelectURL` 触发 scroll 即可，或复用 `selectedURLs` 配合一个 `scrollToSelection` flag。

更简方案：在 `updateNSView` 中检测 `selectedURLs` 变化后 `scrollRowToVisible`。当前 `updateNSView` 有 `itemsChanged` 守卫，需在 selection 变化时也触发 scroll。通过新增 `scrollToURL: URL?` 属性传递，`updateNSView` 检测后滚动并清空。

### Part 6：文件列表变化标记

`WorkspaceModel` 新增：

```swift
private(set) var changeIndicators: [String: ChangeEventType] = [:]  // path → type
private var indicatorTimers: [String: Timer] = [:]
```

在 `handleFSEvents` 中，每个事件设置 indicator 并启动 30s 定时清除：

```swift
private func handleFSEvents(_ events: [(path: String, type: ChangeEventType)]) {
    let dir = currentURL.path(percentEncoded: false)
    let batch = events.map { (path: $0.path, type: $0.type, directory: dir) }
    try? changeStore?.recordBatch(batch)

    for event in events {
        if event.type != .deleted {
            changeIndicators[event.path] = event.type
            indicatorTimers[event.path]?.invalidate()
            indicatorTimers[event.path] = Timer.scheduledTimer(
                withTimeInterval: 30, repeats: false
            ) { [weak self] _ in
                self?.changeIndicators.removeValue(forKey: event.path)
                self?.indicatorTimers.removeValue(forKey: event.path)
            }
        }
    }

    reload()
}
```

`FileTableView` 新增属性：

```swift
var changeIndicators: [String: ChangeEventType]
```

`Coordinator` 在 `tableView(_:viewFor:row:)` 的 name column 中，判断 `changeIndicators[item.url.path(percentEncoded: false)]`，如有则在 icon 左侧渲染 6×6 圆形色点（green = added, orange = modified）。

名称列 cell 布局从 `icon → text` 变为 `dot(6×6, optional) → icon(16×16) → text`：

```swift
// makeCell 中增加可选的 indicator dot
let dot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
dot.wantsLayer = true
dot.layer?.cornerRadius = 3
dot.identifier = NSUserInterfaceItemIdentifier("changeDot")
dot.isHidden = true
cell.addSubview(dot)
```

`tableView(_:viewFor:row:)` 中查找 dot view 并设置可见性和颜色。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `FileWorkspace/FileTableView.swift` | ① Coordinator 实现 `pasteboardWriterForRow`（拖拽源）；② name column cell 增加 change indicator dot；③ 新增 `changeIndicators` 属性 + `scrollToURL` 属性；④ `updateNSView` 增加 scroll-to-selection 逻辑 |
| `ChangeJournal/ChangeEvent.swift` | 新增 `ChangeTimeGroup` 枚举 + `ChangeEvent.grouped` 纯函数 |
| `ChangeJournal/ChangeListView.swift` | 重写：filter bar + 时间分组 sections + 行点击回调 |
| `FileWorkspace/WorkspaceModel.swift` | ① 新增 `changeIndicators` + timer 逻辑；② 新增 `navigateAndSelect(path:)` 方法；③ `handleFSEvents` 中填充 indicators |
| `ContentView.swift` | ① 终端面板加 `.onDrop`；② ChangeListView 接线 `onNavigate`；③ FileTableView 传 `changeIndicators` + `scrollToURL` |

## 不改动

| 文件 | 理由 |
|---|---|
| `Terminal/GhosttySurfaceView.swift` | 不注册 drag destination，不改动 |
| `Terminal/TerminalEngine.swift` | 协议不变，`writeText` S9 已有 |
| `Terminal/GhosttyTerminalEngine.swift` | 不变 |
| `Terminal/TerminalPanelView.swift` | 不变（drop 在 ContentView 层处理） |
| `FileWorkspace/ShellEscape.swift` | 不变，复用 |
| `ChangeJournal/ChangeStore.swift` | 不变，查询接口已满足 |
| `ChangeJournal/FSWatcher.swift` | 不变 |
| `PathDeckApp.swift` | 不变（无新菜单命令） |

## Scope

- 文件列表行可拖出（pasteboard writer with file URL）
- 终端面板 drop target（SwiftUI `.onDrop`）→ shell-escape → `writeText`
- 变化面板时间分组（刚刚 / 5 分钟内 / 今天 / 更早）
- 变化面板类型过滤（全部 / 新增 / 修改 / 删除）
- 变化条目点击 → 文件浏览器定位
- 文件列表名称列变化标记（色点，30 秒淡出）

## Non-scope

- 终端隐藏时拖拽自动展开终端（当前 height:0 无 drop target，用 ⌘⇧T 替代）
- 从 Finder 拖文件到终端面板（只支持从本 App 文件列表拖出；Finder 跨 App 拖拽后续增量）
- 变化事件聚合/去重（如 1 秒内同文件多次 modified → 合并，后续）
- Terminal cwd 追踪与同步（FR-BRIDGE-004，S11）
- 多 Terminal Tab（FR-TERM-003，S11）
- Diff / before-after 视图（FR-CHANGE-005，后续）
- 变化面板折叠/展开状态持久化
- 变化忽略规则（FR-CHANGE-007，后续）

## 实现顺序

1. `ChangeEvent.swift` — 新增 `ChangeTimeGroup` + `grouped` 纯函数 + 单测
2. `ChangeListView.swift` — 重写：filter bar + 分组 sections + 行点击回调
3. `WorkspaceModel.swift` — 新增 `changeIndicators` + timer 清理 + `navigateAndSelect`
4. `FileTableView.swift` — pasteboard writer + change dot + scrollToURL
5. `ContentView.swift` — `.onDrop` + ChangeListView 接线 + FileTableView 新属性传递
6. build + 全量单测 + 新增单测（分组 ×4 + navigateAndSelect ×2 + indicator 过期 ×1）
7. GUI 走查（5 组验证标准）
8. 更新 `ChangeJournal/AGENTS.md` + `FileWorkspace/AGENTS.md` + 根 `AGENTS.md` 变更日志

## 工作量

0 个新文件 + 5 个改动文件 + 3 个文档更新，~250 行新代码 + ~7 个新增单测。
