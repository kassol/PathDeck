# S33 Terminal Appearance + Hot Reload — 傻瓜化主题画廊 + 实时切换

> 日期：2026-06-25
> 前置：S32 NSWindow Tabbing（工作区实现中，建立 `WorkspaceController` per-window + `WorkspacePreferences` 单例 + app 级单实例 `GhosttyTerminalEngine`）
> 触发：Sir「终端配置项尽可能傻瓜化 + 美观」，参考 `nowledge-co/con-terminal`（同 libghostty 后端，已实现主题画廊 + 实时预览）与 `manaflow-ai/cmux`（同 Swift+GhosttyKit 栈，专家配置隔离 + 控件范式）

## 一句话

把终端外观从「编译内置默认 + 裸 `@AppStorage` 三键、仅 2 项生效」升级为「内置主题 preset 画廊 + 字体/字号/padding/透明度，全部经 ghostty 配置文件透传、改即热重载到所有活动终端不丢 scrollback」。

## 关键澄清（与 Sir 的决策锚定）

- **D-Sir-1 主题形态**：首发只做内置 preset 画廊（4–6 套，随系统明暗各配深浅），逐项自定义调色 → 二期。
- **D-Sir-2 不要文本编辑器**：砍掉「Open Ghostty Config 裸文本编辑器」逃生口。专家项里只把 **cursor 样式**提升为干净下拉（`con` 把 cursor 列为其持久化 4 核心字段之一）；逐项 16 色 / 行距 / ligature / TERM 不做 GUI。
- **D-Sir-3 一并修死设置 + 统一偏好基础设施**：scrollback 当前有 UI 但完全不透传（死设置）本期修活；三个裸 `@AppStorage` key 迁入 `@Observable` 单例机制。
- **D-Sir-4 热重载**：改设置即时作用于已存在的终端 tab，不重建 surface（保住 scrollback / PTY / cwd / shell 会话）。

## 承重前提（已对 PathDeck 自带 vendor 库一手 nm 核实，含一处修正）

| 事实 | 证据 |
|---|---|
| **热重载可行，零项需重建 surface**：`ghostty_surface_update_config(surface, cfg)` 把新 config 应用到活动 surface，libghostty 内部 diff 重算字体/网格/色彩/透明度并 reflow，不销毁 PTY | `vendor/GhosttyKit.xcframework/macos-arm64/Headers/ghostty.h:1109`；`ghostty-internal.a` nm 显示 `T` 已定义。`con-ghostty terminal.rs:845`、`cmux GhosttyApp+SurfaceConfigurationReload.swift:9` 同栈生产验证 |
| **全局热更新**：`ghostty_app_update_config(app, cfg)` 更新 app 级默认（影响后续新建 surface 继承基线） | `ghostty.h:1096` |
| **⚠️ 修正**：本 xcframework **不导出** `ghostty_config_set(key,value)` / `load_string` 逐键内存写入（grep count=0 + nm 不存在）。之前方案稿假设的「逐键 set」对这份 vendor 库不成立 | grep/nm 双核实；`surface_config_s` 结构体除 `font_size`(`ghostty.h:472`) 外无任何外观字段 |
| **唯一构造路径**：把外观序列化成 ghostty 配置文件文本 → `ghostty_config_new()` → `ghostty_config_load_file(path)` → `ghostty_config_finalize()`。`con`/`cmux` 都走「写 .conf 文件 → load_file」 | `ghostty.h:1070/1074/1077` |
| **xcframework 不含 themes 资源**：不能用 `theme = Dracula` 引用内置主题名，必须 Swift 端把 ThemePreset 展开成显式 `background`/`foreground`/`palette = N=hex` 等键值 | `Terminal/AGENTS.md:36`「预编译 xcframework 不含 zig-out 的 terminfo / shell-integration / themes」 |

最脆弱假设：**libghostty `Surface.updateConfig` 对字体 reflow 绝不重建 PTY**。`con` 与 `cmux` 两个同栈生产实现均依赖此行为，可信度高，但未在 PathDeck 亲跑通 → P1 列为强制手动验收（切字体后 `ps` 对比 shell PID + scrollback 历史保留）。若证伪，退路是 if/else 销毁重建 NSView（丢全部 scrollback、shell 被杀重启、cwd 靠 OSC7 恢复），必须向用户明确标注「会话历史将清空」——本方案默认完全避免这条退路。

## 现状锚点

