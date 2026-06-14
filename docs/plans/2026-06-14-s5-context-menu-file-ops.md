# S5：右键菜单 + 文件操作

> 日期：2026-06-14　需求：context-menu-file-ops（M1 切片 S5）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s4-path-nav-sort-hidden.md`。

## 背景定位（M1 进行中）

M0 全部完成，M1（Finder-first MVP）已交付 S4（路径导航 + 排序 + 隐藏文件）。当前文件列表能浏览、排序、导航，但不能对文件执行任何操作——用户需要切到 Finder 才能删除、重命名、新建文件夹。S5 的目标是把文件列表从"只能看"升级为"能操作"，补齐 M1 验收标准中的"常见文件操作稳定"。

涉及 PRD 功能项：FR-FILE-002（右键菜单 / Rename / New Folder / Move to Trash / Reveal in Finder / Open With）。

## 目标与验证标准

六项能力，全部可手动验证：

### 1. 右键菜单

手动验证：
- 单选一个文件 → 右键 → 弹出菜单，包含：打开 / 用其他应用打开… / 移到废纸篓 / 重命名 / 在 Finder 中显示 / 复制路径
- 多选三个文件 → 右键 → 弹出菜单，菜单项适配多选（"重命名"灰掉，其余正常）
- 右键空白区域 → 弹出菜单，仅显示"新建文件夹"
- 目录项右键 → 菜单与文件基本相同，但"打开"改为"进入文件夹"

### 2. Open / Open With…

手动验证：
- 右键文件 → 打开 → 用默认应用打开（等效双击）
- 右键文件 → 用其他应用打开… → 弹出系统 Open With 面板 → 选择应用后成功打开
- 多选文件 → 打开 → 批量用各自默认应用打开

### 3. Move to Trash

手动验证：
- 右键文件 → 移到废纸篓 → 文件消失，Finder 废纸篓中出现该文件
- ⌘⌫ 快捷键 → 选中文件移到废纸篓
- 多选文件 → 移到废纸篓 → 全部进废纸篓
- 废纸篓操作后底部 ChangeJournal 面板出现对应 deleted 事件（FSWatcher 自动感知，无需额外代码）

### 4. Rename

手动验证：
- 右键文件 → 重命名 → 文件名列进入编辑态（光标闪烁、文字可选可改）
- 选中文件后按 Enter（或 Return）→ 进入编辑态
- 输入新名称后按 Enter → 文件名更新，列表刷新后仍选中该文件
- 按 Esc → 取消编辑，恢复原名
- 输入已存在的文件名 → 编辑取消，提示重名（NSAlert 或系统 beep）
- 多选状态下右键 → "重命名"菜单项禁用

### 5. New Folder

手动验证：
- 右键空白区域 → 新建文件夹 → 在当前目录创建"未命名文件夹"（若已存在则加数字后缀）
- ⌘⇧N 快捷键 → 同上
- 新文件夹创建后自动选中并进入重命名状态
- ChangeJournal 面板出现 created 事件

### 6. Reveal in Finder

手动验证：
- 右键文件 → 在 Finder 中显示 → Finder 激活并高亮该文件
- 多选文件 → 在 Finder 中显示 → Finder 高亮所有选中文件

## 技术方案

### 右键菜单：NSTableView `menu` 属性 + Coordinator 构建

NSTableView 的右键菜单通过设置 `tableView.menu` + 实现 `NSMenuDelegate.menuNeedsUpdate(_:)` 来动态构建。Coordinator 在 menu 弹出前根据点击位置（`tableView.clickedRow`）和当前选择（`tableView.selectedRowIndexes`）决定菜单内容。

点击行为规则（Finder 一致）：
- 右键点击已选中行 → 保持多选，菜单作用于所有选中项
- 右键点击未选中行 → 清除旧选择，选中该行，菜单作用于该行
- 右键点击空白区域（`clickedRow == -1`）→ 清除选择，只显示"新建文件夹"

菜单结构：

```
文件右键（单选）：
  打开                    ⏎
  用其他应用打开…
  ──────────
  重命名
  移到废纸篓              ⌘⌫
  ──────────
  在 Finder 中显示
  复制路径
  ──────────
  新建文件夹              ⌘⇧N

目录右键（单选）：
  进入文件夹              ⏎
  用其他应用打开…
  ──────────
  重命名
  移到废纸篓              ⌘⌫
  ──────────
  在 Finder 中显示
  复制路径
  ──────────
  新建文件夹              ⌘⇧N

多选右键：
  打开
  ──────────
  移到废纸篓              ⌘⌫
  ──────────
  在 Finder 中显示
  复制路径
  ──────────
  新建文件夹              ⌘⇧N

空白区域右键：
  新建文件夹              ⌘⇧N
