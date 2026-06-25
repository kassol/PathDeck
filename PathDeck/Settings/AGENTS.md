# AGENTS.md — Settings

> 应用偏好设置界面（SwiftUI `Settings` scene）。本文就近覆盖根 `AGENTS.md`。

## 职责

终端外观/行为偏好的可视化设置面板。系统 ⌘, 打开。左分类（Appearance / Terminal）右详情，Warp 式语义小节。所有控件绑 `Terminal/TerminalPreferences.shared`。**热重载分层**（ghostty 库限制）：主题/字号/光标/copy-on-select 实时作用于活动终端（不重建）；字体族/边距/透明度/scrollback/shell 仅新建终端生效——各 Section footer 已如实标注「Takes effect in new terminals.」。

## 目录结构

- `SettingsView.swift` — `Settings` scene 根：`NavigationSplitView` 左侧分类列表（`SettingsCategory`：appearance/terminal，各带 SF Symbol）+ 右侧详情，固定 660×460
- `AppearanceSettingsTab.swift` — 外观面板：Theme 画廊 + Text&Font（font-family picker + 字形样张 `AaBb 0O1lI` + 字号 stepper 8–32 + cursor 下拉 bar/block/underline）+ Size&Opacity（padding 滑块 0–24 / opacity 滑块 0.5–1.0 / blur 开关）。font-family 在常见等宽字体里筛本机已安装项（`NSFontManager.availableFontFamilies`），空 = 系统默认
- `ThemeGalleryView.swift` — 内置主题缩略图画廊（`LazyVGrid` 自适应卡片）：每卡渲染迷你终端样张（traffic-light 点 + 着色 prompt/ls/git 行 + 16 色 ANSI 色条）+ 选中加 accent 边框/勾选 + 明暗角标；点击 `prefs.activeThemeID = id` 即套用。含 `Color(hex:)` 扩展（`#RRGGBB` → sRGB）
- `TerminalSettingsTab.swift` — 终端面板：Shell（picker + Custom 自定义路径，空 = 系统默认）+ Behavior（copy-on-select）+ Scrollback（行数滑块，写 conf 时换算字节）

## 模块规范

- 控件统一绑 `TerminalPreferences.shared`（`@Observable` + `@Bindable`）；改值经 `didSet` 持久化，外观项额外 post `.terminalAppearanceDidChange` 触发热重载。
- **不 `import GhosttyKit`**：外观透传/热重载由 `Terminal` 模块经 runtime.conf + ghostty config 完成，本目录只产生偏好变更。
- 新增用户可见字符串走 `Localizable.xcstrings`（en + zh-Hans），未译时 SwiftUI 回退英文 key。

## 依赖关系

依赖 `Terminal/TerminalPreferences`（偏好单实例）+ `Terminal/ThemePreset` / `BuiltInThemes`（主题数据）。被 `PathDeckApp` 的 `Settings { SettingsView() }` scene 挂载。

## 变更日志

- 2026-06-25 S33 Terminal Appearance：从单 420×320 `TerminalSettingsTab` 升级为左分类右详情双面板（Appearance / Terminal）。新增 `AppearanceSettingsTab`（主题画廊 + 字体/字号/cursor + padding/opacity/blur）+ `ThemeGalleryView`（6 套内置主题缩略图画廊 + 实时套用）。`TerminalSettingsTab` 收缩为 Shell + Behavior(copy-on-select) + Scrollback。偏好从裸 `@AppStorage` 三键迁入 `TerminalPreferences` 单例。