| 维度 | 现在 | 改后 |
|---|---|---|
| 生效的终端设置 | 仅 shell（`GhosttySurfaceView.swift:212,224`）、字号（`:209` surface_config_s.font_size） | shell + 字号 + 主题 + font-family + padding + 透明度 + 模糊 + cursor + scrollback，全部经 runtime.conf 透传 |
| scrollback | UI 有（`TerminalSettingsTab.swift:49-61`，默认 10000）但**无任何 ghostty 消费**（死设置） | 写 `scrollback-limit = N` 到 runtime.conf，经 update_config 生效 |
| 主题/配色 | 无，走 libghostty 编译默认；全局 config 句柄空白（`GhosttyApp.swift:58-62` new→finalize 之间无 load） | 内置 `ThemePreset` 画廊；全局 config init 时 `load_file(runtime.conf)`，改设置时 reload + 广播 |
| 偏好持久化 | 裸 `@AppStorage("terminalShell"/"terminalFontSize"/"terminalScrollback")` + `enum TerminalDefaults` 读 UserDefaults（`TerminalSettingsTab.swift:4-6,84-109`） | 新增 `TerminalPreferences` `@Observable` 单例（同 `WorkspacePreferences.swift:6-65` 的 didSet→persist 范式），裸 key 退役 |
| Settings 窗口 | `SettingsView` 单嵌 `TerminalSettingsTab`，固定 420×320 无分类（`SettingsView.swift:3-8`） | 左分类（Appearance / Terminal）右详情，Warp 式语义小节 |
| 设置生效范围 | 仅新建 tab（`TerminalSettingsTab.swift:64`「apply to new terminal tabs」） | 即时热重载到全部活动 surface |
| 外观真值来源 | 创建 surface 时一次性读 `TerminalDefaults`（`GhosttySurfaceView.swift:209,212`） | 单一真值 = runtime.conf（由 `TerminalConfigWriter` 从 `TerminalPreferences` 序列化）；新建与热重载共用同一份 |

## 技术决策

| # | 决策 | 理由 |
|---|------|------|
| D1 | 透传走「写 runtime.conf 文件文本 → `ghostty_config_load_file`」，不走逐键 set | 本 vendor xcframework 不导出 `ghostty_config_set`/`load_string`（已 nm 核实）；`con`/`cmux` 同款路线 |
| D2 | runtime.conf 落 `NSTemporaryDirectory()/PathDeck/runtime.conf`，固定路径覆写，单写者（主线程） | 无需锁；load_file 失败时旧 config 句柄保持上次 finalize 态，update_config 用旧值不崩、外观不变（静默降级，不丢会话） |
| D3 | 单一真值函数：`TerminalConfigWriter.write(from: TerminalPreferences, theme: ThemePreset)` 产出全部外观键值；新建 surface 与热重载共用 | 避免「创建时设一套、热重载设另一套」的双真值；`GhosttySurfaceView.swift:209` 的 per-surface `font_size` 快路退役，font-size 改由 runtime.conf 承载（新 surface 经全局 config 继承） |
| D4 | `GhosttyApp` init 改为 `config_new → load_file(runtime.conf) → finalize → app_new`；新增 `reloadConfig(fromFile:)` + `applyConfig(to surface:)` | init 前先 `TerminalConfigWriter.writeCurrent()` 保证文件存在；reload 重建 config 句柄、`app_update_config`、swap `self.config`（free 旧）；applyConfig 对单 surface 调 `surface_update_config(surface, self.config)`。`self.config`(`GhosttyApp.swift:26`)/`self.app`(`:25`) 句柄复用 |
| D5 | 热重载广播：`TerminalPreferences` didSet → post `.terminalAppearanceDidChange`（纯 Foundation 通知）→ `GhosttyTerminalEngine` 观察 → 写 conf → `GhosttyApp.reloadConfig` → 遍历 `surfaceViews`(`GhosttyTerminalEngine.swift:11`) 逐个 `applyConfig(to:)` → setNeedsDisplay | 保持协议边界：`TerminalPreferences`（Workspace 域）不 import GhosttyKit，只发通知；C 符号仍限 `GhosttyApp`/`GhosttySurfaceView`（`Terminal/AGENTS.md:32`）。engine 已是 app 级单实例且已有通知观察范式（`:23-27`） |
| D6 | 主题 = Swift 端 `ThemePreset`（id/name/isDark/background/foreground/cursorColor/palette[16] 全 hex）+ `serialize()` 展开成 `background`/`foreground`/`cursor-color`/`palette = N=#hex`×16 配置行 | xcframework 无 themes 资源，不能引用主题名；preset 直接灌显式颜色键值 |
| D7 | **偏好归属**：新增 `TerminalPreferences` 单例（sibling，非塞进 `WorkspacePreferences`） | `WorkspacePreferences` 是文件工作区布局（sort/hidden/panel）；终端外观是独立关注点，分立避免单类膨胀，同时仍统一到 `@Observable + didSet→persist` 机制（满足 D-Sir-3）。Sir 已确认 |
| D8 | cursor 样式 = 下拉（Bar/Block/Underline 三选），写 `cursor-style = X` | D-Sir-2 砍文本编辑器后 cursor 提升为 GUI 专家项（`con` 核心 4 字段之一）。Sir 已确认 |
| D11 | copy-on-select 开关，写 `copy-on-select = true`，经 update_config 热重载 | Sir 确认加入；终端常见预期，单 toggle，Terminal/Behavior 小节 |
| D9 | shell-integration 开关**不做**，保持当前始终开启 | 它是 PTY-spawn 时的 env 注入（`GhosttySurfaceView.swift:215` + `ShellIntegration.envVars`），无法热重载（只能新 tab 生效），与 D-Sir-4 热重载语义冲突；且非外观项。本期出 scope |
| D10 | 明暗自适应：随系统 light/dark 切换 preset，额外同步 `ghostty_app_set_color_scheme` + `ghostty_surface_set_color_scheme`（`ghostty.h:1099/1121`，仅切枚举，辅助） | D-Sir-1「随系统明暗各配深浅」；主题色仍靠 update_config，set_color_scheme 不能应用任意 palette |