```

### Open / Open With…

- Open：`NSWorkspace.shared.open(item.url)`
- Open With：`NSWorkspace.shared.open([url], withApplicationAt:, configuration:)` 通过先弹出 `NSOpenPanel`（过滤 `.app`，起始目录 `/Applications`）让用户选应用。或者更简单地用 `NSSharingServicePicker` / 直接 `NSWorkspace.shared.open` 的 completion-based API。最简方案：调用 `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` 前用 `NSOpenPanel` 选 .app。

### Move to Trash

`FileManager.default.trashItem(at:resultingItemURL:)`——系统 API，自动放入废纸篓、支持 Put Back。批量操作逐个调用。FSWatcher 会感知文件消失事件，自动写入 ChangeJournal，无需额外联动代码。

操作后调用 `reload()` 刷新列表。

快捷键 ⌘⌫：在 `PathDeckApp.swift` 的 `ViewCommands` 中添加。需要 `@FocusedValue` 取选中文件。

### Rename

NSTableView 内置 inline editing 支持：
1. 让 name 列的 `NSTextField` 可编辑（`isEditable = true`）
2. 触发编辑：`tableView.editColumn(_:row:with:select:)`
3. 编辑完成：`controlTextDidEndEditing(_:)` 回调（`NSControlTextEditingDelegate`），在此调用 `FileManager.moveItem(at:to:)` 执行重命名
4. 取消编辑：用户按 Esc 时 `NSTextField` 自动还原 `stringValue`

Enter 键触发编辑而非双击进入目录：当前 Enter 无绑定（双击走 `doubleAction`），需在 Coordinator 中监听 `keyDown` 或通过 `NSTableView` 子类 / `NSResponder` 链处理。最简方案：在菜单命令中添加 Enter 快捷键触发 rename action（通过 responder chain 找到 table view + 当前选中行）。

重名检测：`moveItem` 抛错时 catch，`NSSound.beep()` 提示。

### New Folder

`FileManager.default.createDirectory(at:withIntermediateDirectories:false)`。

命名策略：从"未命名文件夹"开始，存在时追加" 2"、" 3"…（Finder 行为）。

创建后 `reload()` 刷新，选中新文件夹行，立即触发 rename 进入编辑态。

### Reveal in Finder

`NSWorkspace.shared.activateFileViewerSelecting([url])`——支持多选。

### 选中文件的路径传递

当前 `WorkspaceModel` 缺少选中文件的概念。需要新增：

```swift
var selectedURLs: [URL] = []
```

`FileTableView` 新增 `onSelectionChange: ([FileItem]) -> Void` 回调，`Coordinator` 在 `tableViewSelectionDidChange(_:)` 中触发。`WorkspaceModel` 更新 `selectedURLs`。

右键菜单和快捷键操作都基于 `selectedURLs`。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `FileTableView.swift` | 右键菜单（`NSMenu` + `NSMenuDelegate`）；name 列 `NSTextField` 可编辑 + `controlTextDidEndEditing`；`onSelectionChange` 回调；Enter 键触发 rename |
| `WorkspaceModel.swift` | `selectedURLs` 属性；`openItems()` / `openWith()` / `trashItems()` / `renameItem(from:to:)` / `newFolder()` / `revealInFinder()` 方法 |
| `ContentView.swift` | 传 `onSelectionChange` 给 FileTableView |
| `PathDeckApp.swift` | `ViewCommands` 新增 ⌘⌫ 移到废纸篓 + ⌘⇧N 新建文件夹菜单项 |

## 不改动

| 文件 | 理由 |
|---|---|
| `FileItem.swift` | 无需新字段 |
| `DirectoryLister.swift` | 无需改动 |
| `ChangeJournal/*` | FSWatcher 自动感知文件变化，无需额外联动 |
| `Terminal/*` | 无关 |

## Scope

- NSTableView 右键菜单（单选 / 多选 / 空白区域三种状态）
- Open（默认应用）/ Open With…（NSOpenPanel 选 .app）
- Move to Trash（⌘⌫）
- Rename（Enter 触发 inline editing）
- New Folder（⌘⇧N，创建后自动 rename）
- Reveal in Finder
- Copy Path（已有快捷键，补入右键菜单）
- 选中文件状态跟踪（`selectedURLs`）

## Non-scope

- 批量重命名（Finder 的 Rename X Items…）——M1 后续或 P2
- 拖拽排序 / 拖拽移动文件——独立切片
- 文件复制 / 粘贴（⌘C ⌘V）——独立切片
- 文件 info / Get Info 面板——独立切片
- 右键菜单中的 Quick Look 预览——预览切片
- 撤销操作（⌘Z 撤销 Trash / Rename）——P2

## 验证

- 自动：`WorkspaceModel` 的 `newFolder` 命名策略可单测（"未命名文件夹" → "未命名文件夹 2" → …）。
- 构建：Debug/Release clean build 通过。
- GUI 冒烟：人工在 Xcode 走查上述 6 组验收标准。

## 工作量

4 个文件改动，~400-500 行新/改代码。

## 实现顺序

1. `WorkspaceModel` 新增 `selectedURLs` + 文件操作方法（`openItems` / `trashItems` / `renameItem` / `newFolder` / `revealInFinder`）+ newFolder 命名策略单测
2. `FileTableView` 新增 `onSelectionChange` 回调 + `tableViewSelectionDidChange` 实现
3. `FileTableView` 右键菜单（`NSMenu` + `menuNeedsUpdate`）+ 菜单 action 分发
4. `FileTableView` name 列 inline editing（`isEditable` + `controlTextDidEndEditing` + Enter 键触发）
5. `ContentView` 接入 `onSelectionChange`
6. `PathDeckApp.swift` 新增 ⌘⌫ / ⌘⇧N 菜单命令
7. clean build + 单元测试 + GUI 走查
