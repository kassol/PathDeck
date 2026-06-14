# S6：Quick Look 预览（空格键）

> 日期：2026-06-14　需求：quick-look-preview（M1 切片 S6）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s5-context-menu-file-ops.md`。

## 背景定位（M1 进行中）

M1 验收标准："可以作为轻量 Finder 替代使用 30 分钟以上"。当前文件列表已能浏览、导航、排序、操作（S1–S5），但不能预览——用户选中图片/PDF/代码后必须双击用外部应用打开才能看内容。空格键预览是 Finder 最高频交互之一，缺失严重影响 M1 验收体验。

涉及 PRD 功能项：FR-PREVIEW-002（Quick Look 集成，P0）。

FR-PREVIEW-001（内嵌 Preview Pane 侧栏预览）和 FR-PREVIEW-003（预览内容发送 Terminal）不在本切片范围。

## 目标与验证标准

一项能力：空格键触发系统 Quick Look 面板预览选中文件。

### 1. 空格键预览

手动验证：
- 选中一个图片文件 → 按空格 → 弹出 Quick Look 面板，显示图片预览
- 选中一个 PDF → 按空格 → Quick Look 面板显示 PDF 内容
- 选中一个文本/代码文件 → 按空格 → Quick Look 面板显示文本内容
- Quick Look 面板已打开时按空格 → 面板关闭
- Quick Look 面板打开时切换选中文件 → 面板内容跟随切换
- 多选文件 → 按空格 → Quick Look 面板显示第一个，可用箭头切换
- 选中目录 → 按空格 → Quick Look 面板显示目录信息（系统默认行为）

## 技术方案

### QLPreviewPanel：系统 Quick Look API

macOS 提供 `QLPreviewPanel`（Quartz 框架），是 Finder 空格键预览的同一套机制。集成方式：

1. **空格键触发**：`FileNSTableView.keyDown` 拦截空格键（keyCode 49），调用 `QLPreviewPanel.shared.toggle()`（面板已打开则关闭，未打开则打开）。

2. **数据源**：Coordinator 遵循 `QLPreviewPanelDataSource`，提供：
   - `numberOfPreviewItems(in:)` → 当前选中文件数
   - `previewPanel(_:previewItemAt:)` → 返回选中文件的 URL（`URL` 已遵循 `QLPreviewItem`）

3. **委托**：Coordinator 遵循 `QLPreviewPanelDelegate`，实现：
   - `previewPanel(_:handle:)` → 返回 true 表示本面板处理该事件
   - `previewPanel(_:sourceFrameOnScreenFor:)` → 返回选中行在屏幕上的 frame（面板弹出/关闭时的缩放动画锚点）

4. **面板所有权**：`FileNSTableView` 覆写 `acceptsPreviewPanelControl(_:)` 返回 true，`beginPreviewPanelControl(_:)` 和 `endPreviewPanelControl(_:)` 设置/清除 panel 的 dataSource + delegate。这是 QLPreviewPanel 的标准所有权协议——面板会沿 responder chain 找第一个 `acceptsPreviewPanelControl` 返回 true 的 view。

5. **选择变化刷新**：`tableViewSelectionDidChange` 中，如果 QLPreviewPanel 已打开（`QLPreviewPanel.sharedPreviewPanelExists && QLPreviewPanel.shared.isVisible`），调用 `QLPreviewPanel.shared.reloadData()` 刷新预览内容。

### 关键实现细节

- `import QuickLookUI`（AppKit 的 Quick Look UI 框架）
- `URL` 自身遵循 `QLPreviewItem`（`previewItemURL` 返回自身），无需包装类
- 源 frame 动画：通过 `tableView.frameOfCell(atColumn:row:)` 取名称列单元格 frame，再 `convert(_:to: nil)` 转为窗口坐标，最后 `window.convertToScreen(_:)` 转为屏幕坐标
- 多选时 `numberOfPreviewItems` 返回选中数量，用户可在 Quick Look 面板内用左右箭头翻页

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `FileTableView.swift` | `FileNSTableView` 添加空格键处理 + QLPreviewPanel 所有权方法；Coordinator 遵循 `QLPreviewPanelDataSource` + `QLPreviewPanelDelegate`；`tableViewSelectionDidChange` 添加 QL 刷新 |

## 不改动

| 文件 | 理由 |
|---|---|
| `WorkspaceModel.swift` | 无需新状态，QL 只读取已有 `selectedURLs` |
| `ContentView.swift` | 无需新接口 |
| `PathDeckApp.swift` | 无需新菜单命令（空格键在 view 层处理） |
| `FileItem.swift` | 无需新字段 |
| `ChangeJournal/*` | 无关 |
| `Terminal/*` | 无关 |

## Scope

- 空格键打开/关闭 QLPreviewPanel
- 选中文件切换时 QL 面板跟随刷新
- 多选文件时 QL 面板支持箭头翻页
- 弹出/关闭动画锚定选中行

## Non-scope

- 内嵌 Preview Pane 侧栏（FR-PREVIEW-001）——独立切片，更大
- 预览内容发送到 Terminal（FR-PREVIEW-003）——依赖 Terminal 集成
- 自定义预览渲染（Markdown 渲染、代码高亮）——系统 QL 已覆盖大部分格式
- 缩略图列（文件列表内联缩略图）——独立切片

## 验证

- 自动：无需新单测——QLPreviewPanel 是系统 API 的纯胶水，逻辑集中在 keyDown 分发和数据源接口，无可测业务逻辑。
- 构建：Debug/Release clean build 通过。
- GUI 冒烟：人工在 Xcode 走查上述 7 条验收标准。

## 工作量

1 个文件改动，~60-80 行新代码。

## 实现顺序

1. `FileNSTableView` 添加空格键 keyDown 处理（toggle QLPreviewPanel）
2. `FileNSTableView` 覆写 `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl`
3. Coordinator 遵循 `QLPreviewPanelDataSource`（基于 `selectedURLs` 提供 items）
4. Coordinator 遵循 `QLPreviewPanelDelegate`（源 frame 动画）
5. `tableViewSelectionDidChange` 中添加 QL 面板刷新
6. clean build + GUI 走查