## Scope

每个 Phase 独立可合并：P1 单独落地即修复 scrollback 死 bug + font-size 热重载；P2 加主题画廊；P3 补其余外观项 + 美化布局。

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| **P1** | Feat/Fix | **透传 + 热重载地基 + 修 scrollback**（UI 暂不变）。新增 `TerminalPreferences` 单例（迁 shell/fontSize/scrollback 三键，裸 `@AppStorage` 退役）；`TerminalConfigWriter`（序列化 → runtime.conf，含 `font-size`/`scrollback-limit`）；`GhosttyApp` init 加 `load_file` + 新增 `reloadConfig`/`applyConfig`；`GhosttyTerminalEngine` 观察 `.terminalAppearanceDidChange` 写 conf + 广播；`GhosttySurfaceView.swift:209` per-surface font_size 退役 | `PathDeck/Terminal/TerminalPreferences.swift`（新）, `PathDeck/Terminal/TerminalConfigWriter.swift`（新）, `PathDeck/Terminal/GhosttyApp.swift`, `PathDeck/Terminal/GhosttyTerminalEngine.swift`, `PathDeck/Terminal/GhosttySurfaceView.swift`, `PathDeck/Settings/TerminalSettingsTab.swift`（读改 TerminalPreferences） |
| **P2** | Feat | **主题画廊 + 设置重构**。`ThemePreset` 模型 + `serialize()` + `BuiltInThemes` 目录（4–6 套，明暗成对）；`SettingsView` 重构左分类（Appearance / Terminal）右详情；Appearance/Theme 小节缩略图卡片画廊（迷你终端样张 + 选中 accent 边框 + 实时预览）；主题选择经 D5 链路热重载 | `PathDeck/Terminal/ThemePreset.swift`（新）, `PathDeck/Settings/SettingsView.swift`, `PathDeck/Settings/AppearanceSettingsTab.swift`（新）, `PathDeck/Settings/ThemeGalleryView.swift`（新）, `PathDeck/Terminal/TerminalConfigWriter.swift`（加颜色键序列化） |
| **P3** | Feat | **其余外观/行为控件**。Text&Font 小节：font-family（picker + 字形样张 `AaBb 0O1lI`）+ font-size（滑块 + 等宽读数 + 默认值时禁用 Reset，范式抄 cmux）+ cursor 下拉。Size&Opacity 小节：window-padding（单滑块 x=y）+ background-opacity（滑块）+ blur（开关）。Terminal/Behavior 小节：copy-on-select 开关。全部经 runtime.conf + 热重载 | `PathDeck/Settings/AppearanceSettingsTab.swift`, `PathDeck/Terminal/TerminalPreferences.swift`（加 fontFamily/padding/opacity/blur/cursorStyle/copyOnSelect 属性）, `PathDeck/Terminal/TerminalConfigWriter.swift` |

## 透传 + 热重载机制（落地细节）

**单一真值链路（新建与热重载共用）：**

```
TerminalPreferences.shared（fontFamily/fontSize/padding/opacity/blur/cursor/scrollback/activeThemeID）
        │  + BuiltInThemes[activeThemeID] → ThemePreset（bg/fg/cursor/palette[16] hex）
        ▼
TerminalConfigWriter.write()  →  序列化为 ghostty 配置文本：
        theme 行: background = 1e1e2e / foreground = cdd6f4 / cursor-color = f5e0dc
                  palette = 0=#45475a ... palette = 15=#a6adc8   (16 行)
        排版行: font-family = SF Mono / font-size = 13 / cursor-style = bar
                window-padding-x = 8 / window-padding-y = 8
                background-opacity = 1.0 / background-blur-radius = 20
        行为行: scrollback-limit = 10000 / copy-on-select = true
        ▼  写 NSTemporaryDirectory()/PathDeck/runtime.conf（覆写）
        ▼
GhosttyApp.reloadConfig(fromFile:)
        cfg = ghostty_config_new(); ghostty_config_load_file(cfg, path); ghostty_config_finalize(cfg)
        ghostty_app_update_config(app, cfg)          // 全局默认（新 surface 继承基线）
        free 旧 self.config; self.config = cfg
        ▼
GhosttyTerminalEngine：for view in surfaceViews.values
        GhosttyApp.shared.applyConfig(to: view.surface)   // ghostty_surface_update_config(surface, self.config)
        view.setNeedsDisplay(view.bounds)                 // 触发重绘
```

