# S7：打开任意文件夹 + 文件名搜索

> 日期：2026-06-14　需求：open-folder-search（M1 切片 S7）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s6-quick-look-preview.md`。

## 背景定位（M1 收尾）

M1 验收标准："可以作为轻量 Finder 替代使用 30 分钟以上"。S1–S6 已落地文件浏览、导航、排序、右键操作、Quick Look，但有两个关键缺口：

1. **无法打开任意目录**——当前 app 启动锁定在 `~`，只能往下钻、往上跳。用户无法指定 `/Volumes/外置盘` 或 `~/Projects/foo` 作为起始目录。这是 FR-FILE-001（P0）的核心要求。
2. **无法搜索文件名**——M1 范围明确列出"搜索文件名"。目录内数十上百个文件时，缺少搜索是严重体验缺失。这是 FR-SEARCH-001（P0）。

两项合计改动量可控，合并为一个切片交付。完成后 M1 全部 scope 闭合。

## 目标与验证标准

### 1. 打开任意文件夹（FR-FILE-001）

手动验证：
- File > Open…（⌘O）→ 弹出 NSOpenPanel（仅选目录）→ 选择目录 → 文件列表切换到该目录
- File > Open Recent → 显示最近打开的目录列表（最多 10 项）→ 点击条目跳转
- 从 Finder 拖文件夹到 app 窗口 → 切换到该目录
- 打开不可读目录 → 列表为空，不崩溃（现有 `DirectoryLister` 的 `try?` 已覆盖）
- 重启 app → 恢复上次打开的目录（`NSDocument` 的 restore 不用；用 UserDefaults 记上次路径）

单元测试：
- `RecentFoldersTests`：添加 / 去重 / 上限截断 / 持久化读写

### 2. 文件名搜索（FR-SEARCH-001）

手动验证：
- ⌘F 或点击 toolbar 搜索图标 → toolbar 下方出现搜索栏（NSSearchField）
- 输入关键词 → 文件列表实时过滤，仅显示文件名包含关键词的条目（大小写不敏感）
- 清空搜索框 → 恢复完整文件列表
- Esc → 关闭搜索栏，恢复完整列表
- 搜索状态下切换目录 → 清空搜索词，显示新目录完整内容
- 搜索状态下切换隐藏文件 → 搜索词保留，结果刷新
- 搜索空目录 → 显示空列表，不崩溃

单元测试：
- `SearchFilterTests`：精确匹配 / 子串匹配 / 大小写不敏感 / 空关键词返回全量 / 中文文件名匹配 / 目录与文件均可匹配

## 技术方案

### Part 1：打开任意文件夹

#### 1a. File > Open…（⌘O）

在 `PathDeckApp.swift` 的 `FileCommands` 中添加 `CommandGroup(replacing: .newItem)` 里的 Open 按钮（替换默认 New 组）。点击时调用 `WorkspaceModel.openFolder()`，内部：

```swift
func openFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    navigate(to: url)
    RecentFolders.shared.add(url)
}
```

⌘O 快捷键通过 `.keyboardShortcut("o")` 绑定。现有 `CommandGroup(after: .newItem)` 的"新建文件夹"保持不变——改为放在 `replacing: .newItem` 内部一起，避免两个 group 交叉。

#### 1b. 最近打开列表

新建 `RecentFolders.swift`（放 `FileWorkspace/`），职责：

- 维护最近 10 个目录 URL 的有序列表（最新在前）
- 添加时去重（已存在则提到最前）
- UserDefaults 持久化（key: `recentFolders`，存 `[String]` 路径数组）
- `shared` 单例

菜单：`FileCommands` 添加一个动态子菜单 "Open Recent"，遍历 `RecentFolders.shared.items` 生成 Button 列表 + 底部 "Clear Menu" 按钮。

#### 1c. 启动恢复上次目录

`WorkspaceModel.init()` 读 UserDefaults `lastOpenedFolder`；`navigate(to:)` 每次成功导航时写入。无值时仍默认 `~`。

#### 1d. 拖放文件夹

`ContentView` 的根 `VStack` 添加 `.onDrop(of: [.fileURL], ...)` 修饰器。仅接受单个 `isDirectory` URL，调用 `model.navigate(to:)` + `RecentFolders.shared.add()`。

### Part 2：文件名搜索

#### 2a. 搜索状态

`WorkspaceModel` 新增：

```swift
var searchQuery: String = ""
var isSearching: Bool = false
```

修改 `items` 的暴露方式：当前 `reload()` 把 `DirectoryLister.list()` 结果排序后直接赋给 `items`。改为：
- 新增 `private(set) var allItems: [FileItem] = []`（完整列表）
- `items` 改为计算属性或在 `reload()` / `searchQuery` didSet 中重新计算：

```swift
// reload() 末尾
allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
applySearch()

