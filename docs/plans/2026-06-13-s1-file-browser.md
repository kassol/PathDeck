# S1：启动即家目录的文件浏览

> 日期：2026-06-13　需求：file-browser（M0 切片 S1）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`。

## 背景定位（M0 切片路线）

一次一小步，每步独立可合并、可手动验证。M0（技术验证）拆为三个切片，各自单独出 plan 文件：

| 切片 | 内容 | 状态 | 验证目标 |
|---|---|---|---|
| **S1** | 启动即家目录 + NSTableView 文件列表 + 进出目录 | 已完成 ✓ | 启动看到 `~` 内容，能双击进子目录、返回上级 |
| S2 | libghostty 嵌入冒烟 | 完成 ✓ | build + 单测 + GUI 渲染/键盘回显走查均通过。见 `2026-06-13-s2-libghostty-smoke.md` |
| S3 | FSEvents 监听 demo + SQLite 事件写入 demo | 完成 ✓ | 当前目录文件增删改能写入 SQLite 并刷新列表。见 `2026-06-14-s3-fsevents-sqlite.md` |

S2 排在 S1 之后是风险排序：libghostty 是整个产品最脆弱的假设（"能嵌入并跑起真 PTY"），`vendor/GhosttyKit.xcframework` 已构建但尚未实测嵌入；越早证伪越省。不把它拖到 M1 完整工作台之后。

S1 完成即进入 M1 完整文件工作台（多视图、搜索、右键、预览面板等），那是后续计划。

---

## 目标与验证标准

App 启动直接显示当前用户家目录（`~`）的文件列表，双击文件夹进入、工具栏按钮返回上级。

可验证（手动）：
1. 构建运行 → 窗口直接显示 `/Users/<user>` 的真实内容（不是容器目录）。
2. 列表含名称(带系统图标)、修改日期、大小、类型四列；文件夹排在文件前，按名称排序。
3. 双击任一文件夹 → 列表切换为该目录内容，工具栏路径更新。
4. 点工具栏返回（或 ⌘↑）→ 回到上级目录。

## 前置：关闭 App Sandbox（落实 D1）

当前 app target 两个配置（Debug `BDA2E8912…`、Release `BDA2E8922…`）含 `ENABLE_APP_SANDBOX = YES`、`ENABLE_USER_SELECTED_FILES = readonly`。

改动：
- `ENABLE_APP_SANDBOX = YES → NO`（Debug + Release）
- 移除 `ENABLE_USER_SELECTED_FILES`（sandbox 专用，关 sandbox 后无意义）
- 保留 `ENABLE_HARDENED_RUNTIME = YES`（Developer ID + Notarization 需要）

依据：D1 明确"不走 App Store 沙盒"，理由是 FSEvents 监听任意目录 + PTY + 真 terminal 在 sandbox 下不可行；且本切片"启动即真实 ~"在 sandbox 下不可能（`homeDirectoryForCurrentUser` 会被重定向到容器目录）。此为落实既定决策，非新决策。

无独立 `.entitlements` 文件（`GENERATE_INFOPLIST_FILE = YES`，未引用 `CODE_SIGN_ENTITLEMENTS`），改 build setting 即可。

## Scope

- 读取并展示单个目录一层内容
- 文件夹 / 文件区分、系统图标、四列元数据
- 进入子目录 + 返回上级两个导航动作

## Non-scope（有意推后，非遗漏）

- 错误态 UI（无权限 / 目录读取失败）→ S1 列举失败显示空列表，错误提示留后续切片
- 后台线程列目录 / 大目录性能优化 → 同步在 MainActor 列举，万级目录性能是 M1 验收项
- security-scoped bookmark、记住上次浏览位置 → 启动固定从 `~`，bookmark 持久化留 S3 之后
- 搜索、视图切换、右键菜单、就地重命名、Preview/Changes/Terminal 面板
- 隐藏文件开关 → 默认隐藏

## 文件清单

新建模块目录 `PathDeck/FileWorkspace/`（synchronized group 自动纳入 target，无需改 pbxproj）：

| 文件 | 职责 |
|---|---|
| `FileWorkspace/FileItem.swift` | 单个文件/目录的值类型 model |
| `FileWorkspace/DirectoryLister.swift` | 纯函数式目录枚举服务（可单测，无 UI 依赖） |
| `FileWorkspace/WorkspaceModel.swift` | `@Observable` 状态：当前目录 + items + 导航方法 |
| `FileWorkspace/FileTableView.swift` | `NSViewRepresentable` 包 `NSScrollView`+`NSTableView` |
| `FileWorkspace/AGENTS.md` | 子目录规范（职责/结构/依赖/变更日志） |
| `PathDeckTests/DirectoryListerTests.swift` | `DirectoryLister` 单元测试 |

改动：`PathDeck/ContentView.swift`（装载 `FileTableView` + 工具栏）。`PathDeckApp.swift` 不变。

## 接口契约

`FileItem`：值类型，`Identifiable`（`id = url`）。字段：`url: URL`、`name: String`、`isDirectory: Bool`、`size: Int64?`（目录为 nil）、`modifiedDate: Date?`、`kind: String`（本地化类型描述）。图标按需取（`NSWorkspace.shared.icon(forFile:)`），不进 model。

`DirectoryLister`：
```
struct DirectoryLister {
    func list(_ directory: URL, includeHidden: Bool = false) throws -> [FileItem]
}
```
实现：`FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`，keys = `[.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]`，options = `includeHidden ? [] : [.skipsHiddenFiles]`。排序：目录优先，再 `localizedStandardCompare(name)`。

`WorkspaceModel`：`@Observable final class`。
```
private(set) var currentURL: URL
private(set) var items: [FileItem]
init(root: URL = FileManager.default.homeDirectoryForCurrentUser)
func enter(_ item: FileItem)   // 仅当 isDirectory：currentURL = item.url; reload()
func goUp()                    // parent = currentURL.deletingLastPathComponent()；parent==current 则 no-op
func reload()                  // items = (try? lister.list(currentURL)) ?? []
```

`FileTableView`：`NSViewRepresentable`，入参 `items: [FileItem]`、`onOpen: (FileItem) -> Void`。
- `makeNSView`：`NSScrollView` 容纳 view-based `NSTableView`，四列（name/dateModified/size/kind）。
- name 列 cell = `NSTableCellView`（imageView 图标 + textField 名称）；size 用 `ByteCountFormatter`，date 用 `Date.FormatStyle`。
- `tableView.doubleAction` → Coordinator → `onOpen(items[clickedRow])`。
- `Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate`，持有 items 副本；`updateNSView` 更新 items 并 `reloadData()`。

`ContentView`：
```
@State private var model = WorkspaceModel()
// body: FileTableView(items: model.items, onOpen: { model.enter($0) })
//   .toolbar { 返回上级按钮(model.goUp) + 当前路径文本(model.currentURL.path(abbreviatingWithTilde)) }
//   .frame(minWidth: 720, minHeight: 480)
```

并发说明：工程 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，以上类型默认 MainActor 隔离，同步文件 IO 暂在主线程（小目录可接受）。后续挪后台时按 D2 预留 `Sendable`/actor。

## 测试

`DirectoryListerTests`：在 `FileManager` 临时目录建 2 文件 + 1 子目录，断言：
- `list` 返回 3 项；
- 子目录 `isDirectory == true`、文件 `== false`；
- 文件 `size` 与写入字节数一致、目录 `size == nil`；
- 排序结果首项为目录；
- `includeHidden: false` 时跳过 `.` 前缀文件。

命令（见根 AGENTS.md）：
```
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck test
```

## 回滚

纯新增文件 + `ContentView.swift` 一处改 + 三个 build setting 改动，无外部状态、无数据写入。`git checkout` 工程文件与源码即可完全回退。

## 收尾（实现后）

- 新建 `PathDeck/FileWorkspace/AGENTS.md`
- 更新根 `AGENTS.md`：目录索引补 `FileWorkspace` 与 `docs/plans/`，变更日志记录"关闭 App Sandbox 落实 D1"，技术栈表确认文件列表采用 NSTableView
- 本文件状态表 S1 标记为已完成

---

## 关键决策记录

- **文件列表用 NSTableView 而非 SwiftUI Table**：文件列表是长期核心视图，终局需求（多选 / 拖拽含 file promise / 就地重命名 / type-select / 万级实时增量刷新 / Column 视图）几乎全落在 SwiftUI 结构性弱区，迟早全得落回 AppKit。对终局确定的核心视图，"先快后换"的返工不划算。App 其余部分（toolbar/sidebar/preview/settings/布局壳）仍用 SwiftUI，整体 hybrid。
- **启动即 `~`，无 Welcome / Open Folder**：它首先是 Finder，启动就该在某个目录里。"打开文件夹"是工作区/编辑器心智。直接进 `~` 同时消除了"未打开任何文件夹"的空状态边界。
- **关闭 App Sandbox**：落实 D1。sandbox 阻断真实家目录访问与后续 FSEvents/PTY。
- **S2（libghostty）紧随 S1**：风险排序，最脆弱假设最先证伪。