**启动路径**：`GhosttyApp.init` 在 `ghostty_config_new()` 前先 `TerminalConfigWriter.writeCurrent()` 保证 runtime.conf 存在，`config_new → load_file(runtime.conf) → finalize → app_new(&runtime, config)`（`GhosttyApp.swift:58-62,112-118` 现有序列里插入 load_file 一行）。新建 surface 经全局 config 继承外观，`GhosttySurfaceView.swift:209` 的 `config.font_size` 退役（font-size 由 runtime.conf 承载）。

**hex 格式实测点**（P2 开工首步）：ghostty `palette = N=#RRGGBB` / `background = RRGGBB` 接受形态先写一行试跑确认（`#` 前缀有无），再批量序列化。

## 验证

**自动（单测，临时目录隔离）：**
- `TerminalConfigWriterTests`：给定 `TerminalPreferences` + `ThemePreset` → `write()` 产出的 conf 文本逐行格式正确（font-size / scrollback-limit / palette×16 / opacity 等键值）；写入临时目录可读回。
- `TerminalPreferencesTests`：didSet→persist 往返（同 `WorkspacePreferencesTests` 范式）；缺省值（fontSize=13/scrollback=10000/opacity=1.0）；迁移旧裸 key 读取兼容。
- `ThemePresetTests`：`serialize()` 16 色 palette 行齐全、明暗 preset isDark 正确、`BuiltInThemes` id 唯一。
- `GhosttyTerminalEngine` 广播：`.terminalAppearanceDidChange` 触发对全部 `surfaceViews` 调用 applyConfig（用 spy/桩 surface 断言命中计数，脱离 libghostty）。

**手动走查（程序测不到的视觉/进程行为，逐条 操作→预期）：**
1. 开 2 个终端 tab，各 `ls` 产生滚动历史 → 设置切主题 → **预期**：两个 tab 颜色即时变，scrollback 历史保留，无闪烁重建。
2. 切字体/字号 → **预期**：字符重排（一次 reflow 重绘），`ps` 对比 shell PID 不变、scrollback 不丢（**承重假设验收点**）。
3. 拖 opacity 滑块 → **预期**：终端背景实时透明度变化（窗口需半透明 backing，`GhosttySurfaceView.swift:56-61` 已预留）。
4. 主题画廊：hover/点击卡片 → **预期**：选中卡 accent 边框 + 卡内迷你样张反映该 preset 配色。
5. 改 scrollback 上限后跑 `seq 1 20000` → **预期**：可回滚行数符合新上限（修复死设置验收）。

## 实现修正（落地核实）

本稿设计阶段假设全部外观项热重载。落地时经 ghostty 库 config 文档 strings 一手核实，**热重载分层**：仅主题/字号/光标/copy-on-select 实时作用于已开终端；font-family/padding/scrollback/shell 仅新建终端生效，background-opacity macOS 注解需重启 Ghostty。设置面板 Section footer 已按此标注。权威矩阵见 `PathDeck/Terminal/AGENTS.md` S33 条目。

## 风险 / 未验证

- **承重假设**：libghostty `Surface.updateConfig` 字体 reflow 不重建 PTY——P1 手动走查 2 验收；证伪则退 NSView 重建（标注会话清空），不作默认。
- **hex 接受形态**：`#RRGGBB` vs `RRGGBB` 需 P2 首步实测，未实测前不批量。
- **runtime.conf 并发**：单写者固定路径覆写，load_file 失败静默降级（旧 config 不崩、外观不变）。
- **opacity 模糊依赖窗口 backing**：透明生效需窗口 `isOpaque=false`（已有预留），若 S32 NSWindow 改造影响 backing 需复查。

## 收尾（实现后）

- 更新 `PathDeck/Terminal/AGENTS.md` 变更日志（S33 透传/热重载机制 + 新文件职责）。
- 新增 `PathDeck/Settings/AGENTS.md`（Settings 目录当前无规范文档，按「约束先行」补结构约定）。
- 更新根 `AGENTS.md` 变更日志 + 目录索引（新增 Terminal 三文件 + Settings 拆分）。
