# AGENTS.md — Settings

> 应用偏好设置界面（SwiftUI `Settings` scene）。本文就近覆盖根 `AGENTS.md`。

## 职责

终端外观/行为偏好的可视化设置面板。系统 ⌘, 打开。左分类（Appearance / Terminal）右详情，Warp 式语义小节。所有控件绑 `Terminal/TerminalPreferences.shared`。**热重载分层**（ghostty 库限制）：字号/光标/copy-on-select 实时作用于活动终端（不重建）；字体族/样式/连字/thicken/non-ASCII 字体/边距/透明度/scrollback/shell 仅新建终端生效——各 Section footer 已如实标注。

## 目录结构

- `SettingsView.swift` — `Settings` scene 根：`NavigationSplitView` 左侧分类列表（`SettingsCategory`：appearance/terminal，各带 SF Symbol）+ 右侧详情，固定 660×460
- `AppearanceSettingsTab.swift` — 外观面板：Font（「Select…」拉起系统 `NSFontPanel` 选字体族+样式 + 字号 stepper 8–32 + 字形样张 + 连字开关 + Anti-aliased 开关）+ Non-ASCII Font（独立字体 toggle + Select… 面板）+ Cursor（bar/block/underline）+ Window（padding/opacity/blur）。`FontPanelDelegate` 桥接 `NSFontManager` target/action，`changeFont(_:)` 按 activeTarget 写回 `fontFamily`/`fontStyle`/`fontSize` 或 `nonASCIIFontFamily`
- `TerminalSettingsTab.swift` — 终端面板：Shell（picker + Custom 自定义路径，空 = 系统默认）+ Behavior（copy-on-select）+ Scrollback（行数滑块，写 conf 时换算字节）

## 模块规范

- 控件统一绑 `TerminalPreferences.shared`（`@Observable` + `@Bindable`）；改值经 `didSet` 持久化，外观项额外 post `.terminalAppearanceDidChange` 触发热重载。
- **不 `import GhosttyKit`**：外观透传/热重载由 `Terminal` 模块经 runtime.conf + ghostty config 完成，本目录只产生偏好变更。
- 新增用户可见字符串走 `Localizable.xcstrings`（en + zh-Hans），未译时 SwiftUI 回退英文 key。

## 依赖关系

依赖 `Terminal/TerminalPreferences`（偏好单实例）。被 `PathDeckApp` 的 `Settings { SettingsView() }` scene 挂载。

## 变更日志

- 2026-06-26 S34 字体配置增强：移除主题选择画廊（`ThemeGalleryView.swift` 删除），内置 Monokai Pro Light 固定配色（硬编码到 `TerminalConfigWriter`）。删除 `ThemePreset.swift`（`ThemePreset` / `BuiltInThemes` 不再需要）。`AppearanceSettingsTab` 重构：字体选择从精选 9 个等宽字体 Picker 改为系统 `NSFontPanel`（`FontPanelDelegate` 桥接，字体族+样式一并选取）+ Use Ligatures 开关（`font-feature = -calt/-liga`）+ Anti-aliased 开关（`font-thicken`）+ Non-ASCII Font section（`font-codepoint-map = U+0080-U+FFFF`，独立 NSFontPanel 入口）。
- 2026-06-25 S33 Terminal Appearance：从单 420×320 `TerminalSettingsTab` 升级为左分类右详情双面板（Appearance / Terminal）。新增 `AppearanceSettingsTab`（主题画廊 + 字体/字号/cursor + padding/opacity/blur）+ `ThemeGalleryView`（6 套内置主题缩略图画廊 + 实时套用）。`TerminalSettingsTab` 收缩为 Shell + Behavior(copy-on-select) + Scrollback。偏好从裸 `@AppStorage` 三键迁入 `TerminalPreferences` 单例。