// searchQuery didSet → applySearch()
private func applySearch() {
    if searchQuery.isEmpty {
        items = allItems
    } else {
        items = allItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}
```

`navigate(to:)` 中清空 `searchQuery` 和 `isSearching`。
`toggleHidden()` 和 `applySort()` 后重新 `applySearch()`。

#### 2b. 搜索栏 UI

`ContentView` 在 `PathBarView` 和 `FileTableView` 之间，条件显示搜索栏：

```swift
if model.isSearching {
    SearchBarView(query: Binding(
        get: { model.searchQuery },
        set: { model.searchQuery = $0 }
    ), onDismiss: {
        model.isSearching = false
        model.searchQuery = ""
    })
}
```

`SearchBarView`：一个包含 `NSSearchField` 的 `NSViewRepresentable`（用 AppKit 的 `NSSearchField` 而非 SwiftUI `TextField`，因为 NSSearchField 自带取消按钮、搜索图标、Esc 清除行为，与 Finder 一致）。
- 出现时自动 `becomeFirstResponder`
- 实时回调 `controlTextDidChange` → 更新 binding
- Esc（`cancelOperation`）→ 调 `onDismiss`

高度固定 28pt，背景 `.bar`，与 PathBarView 视觉一致。

#### 2c. 快捷键

`ViewCommands` 或 `FileCommands` 中添加 ⌘F → `model.isSearching = true`。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `PathDeckApp.swift` | FileCommands 改为 `replacing: .newItem`（Open + New Folder），添加 Open Recent 子菜单；ViewCommands 添加 ⌘F 搜索命令 |
| `WorkspaceModel.swift` | 新增 `searchQuery` / `isSearching` / `allItems`；`reload()` 增加 `applySearch()` 调用；`navigate(to:)` 清空搜索态 + 写 UserDefaults；`init()` 读 `lastOpenedFolder`；`openFolder()` 方法；`applySort()` / `toggleHidden()` 后重新 `applySearch()` |
| `ContentView.swift` | 条件插入 `SearchBarView`；根 VStack 添加 `.onDrop` 接收文件夹拖放 |
| **新增** `FileWorkspace/RecentFolders.swift` | 最近文件夹管理（UserDefaults，10 项上限） |
| **新增** `FileWorkspace/SearchBarView.swift` | NSSearchField 的 NSViewRepresentable 包装 |

## 不改动

| 文件 | 理由 |
|---|---|
| `FileTableView.swift` | 搜索过滤在 model 层完成，table view 只反映 `items` 变化 |
| `DirectoryLister.swift` | 无需变更，枚举逻辑不变 |
| `FileItem.swift` | 无需新字段 |
| `ChangeJournal/*` | 无关 |
| `Terminal/*` | 无关 |

## Scope

- ⌘O 打开任意目录（NSOpenPanel）
- Open Recent 子菜单（最多 10 项 + Clear）
- 启动恢复上次目录
- 拖放文件夹到窗口
- ⌘F 搜索栏（NSSearchField），文件名实时过滤（`localizedCaseInsensitiveContains`）
- Esc 关闭搜索栏

## Non-scope

- 内容搜索（FR-SEARCH-002，P1）——依赖 Spotlight / FTS，独立切片
- 变化搜索（FR-SEARCH-003，P1）——依赖 ChangeJournal 索引
- 按类型/大小/时间过滤（FR-SEARCH-001 验收标准中的附加项）——本切片只做文件名过滤，过滤条件后续增量添加
- 最近搜索记录（FR-SEARCH-001 验收标准中的附加项）——M1 不需要
- Security-scoped bookmark（D1 决策提到的目录授权持久化）——当前非沙盒模式无此需求，沙盒化时再加
- 多窗口多工作区——当前单窗口，后续独立切片
- Sidebar（收藏/最近/标签）——独立切片，M1 后

## 验证

- 自动：`RecentFoldersTests`（添加/去重/上限/持久化）+ `SearchFilterTests`（匹配逻辑 6 例）
- 构建：Debug/Release clean build 通过
- GUI 冒烟：人工走查上述 12 条验收标准

## 工作量

2 个新文件 + 3 个改动文件，~200 行新代码。

## 实现顺序

1. `RecentFolders.swift`——最近文件夹管理 + 单测
2. `WorkspaceModel` 添加 `openFolder()` / `lastOpenedFolder` 恢复 / `searchQuery` / `allItems` / `applySearch()`
3. `SearchBarView.swift`——NSSearchField 包装
4. `ContentView` 插入搜索栏 + 拖放
5. `PathDeckApp.swift` 菜单改造（Open / Open Recent / ⌘F）
6. 单测 `SearchFilterTests`
7. pbxproj `membershipExceptions` 检查（新文件无 AGENTS.md 冲突，应不需要）
8. clean build + GUI 走查
