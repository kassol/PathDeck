# S13：Window Layout Skeleton

> 日期：2026-06-15　需求：window-layout-skeleton
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s12-multi-terminal-tab.md`。

## 背景定位

S1–S12 完成了文件工作台（M1）和终端融合（M2）全部功能切片，但窗口骨架始终是一个 VStack：PathBar → FileTableView → (Terminal XOR ChangeList)。终端和变化列表用 `if/else` 互斥——打开终端就看不到文件变化，这与 PRD §7.1 的目标布局差距过大。

S13 搭建窗口布局骨架，解决两个结构性问题：

1. **无 Sidebar**：最近文件夹只在菜单里，无常驻导航入口
2. **Terminal 与 Changes 互斥**：打开终端就丢失变化可见性

## 目标布局

```
┌──────────────────────────────────────────────────────────────┐
│ Toolbar: ↑ | Title & Subtitle          [Search] [Terminal]   │
├────────────┬─────────────────────────────────────────────────┤
│ Sidebar    │ PathBar                                          │
│            ├─────────────────────────────────────────────────┤
│ 最近文件夹  │ FileTableView                                    │
│ ┌────────┐ ├─────────────────────────────────────────────────┤
│ │ ~/Docs │ │ ═══ drag divider ═══                             │
│ │ ~/Down │ │ [Term 1│Term 2│+           变化 (3)│⚙]          │
│ │ ~/Desk │ │ [terminal content / change list content]         │
│ └────────┘ │                                                  │
├────────────┴─────────────────────────────────────────────────┤
└──────────────────────────────────────────────────────────────┘
```

- **Sidebar**：`NavigationSplitView` sidebar 列，标准 macOS 折叠/展开行为
- **底部面板**：Terminal 和 Changes 共存于同一区域，通过统一 tab bar 切换
- **Inspector 区域**：本切片不落地，M4（版本/diff）时加第三列

## 验证标准（5 个验证点）

### V1：Sidebar 基础功能

手动验证：

1. App 启动 → 左侧出现 Sidebar，显示「最近文件夹」section
2. Sidebar 列出 RecentFolders 中的文件夹（最多 10 项），每行显示文件夹图标 + 名称 + 缩略路径
3. 点击某个文件夹 → 文件浏览器导航到该目录
4. Toolbar 自带 sidebar toggle 按钮（NavigationSplitView 标准行为）→ 点击可折叠/展开
5. Sidebar 折叠后主内容区自动扩展

### V2：底部面板 Tab 切换

手动验证：

1. ⌃\` 打开底部面板 → 默认显示 Terminal tab，创建首个终端会话
2. Tab bar 右侧显示「变化」按钮（带变化条目计数 badge）
3. 点击「变化」→ 底部面板内容切换为变化列表（类型过滤 + 时间分组 + 忽略规则齿轮，与之前一致）
4. 点击任意终端 tab → 切回终端视图
5. 切换时互不干扰：终端 shell 会话保活，变化列表过滤器状态保持

### V3：Terminal 与 Changes 共存验证

手动验证：

1. 打开终端，在终端中 `touch newfile.txt`
2. 文件列表出现绿色变化标记色点（同之前）
3. 切到「变化」tab → 看到 newfile.txt 的 added 记录
4. 切回 Terminal tab → shell 会话完整，可继续输入
5. 点击变化条目 → 文件浏览器选中并滚动到该文件

### V4：Bottom Panel 显示/隐藏

手动验证：

1. ⌃\` 隐藏底部面板 → 文件列表扩展占满剩余空间，底部无 Changes 独立区域
2. 再次 ⌃\` → 面板恢复到之前的 tab 和终端会话
3. 拖拽分割线调整面板高度 → 行为同之前
4. 面板隐藏时，文件列表变化标记色点仍工作

### V5：现有功能回归

单元测试：全量 82 个现有测试通过。

手动验证：

1. ⌘O 打开文件夹 → 正常，sidebar 最近文件夹列表同步更新
2. 文件右键菜单（Open/Trash/Rename/New Folder）→ 正常
3. ⌘⇧T 发送路径到终端 → 路径出现在 active terminal tab
4. 拖拽文件到终端面板 → 正常
5. 空格键 Quick Look → 正常
6. ⌘F 搜索 → 正常

## 最脆弱假设

**NavigationSplitView 的 sidebar 不干扰 AppKit NSTableView 的焦点链。**

FileTableView 是 NSViewRepresentable 包 NSTableView，键盘事件（方向键、空格、Enter、⌘⌫）依赖 first responder 链。NavigationSplitView 引入的 sidebar List 可能争夺焦点。实测重点：从 sidebar 点击文件夹导航后，焦点能否正常回到文件列表。

退路：如果 NavigationSplitView 导致焦点混乱，改用 `HSplitView` 手动搭两列，放弃标准 sidebar 自动折叠行为。

## 技术方案

### Part 1：BottomPanelTab 枚举

`ContentView.swift` 顶部新增：

```swift
enum BottomPanelTab: Hashable {
    case terminal
    case changes
}
```

### Part 2：SidebarView

新增 `PathDeck/SidebarView.swift`：

```swift
struct SidebarView: View {
    var recentFolders: [URL]
    var onNavigate: (URL) -> Void

