# S4：路径导航 + 列排序 + 隐藏文件

> 日期：2026-06-14　需求：path-nav-sort-hidden（M1 切片 S4）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s3-fsevents-sqlite.md`。

## 背景定位（M0→M1 过渡）

M0（技术验证）三个切片全部完成：

| 切片 | 内容 | 状态 |
|---|---|---|
| S1 | 启动即家目录 + NSTableView 文件列表 + 进出目录 | ✓ |
| S2 | libghostty 嵌入冒烟 | ✓ |
| S3 | FSEvents 监听 + SQLite 事件写入 | ✓ |

M1（Finder-first MVP）验收标准：「可作为轻量 Finder 替代使用 30 分钟以上」。S4 是 M1 的第一个切片，目标是把文件列表从 demo 提升到基本可用——能排序、能导航、能控制显示范围。

## 目标与验证标准

三项能力，全部可手动验证：

### 1. 路径导航（FR-FILE-004 P0）

手动验证：
- 打开 App → toolbar 下方显示当前路径的面包屑段（如 `~ / Documents / project`）
- 点击 `Documents` → 文件列表跳转到 `~/Documents`
- 点击 `~` → 跳转到家目录
- ⌘⌥C → 当前路径复制到剪贴板

### 2. 列排序（FR-FILE-002 P0）

手动验证：
- 点击「修改日期」列头 → 文件按日期降序排列，列头出现排序指示器
- 再次点击 → 切换为升序
- 点击「大小」列头 → 按大小排序，之前的排序指示器消失
- 切换目录 → 排序偏好保持
- 任何排序下目录始终排在文件前面

### 3. 隐藏文件（FR-FILE-002 P0）

手动验证：
- 默认看不到 `.git` / `.DS_Store` 等 dotfiles
- 按 ⌘⇧. → dotfiles 出现，再按 → 消失
- 切换目录 → 隐藏文件状态保持

## 技术方案

### 路径导航：SwiftUI 面包屑栏

在 `ContentView` 的 toolbar 区域或文件列表上方加一条路径栏。每个路径段是可点击的 Button，用 `/` 或 `chevron.right` 分隔。

实现方式：一个 SwiftUI `HStack`（`ScrollView(.horizontal)`），从根到当前目录的每一级都渲染为一个 Button。点击某段调用 `WorkspaceModel.navigate(to:)`。

```
[ < ] [ ~ ] › [ Documents ] › [ project ]     [复制路径]
```

路径段由 `WorkspaceModel.pathSegments: [(name: String, url: URL)]` 计算属性提供。

当前 `navigationTitle` / `navigationSubtitle` 保留（macOS 窗口标题栏用）；路径栏是文件列表上方的独立 UI 元素。

复制路径：toolbar 按钮或 ⌘⌥C 快捷键，调用 `NSPasteboard.general.setString`。

### 列排序：NSTableView sortDescriptors

标准 AppKit 排序模式：

1. 给每个 `NSTableColumn` 设 `sortDescriptorPrototype`（key = 列 ID，ascending = true）
2. `Coordinator` 实现 `tableView(_:sortDescriptorsDidChange:)` 回调
3. 排序变化时通知 `WorkspaceModel`，由 model 排序 items 后刷新 table

排序逻辑在 `WorkspaceModel` 层：

```swift
enum SortColumn: String { case name, date, size, kind }
var sortColumn: SortColumn = .name
var sortAscending: Bool = true
```

排序规则：
- 始终目录在前、文件在后（Finder 行为）
- 同组内按当前 sort column + direction 排序
- name 排序用 `localizedStandardCompare`（与 Finder 一致：自然排序 + 区域感知）
- date / size 排序对 nil 值排到末尾

`DirectoryLister.list` 当前硬编码「目录优先 + 名称升序」排序。改动：移除 DirectoryLister 内的排序，排序统一由 WorkspaceModel 负责。DirectoryLister 只做枚举，不做排序——职责更清晰。

交互传导：`FileTableView` 需要新增一个 `onSort: (String, Bool) -> Void` 回调，把列 ID 和方向传给 WorkspaceModel。

### 隐藏文件：WorkspaceModel 状态 + ⌘⇧.

`WorkspaceModel` 新增 `showHidden: Bool = false`，传入 `DirectoryLister.list(_, includeHidden:)`。

⌘⇧. 快捷键：在 `ContentView` 的 `.commands` 或 toolbar/menu 中添加。切换 `model.showHidden` 后调用 `model.reload()`。

`DirectoryLister.list` 已有 `includeHidden` 参数（S1 预留），无需改动签名。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `WorkspaceModel.swift` | 新增 `sortColumn` / `sortAscending` / `showHidden` / `pathSegments` 属性；`navigate(to:)` 方法；`reload()` 内加排序逻辑 |
| `FileTableView.swift` | 列加 `sortDescriptorPrototype`；实现 `sortDescriptorsDidChange`；新增 `onSort` 回调 |
| `DirectoryLister.swift` | 移除内部排序（`.sorted` 调用），只做枚举 |
| `ContentView.swift` | 加路径栏 HStack；传 `onSort` 给 FileTableView；⌘⇧. 菜单/快捷键；⌘⌥C 复制路径 |

## 不改动

| 文件 | 理由 |
|---|---|
| `FileItem.swift` | 无需新字段 |
| `ChangeJournal/*` | 无关 |
| `Terminal/*` | 无关 |
| `PathDeckApp.swift` | 无需改动 |

## Scope

- 路径栏可点击导航
- ⌘⌥C 复制当前路径
- 四列可排序（列头点击）
- 排序全程目录在前
- ⌘⇧. 切换隐藏文件

## Non-scope

- 路径栏可编辑输入（跳转到任意路径）——M1 后续切片
- 右键菜单 / 文件操作（Trash / Rename / New Folder）——独立切片
- 前进/后退导航历史——独立切片
- 视图模式切换（列视图 / 图标视图）——M1 P1
- 搜索——独立切片
- 排序偏好持久化到 UserDefaults——可选，当前内存保持足够

## 验证

- 自动：单元测试覆盖 WorkspaceModel 排序逻辑（按名称/日期/大小/类型排序，目录始终在前，nil 值排末尾）。
- 构建：Debug/Release clean build 通过。
- GUI 冒烟：人工在 Xcode 走查上述 3 组验收标准。

## 工作量

4 个文件改动，~150-200 行新/改代码。

## 实现顺序

1. `DirectoryLister` 移除内部排序
2. `WorkspaceModel` 新增排序/隐藏/路径段属性 + 排序逻辑 + `navigate(to:)` + 排序单测
3. `FileTableView` 列 sortDescriptor + `sortDescriptorsDidChange` + `onSort` 回调
4. `ContentView` 路径栏 + ⌘⇧. 快捷键 + ⌘⌥C 复制路径 + 接入 `onSort`
5. clean build + 单元测试 + GUI 走查