    var body: some View {
        List {
            Section("最近文件夹") {
                if recentFolders.isEmpty {
                    Text("无最近记录")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(recentFolders, id: \.self) { url in
                        SidebarFolderRow(url: url)
                            .contentShape(Rectangle())
                            .onTapGesture { onNavigate(url) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
```

`SidebarFolderRow`（同文件内 private struct）：文件夹系统图标 + 文件夹名 + `abbreviatingWithTildeInPath` 副标题，紧凑单行。

### Part 3：ContentView 外层包 NavigationSplitView

当前 `ContentView.body` 是 `GeometryReader > VStack`。重构为：

```swift
var body: some View {
    NavigationSplitView {
        SidebarView(
            recentFolders: RecentFolders.shared.items,
            onNavigate: { url in
                model.navigate(to: url)
                RecentFolders.shared.add(url)
            }
        )
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
    } detail: {
        GeometryReader { geometry in
            workspaceContent(geometry: geometry)
        }
        .navigationTitle(model.currentURL.lastPathComponent)
        .navigationSubtitle(abbreviatedPath)
        .toolbar { workspaceToolbar }
    }
}
```

`workspaceContent(geometry:)` 提取当前 VStack 的全部内容。

### Part 4：isTerminalVisible → isBottomPanelVisible

`WorkspaceModel.isTerminalVisible` 语义已不准确（底部面板同时承载终端和变化），重命名为 `isBottomPanelVisible`。

影响范围：

| 文件 | 改动 |
|---|---|
| `WorkspaceModel.swift` | 属性重命名 |
| `ContentView.swift` | 所有引用处 |
| `PathDeckApp.swift` | `TerminalCommands` 中的引用 + 菜单文案「切换底部面板」 |

### Part 5：底部面板 Tab 改造

新增状态：

```swift
@State private var activeBottomTab: BottomPanelTab = .terminal
```

底部面板区域重写：

```swift
// 底部面板 divider + tab bar（面板可见时显示）
if model.isBottomPanelVisible {
    TerminalDividerView(
        height: $terminalHeight,
        minHeight: terminalMinHeight,
        maxHeight: geometry.size.height * terminalMaxFraction,
        containerHeight: geometry.size.height
    )

    BottomPanelBar(
        activeTab: $activeBottomTab,
        terminalSessions: $terminalSessions,
        activeTerminalID: $activeTerminalID,
        changeCount: model.changes.count,
        onNewTerminalTab: { createTerminalTab() },
        onCloseTerminalTab: { closeTerminalTab($0) }
    )
}

// Terminal 内容（session 存在时始终在 view tree 中保活）
if !terminalSessions.isEmpty {
    TerminalPanelView(
        activeSessionID: activeTerminalID,
        sessionIDs: Set(terminalSessions.map(\.id)),
        engine: terminalEngine
    )
    .frame(height: model.isBottomPanelVisible && activeBottomTab == .terminal
           ? terminalHeight : 0)
    .clipped()
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        handleTerminalDrop(providers)
    }
}

// Changes 内容（面板可见 + changes tab 活跃时显示）
if model.isBottomPanelVisible && activeBottomTab == .changes {
    ChangeListView(
        events: model.changes,
        hiddenCount: model.hiddenCount,
        onRulesChanged: { model.reload() }
    ) { event in
        let url = URL(fileURLWithPath: event.path)
        if FileManager.default.fileExists(atPath: event.path) {
            model.selectedURLs = [url]
            model.scrollToURL = url
        }
    }
    .frame(height: terminalHeight)
}
```

关键变化：移除原先底部面板隐藏时独立显示 ChangeListView 的 `if !model.isTerminalVisible { ... }` 代码块。变化列表统一在底部面板「变化」tab 中访问。

### Part 6：BottomPanelBar

`ContentView.swift` 内新增 private struct，统一终端 tab 和变化 tab：

```swift
private struct BottomPanelBar: View {
    @Binding var activeTab: BottomPanelTab
    @Binding var terminalSessions: [TerminalSession]
    @Binding var activeTerminalID: UUID?
    var changeCount: Int
    var onNewTerminalTab: () -> Void
    var onCloseTerminalTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if activeTab == .terminal {
                // 终端 tab 活跃：展开 session tabs
                TerminalTabBar(
                    sessions: $terminalSessions,
                    activeID: $activeTerminalID,
                    onNewTab: onNewTerminalTab,
                    onCloseTab: onCloseTerminalTab
                )
            } else {
                // 终端 tab 收起：显示「终端」切换按钮
                Button { activeTab = .terminal } label: {
                    Label("终端", systemImage: "terminal")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }

            Spacer()

            // 变化 tab 按钮（始终可见）
            Button { activeTab = .changes } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                    Text("变化")
                        .font(.system(size: 11))
                    if changeCount > 0 {
                        Text("\(changeCount)")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(activeTab == .changes ? .primary : .secondary)
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(.bar)
    }
}
```

Tab bar 布局：终端 sessions 左对齐（活跃时展开完整 TerminalTabBar，收起时仅显示一个切换按钮），「变化」按钮右对齐（带 count badge）。高度 28pt，与 TerminalTabBar 一致。

### Part 7：⌃\` 行为

逻辑保持不变：

- 面板关闭 → 打开面板 + 若无 terminal session 则创建
- 面板打开 → 关闭面板

打开面板时 `activeBottomTab` 保持上次状态（默认 `.terminal`）。不做特殊切换。

```swift
.onChange(of: model.isBottomPanelVisible) { _, visible in
    if visible && terminalSessions.isEmpty {
        createTerminalTab()
    }
}
```

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `PathDeck/SidebarView.swift` | **新增**：Sidebar 视图 + SidebarFolderRow |
| `PathDeck/ContentView.swift` | **重构**：① 外层包 `NavigationSplitView`；② 新增 `BottomPanelTab` 枚举 + `activeBottomTab` 状态；③ 新增 `BottomPanelBar` private struct；④ 移除 Terminal/Changes 互斥逻辑，改为 tab 切换；⑤ `isTerminalVisible` → `isBottomPanelVisible` |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | `isTerminalVisible` → `isBottomPanelVisible`（属性重命名） |
| `PathDeck/PathDeckApp.swift` | `TerminalCommands`：`isTerminalVisible` → `isBottomPanelVisible` + 菜单文案「切换底部面板」 |

## 不改动

| 文件 | 理由 |
|---|---|
| `Terminal/*`（TerminalEngine / GhosttyTerminalEngine / TerminalPanelView / TerminalTabBar / GhosttySurfaceView / GhosttyApp / TerminalSmokeView / TerminalSession） | 终端模块内部不变，仅被 ContentView 重新组装 |
| `ChangeJournal/*`（ChangeEvent / ChangeStore / ChangeListView / FSWatcher / IgnoreRules） | 变化模块内部不变，ChangeListView 在底部面板中直接复用 |
| `FileWorkspace/*`（FileItem / DirectoryLister / FileTableView / RecentFolders / SearchBarView / ShellEscape） | 文件工作台不变（WorkspaceModel 仅属性重命名） |
| `PathDeckTests/*` | 现有 82 个测试中引用 `isTerminalVisible` 的用例需跟随重命名，但无新测试逻辑 |

## Scope

- `NavigationSplitView` 两列布局（sidebar + detail）
- Sidebar 显示最近打开文件夹，点击导航
- 底部面板 Terminal 和 Changes 共存（tab 切换，非互斥）
- 统一 tab bar：终端 sessions 左侧 + 变化按钮右侧（带 count badge）
- ⌃\` 切换底部面板整体可见性
- 变化列表从独立固定区域移入底部面板「变化」tab
- `isTerminalVisible` → `isBottomPanelVisible` 语义重命名

## Non-scope

- Inspector / Preview 右侧面板（M4 加）
- NavigationSplitView 三列布局（M4 加 inspector 时升级）
- Sidebar 收藏夹 / 标签 / 工作区条目（后续 P1/P2）
- Sidebar 中内嵌变化列表（变化统一在底部面板）
- 底部面板 Terminal + Changes 同时并排显示（后续如有需求再加 split 模式）
- 底部面板 tab 键盘快捷键（⌃1/⌃2 等，后续可加）
- 新增单元测试（本切片是纯视图重组装，无新业务逻辑）


## 实现顺序

1. `WorkspaceModel.swift` — `isTerminalVisible` → `isBottomPanelVisible` 重命名
2. `SidebarView.swift` — 新增 Sidebar 视图 + SidebarFolderRow
3. `ContentView.swift` — 新增 `BottomPanelTab` 枚举 + `BottomPanelBar` 视图
4. `ContentView.swift` — 外层包 `NavigationSplitView`，提取 `workspaceContent`
5. `ContentView.swift` — 移除 Terminal/Changes 互斥逻辑，改为 tab 切换
6. `PathDeckApp.swift` — TerminalCommands 重命名引用 + 菜单文案更新
7. `PathDeckTests` — 跟随重命名（如有引用）
8. build + 全量单测
9. GUI 走查（5 组验证标准）
10. 更新根 `AGENTS.md` 变更日志

## 工作量

1 个新文件 + 3 个改动文件 + 1 个文档更新。~150 行新代码（SidebarView + BottomPanelBar） + ~80 行重组装（ContentView 布局改造）+ ~30 行重命名。
