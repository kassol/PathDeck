# AGENTS.md — PathDeck

> macOS 原生文件工作台。本文件是根级工作约束；子目录 AGENTS.md 就近覆盖本文。
> 开工前先读：本文件 + 相关子目录 AGENTS.md + `docs/prd.md`。

## 项目概述

PathDeck 是一个 Finder-first 的 macOS 文件工作台：以文件浏览为主心智，需要命令行时就地长出真 Terminal，文件系统变化通过 FSEvents 实时感知并刷新列表。

三大支柱：

1. Finder-like 文件工作台（浏览 / 预览 / 搜索 / 路径导航）
2. 内嵌 libghostty 真 Terminal（经 `TerminalEngine` 协议隔离）
3. Context Bridge（文件 ↔ Terminal 双向上下文桥）

完整产品定义见 `docs/prd.md`（v0.2 Draft，产品来源；M3/M4 已标注 Killed，以代码现实为准）。

明确不做（定位边界，违反即偏离产品本质）：

- 不做 Agent Runtime / Agent Profile，保持 agent-agnostic
- 不向用户暴露 Git / branch / worktree 心智
- 不做 coding IDE、不做跨平台、不做 Electron

## 技术栈

| 模块 | 选型 | 备注 |
|---|---|---|
| 主 App | Swift + AppKit + SwiftUI | macOS 原生体验、拖拽、权限 |
| 文件列表 | AppKit `NSTableView` / `NSOutlineView` / `NSCollectionView` | 大目录性能与复杂选择 |
| Terminal | libghostty（Zig 构建，C API） | 见「libghostty 集成风险」|
| Terminal 抽象 | `TerminalEngine` protocol | 隔离 libghostty API 变动 |
| 文件监听 | FSEvents | 当前目录变化实时刷新 |
| 搜索 | Spotlight | |
| 预览 | Quick Look / PDFKit / AVKit | |
| 分发 | Developer ID + Notarization | 见决策 D1 |

环境基线：

- 部署目标 macOS 26.5（见 D3）
- 工程 `SWIFT_VERSION = 5.0`（语言模式；本机编译器 Swift 6.3.2）（见 D2）
- Bundle ID：`in.riverflows.PathDeck`
- URL Scheme：`pathdeck://`
- 芯片：Apple Silicon（arm64）

## 目录索引

`FileWorkspace` 已完成 M1 全部 scope（S1–S7）+ S9 Send Path to Terminal + S10 拖拽到终端 + S16 Preview Pane（右侧文件预览/元数据/Quick Actions）+ FSWatcher（FSEvents 实时监听当前目录文件变化 → reload 列表）；`Terminal` 已完成 S2 冒烟 + S8 面板嵌入主窗口 + S9 文本注入 + S12 多 Terminal Tab（独立 PTY/cwd/scrollback，tab bar 切换/新建/关闭/重命名）+ S16 cwd 同步（OSC 7 → `GHOSTTY_ACTION_PWD` → tab bar 显示当前 cwd + 点击跳转文件浏览器）+ S23 VerticalTerminalTabBar（Terminal-first 模式垂直 Tab 列表）+ S27 Terminal Input Compat（完整键盘/鼠标/IME/剪贴板事件处理，对齐标准终端）。S13 窗口布局骨架：NavigationSplitView 两列（sidebar + detail）+ 底部面板 Terminal。S16 新增 Settings 窗口（Terminal shell/font/scrollback）+ Pinned 升级为 bookmark data 持久化。S17 窗口状态恢复（底部面板/预览面板/排序/terminal tabs 全持久化，重启恢复上次工作场景）+ `writeText` 竞态修复（pending buffer + `onSurfaceReady`）+ 1k/10k 文件性能自动基线（cold-open/sort/filter）。S18 系统入口（M5 Phase 2）：`pathdeck://` URL Scheme + Finder Services + 文件夹「打开方式」三类外部入口经 `AppRouter` 归一到导航，单实例复用。S19–S21 质量加固：终端 writeText 竞态收口（`PendingTextBuffer` 上限 + surface 失败回调 + 多 tab 退出全关）。S22 CLI helper（`pathdeck` 命令行工具，构造 `pathdeck://` URL 经 `/usr/bin/open` 唤起 App，嵌入 app bundle Resources + "Install Command Line Tool…" 菜单安装到 `/usr/local/bin/`）。M5 闭合。D1 Dogfood：移除 Change Journal 全栈（UI + SQLite + 版本快照 + 终端归因 + Diff），FSWatcher 迁入 FileWorkspace/ 简化为纯信号通知，移除 GRDB 依赖。S23 文件 Tab + Terminal-first 模式：FileTab 多目录并行 + TabManager 状态管理 + anchor cwd 一对多绑定 + Finder-first/Terminal-first per-tab 双模式 + ⌘W NSEvent local monitor 三层优先级。S26 目录就地折叠/展开：NSTableView→NSOutlineView 迁移 + OutlineDataSource 树状数据层 + FileNode 引用包装 + FSWatcher 多目录匹配。S25 i18n 多语言支持：`Localizable.xcstrings` String Catalog（en + zh-Hans），73 条目全量本地化。S24 UX Polish：文件列表列宽自适应（lastColumnOnlyAutoresizing）+ 垂直 tab bar 分隔线可拖动（100–300pt，持久化）+ 终端 tab 标题跟随 OSC title 自动更新（手动重命名优先、清空恢复）+ 移除 Reveal in Finder（替换为 Copy Path）。

```
PathDeck/                  App 源码
PathDeck/PathDeckApp.swift @main（Window scene 单窗口，防 WindowGroup 重复开窗）+ AppDelegate（kAEGetURL 拦截 URL Scheme + application(_:open:) Open With + Services 注册）
PathDeck/ContentView.swift NavigationSplitView 主布局 + FileTabBar + 双模式布局（Finder-first/Terminal-first）+ VerticalDividerView（垂直 tab bar 拖动分隔线）+ NSEvent local monitor ⌘W（终端焦点关终端/多 Tab 关 Tab/单 Tab 关窗口）+ 消费 AppRouter
PathDeck/FileTab.swift     FileTab 值类型（id/title/mode/isTerminalVisible/anchorCwd/terminalSessionIDs）+ FileTabState（Codable 持久化）
PathDeck/TabManager.swift  @Observable 多 Tab 状态管理：FileTab CRUD + WorkspaceModel 多实例 + 终端 session per-tab 绑定 + anchor cwd 生命周期 + 全局偏好（sort/showHidden）+ per-tab 双模式 + 持久化
PathDeck/FileTabBar.swift  横向文件 Tab bar UI（28pt，切换/新建/关闭/重命名）
PathDeck/SidebarView.swift Sidebar（Favorites + Pinned）+ PinnedFolders bookmark 持久化
PathDeck/AppRouter.swift   外部入口（URL Scheme/Services/Open With）归一中介，@Observable 一次性令牌
PathDeck/URLSchemeHandler.swift  pathdeck:// 解析 + 安全校验（查询参数式，目录/存在性校验）
PathDeck/ServicesProvider.swift  Finder Services @objc handler（NSPasteboard → AppRouter.Route）
PathDeck/CLIInstaller.swift "Install Command Line Tool…" 菜单逻辑（原子 replace 到 /usr/local/bin/ + shell-escaped sudo 提示）
PathDeck/Info.plist        URL Scheme / NSServices / CFBundleDocumentTypes / 单实例（synchronized group 排除，靠 INFOPLIST_FILE 引用）
CLI/                       pathdeck 命令行工具 target（pathdeck-cli，product name: pathdeck）
CLI/main.swift             CLI 入口：解析参数 → CLICommand.parse → /usr/bin/open pathdeck://
CLI/CLICommand.swift       参数解析 + URL 构造纯函数（synchronized group 同时编译到 PathDeck app target 供单测，main.swift 经 membershipExceptions 排除）
PathDeck/FileWorkspace/    文件工作台模块（目录浏览、列表视图、Preview Pane、FSWatcher），见其 AGENTS.md
PathDeck/Terminal/         内嵌 libghostty 真终端模块（多 Tab + TerminalEngine 协议 + cwd 同步），见其 AGENTS.md
PathDeck/Settings/         Settings 窗口（Terminal 偏好设置）
PathDeck.xcodeproj/        Xcode 工程
PathDeckTests/             单元测试
PathDeckUITests/           UI 测试
vendor/                    第三方二进制（GhosttyKit.xcframework，不进 git，按 libghostty recipe 重建）
docs/prd.md                产品需求文档（权威产品定义）
docs/design.md             UI 设计系统与原型参考（视觉权威，从 design/ 设计稿抽取）
docs/plans/                开发计划，按 `YYYY-MM-DD-<需求名>.md` 每需求一份
design/                    设计稿源文件（standalone HTML，可浏览器打开看可视参考），不进 build
```

规划模块（落地时各自补一份子目录 AGENTS.md）：`ContextBridge` / `Extensions`（`FileWorkspace`、`Terminal` 已落地；`ChangeJournal` 已在 D1 Dogfood 中移除）。

### Sidebar 扩展路线

当前 Sidebar 含两个 section：Favorites（Desktop/Documents/Downloads/Home/Applications，静态）+ Pinned（用户拖拽文件夹固定，右键移除，`PinnedFolders` + bookmark data 持久化（S16 升级），`DropDelegate` 仅接受 `UTType.folder`）。参照 Finder 侧边栏，后续按优先级扩展：

**P1**：iCloud Drive 入口 / Volumes & Locations（外置盘、网络盘，需评估 FSEvents 对非本地卷可靠性）/ ~~Pinned 升级 security-scoped bookmark~~（✅ S16 已完成）/ Recents 入口

**P2**：Tags（`NSURLTagNamesKey` 按颜色/名称分组）/ Smart Folders（保存搜索条件为虚拟文件夹）/ Pinned 拖拽重排序

**约束**：Sidebar 条目点击 = 导航（`model.navigate(to:)`），不做展开子树；文件树浏览是主区 FileTableView 职责。

### FileWorkspace 扩展路线

**P2**：~~目录就地折叠/展开~~（✅ S26 已完成）/ ~~i18n 多语言支持~~（✅ S25 已完成）

## 常用命令

```bash
# 列出可用 scheme / target
xcodebuild -list -project PathDeck.xcodeproj
# 构建
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build
# 测试（全量，含会拉起 GUI 的 UITests）
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck test
# 仅单元测试（跳过 UITests，纯逻辑验证用这个；-destination 绕过 Developer Mode 未开时的 LaunchServices 报错）
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -only-testing:PathDeckTests -destination 'platform=macOS,arch=arm64' test
# 打开工程
open PathDeck.xcodeproj
```

## 全局规范

### 关键技术决策

- **D1 分发 = Developer ID + Notarization，不走 App Store 沙盒。**
  理由：监听任意目录的 FSEvents + fork PTY + 真 terminal 在 App Store sandbox 下基本不可行。该决策反向约束权限模型：用 security-scoped bookmark 持久化用户显式授权的目录，默认不申请 Full Disk Access。

- **D2 Swift 语言模式暂定 5.0，编译器 6.3.2。**
  FSEvents watcher / PTY 均涉并发。未来切 Swift 6 strict concurrency 时要统一并发模型；新增并发代码应预留 `Sendable` / actor 隔离，避免后期大改。

- **D3 部署目标 macOS 26.5。**
  激进、收窄用户群，早期验证可接受。引入任何 API 前确认 26.5 可用，不为兼容旧系统做降级分支。

### libghostty 集成（已验证可构建 + 可嵌入运行，产物在 `vendor/`）

libghostty 无官方预编译产物 / 无 SPM / Homebrew 库形态 / 无官方 Swift 封装；C API（`ghostty.h`）功能稳定但签名仍 in flux（头文件自述 "not meant to be a general purpose embedding API (yet)"）。License：Ghostty MIT。已在本机 macOS 26.5 成功构建出含完整 C API 符号的 `GhosttyKit.xcframework`，产物落在 `vendor/`（见下）。

**关键工具链坑（实测，必读）**：Ghostty 精确要求 zig **0.15.2**（`build.zig` 的 `requireZig` 守卫 + std API 绑定，0.16 因版本守卫 + `readFileAlloc` 等 API breaking 编不过）。但 zig 0.15.2 **官方 release** 的链接器在 **Xcode 26.4+** 下无法 native 链接——Apple 把 tbd 的 `arm64-macos`/`arm64e-macos` 合并成只剩 `arm64e-macos`，zig 自带 lld 的 target-string 匹配不上，导致所有 `libSystem` 符号 undefined（连 zig 自己的 build runner 都编不出，`-Dtarget` 无法绕过，因 build runner 强制 host-native）。解法：用 **Homebrew 打了 arm64e 补丁的 zig 0.15.2**（上游 PR 31673 回移植，formula revision 1）。

**重建 recipe（临时本地构建，约 15min，构建完彻底清理工具链；峰值临时占 ~2-3GB）**：

```bash
# 1. 装 patched zig 0.15.2（经本地 tap；依赖 llvm@20+lld@20，全程 bottle，无源码编译）
brew tap-new kassol/zigbuild
curl -fsSL https://raw.githubusercontent.com/Homebrew/homebrew-core/616a4d9a7f/Formula/z/zig.rb \
  -o "$(brew --repository)/Library/Taps/kassol/homebrew-zigbuild/Formula/zig.rb"
brew install kassol/zigbuild/zig                      # zig 0.15.2_1，含 arm64e 补丁
# 2. 装 Metal Toolchain（Xcode 26 默认不含，libghostty 的 Metal shader 渲染必需，~688MB）
xcodebuild -downloadComponent MetalToolchain
# 3. 构建（建议 pin 一个验证过的 Ghostty commit；本次用 --depth 1 最新 main 成功）
git clone --depth 1 https://github.com/ghostty-org/ghostty && cd ghostty
zig build -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework=true -Demit-macos-app=false
# 产物 macos/GhosttyKit.xcframework 含 macos+ios 共 4 架构 slice（~536MB，iOS slice 用不上）
# 4. 提取 macOS arm64 + strip → 精简 xcframework（270M→23M）
lipo macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a -thin arm64 -output /tmp/ghostty-internal.a
strip -S /tmp/ghostty-internal.a
xcodebuild -create-xcframework -library /tmp/ghostty-internal.a \
  -headers macos/GhosttyKit.xcframework/macos-arm64_x86_64/Headers \
  -output <PathDeck>/vendor/GhosttyKit.xcframework
# 5. 清理工具链（零长期占用）
brew uninstall kassol/zigbuild/zig llvm@20 lld@20 && brew untap kassol/zigbuild
xcodebuild -deleteComponent MetalToolchain
```

**产物**：`vendor/GhosttyKit.xcframework`（macOS arm64、Release strip、~23MB，含 `ghostty.h` + `module.modulemap`，可 `import GhosttyKit`）。该二进制不进 git（见 `.gitignore`），需要时按上方 recipe 重建。

**集成方式（cmux + con-terminal 两生产项目实证；cmux 与 PathDeck 同栈 Swift+AppKit+预编译 xcframework，逐行锚点见 `docs/plans/2026-06-13-s2-libghostty-smoke.md` §参考来源）**：xcframework 加入 target Frameworks（静态库，Do Not Embed）；Swift 直接 `import GhosttyKit`（module 桥接，无需 modulemap / bridging include）；`OTHER_LDFLAGS = -lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UniformTypeIdentifiers -framework Carbon`（注意 `-lc++` 非 `-lstdc++`）。调用顺序 `ghostty_init`→`ghostty_config_new/finalize`→`ghostty_app_new`（填 6 个 runtime callbacks；`read_clipboard_cb` 视 GhosttyKit 构建可能需 `unsafeBitCast` 绕 bool↔Void importer 差异，本仓库当前产物实测正确导入为 `Bool`、可直接字面闭包）→ NSView(`makeBackingLayer`→`CAMetalLayer`，**须已挂 window 再建 surface**，否则黑屏)→`ghostty_surface_config_new`(platform.macos.nsview)→`ghostty_surface_new`→`set_display_id`/`set_content_scale`/`set_size`/`refresh`。**渲染由 libghostty 内部 CVDisplayLink 自驱，宿主从不调 `ghostty_surface_draw`**（`wakeup_cb`→合并到主队列的 `ghostty_app_tick` 只泵 PTY I/O，不是渲染）；resize 调 `set_size`，事件转发 text/key/mouse。terminfo：冒烟经 `surface_config.env_vars` 注入 `TERM=xterm-256color`；正式集成补 `xterm-ghostty`——预编译 xcframework **不含 Ghostty 的 zig-out 资源**（terminfo / shell-integration / themes），须单独从源码取。约 1500 行 Swift 胶水量级。

**约束**：

- 必须 pin Ghostty commit；升级当作 breaking 处理、预算迁移成本。
- 业务层只依赖 `TerminalEngine` 协议，禁止在业务代码直接散用 libghostty C 符号。libghostty C 符号限于 `GhosttyApp.swift` 和 `GhosttySurfaceView.swift` 内部（见 `PathDeck/Terminal/AGENTS.md`）。
- fallback：SwiftTerm（纯 SPM、开箱即用，CPU 渲染、特性 / 性能低一档）。

### 编码与协作

- 外科手术式修改：每行改动可追溯到明确需求，不顺手重构 / 改格式 / 动死代码。
- 里程碑式提交；commit message 用英文，第三方可读产出物中不出现个人称谓。
- 改完跑构建 + 测试（涉及 synchronized group 资源变动时用 **clean build**：同名 resource 冲突等问题增量 build 不暴露）。
- 新增子目录 `AGENTS.md` 或其他 `.md` / 文档后，须在 `PathDeck.xcodeproj` 把它加入 `PathDeck` synchronized group 的 `membershipExceptions`（`PBXFileSystemSynchronizedBuildFileExceptionSet`）——否则各目录同名 `AGENTS.md` 都拷向 `Contents/Resources/AGENTS.md` 冲突，致 build 失败。同理 `PathDeck/Info.plist` 也必须排除（否则 synchronized group 把它当 resource 拷入 bundle，与 `INFOPLIST_FILE` 指向的同一文件冲突）。当前已排除 `FileWorkspace/AGENTS.md`、`Terminal/AGENTS.md`、`Info.plist`。
- i18n：用户可见字符串用英文 key，SwiftUI 直接写字面量（`Text("Key")`、`.help("Key")`）自动走 `LocalizedStringKey`；AppKit 用 `String(localized: "Key")`。翻译在 `Localizable.xcstrings`（String Catalog，en + zh-Hans）。条件文案用 `LocalizedStringKey(condition ? "A" : "B")`（三元返回 `String` 不走自动本地化）。
- 用户可见文案避免：Agent Runtime / Profile、Tool Calling、Git / branch / commit / worktree / checkout、sandbox、orchestration、Finder Replacement、AI Finder（见 `docs/prd.md` §20.4）。

## 变更日志

里程碑级变更记录。各切片详细实现见 `docs/plans/` 和子目录 `AGENTS.md` 变更日志。

- 2026-06-17 **S27 Terminal Input Compat**：`GhosttySurfaceView` 全面接入键盘/鼠标/IME/剪贴板事件。P1 剪贴板（surface userdata 反查 view，confirmed=false 安全检查）+ performKeyEquivalent 三层拦截（Ctrl 直发/appReservedShortcuts 过滤/is_binding 判断）。P2 keyUp + flagsChanged（物理 keyCode 追踪，左右修饰键独立）。P3 完整鼠标（view point 坐标、焦点点击抑制、pressedMouseButtons 配对追踪、otherMouse 按钮映射、mouseExited 负坐标）。P4 IME NSTextInputClient（keybinding 快速路径 + interpretKeyEvents + keyTextAccumulator 累积 + preedit 提交 keycode=0）。forwardedKeyPresses 追踪 press/release 配对。
- 2026-06-17 **S26 目录就地折叠/展开**：NSTableView→NSOutlineView 迁移。新增 `FileNode`（NSObject 引用包装，跨 reload identity 稳定）+ `OutlineDataSource`（树状数据层：根/子项加载、缓存、`refreshRoot` 保留展开状态精确刷新、`reloadChildren` 裁剪已删除嵌套缓存、per-level 排序）。`FileTableView` Coordinator 从 NSTableViewDataSource/Delegate 切换到 NSOutlineViewDataSource/Delegate。搜索模式回退 flat 列表（`FlatFileNode`），dirty reload 走全量刷新避免 invalid item。FSWatcher handler 签名从 `() -> Void` 改为 `(Set<String>) -> Void`（传 dirty 目录集合），新增 `setExpandedDirectories` 支持多目录匹配，模型层所有展开状态变更后同步 watcher scope。拖拽源显式设置 local + non-local operation mask。WorkspaceModel 持有 OutlineDataSource + `dirtyDirectories` 精确刷新信号。11 个 OutlineDataSource 单测 + 4 个 FSWatcher 多目录单测。
- 2026-06-17 **S25 i18n**：建立 `Localizable.xcstrings` String Catalog（en 基语言 + zh-Hans），提取 11 个源文件的全量硬编码中文字符串为英文 key（SwiftUI 用 `LocalizedStringKey`、AppKit 用 `String(localized:)`），73 个翻译条目，跟随系统语言自动切换。pbxproj `knownRegions` 补 `zh-Hans`。
- 2026-06-17 **S24 UX Polish**：文件列表列宽 `lastColumnOnlyAutoresizingStyle` + 各列 `minWidth`；垂直 tab bar 分隔线可拖动（`VerticalDividerView`，100–300pt，持久化）；终端 tab 标题跟随 OSC title 自动更新（`onTitleChange` + `isManuallyRenamed`，手动重命名优先，清空恢复；ShellIntegration 新增 OSC 2 title hooks：zsh precmd/preexec + bash PROMPT_COMMAND）；移除 Reveal in Finder，PreviewPane 替换为 Copy Path。
- 2026-06-17 **S23 文件 Tab + Terminal-first 模式**：FileTab 多目录并行浏览 + TabManager @Observable 状态管理 + 终端 anchor cwd 一对多绑定 + Finder-first/Terminal-first per-tab 双模式 + FileTabBar（横向 28pt）+ VerticalTerminalTabBar（纵向，外部控制宽度）+ ⌘T/⌃Tab/⌃⇧Tab/⌘1-9 Tab 快捷键 + ⌘W NSEvent local monitor（终端焦点关终端/多 Tab 关 Tab/单 Tab 关窗口）+ ⌃` toggle 终端显隐 + ⌃⇧N 新建终端 + WorkspaceModel 多实例适配（移除全局 UserDefaults 持久化）+ Tab 列表 + 终端关联 + 模式全量持久化。
- 2026-06-16 **D1 Kill Change Journal**（Dogfood 第一刀）：移除 ChangeJournal 全栈（10 源文件 + 8 测试 + Settings tab），FSWatcher 迁入 FileWorkspace/ 简化为纯信号，移除 GRDB 包依赖。底部面板仅保留 Terminal。
- 2026-06-16 **S22 CLI helper**（M5 闭合）：`pathdeck` 命令行工具（参数解析 + URL 构造 + `/usr/bin/open`）+ `CLIInstaller` 安装菜单。203 测试。
- 2026-06-16 **Pre-S22 稳定化**：Kill FinderSync Extension + 10k 性能基线 + reveal firmlink 修复。
- 2026-06-16 **S19–S21 质量加固**：writeText 竞态收口（PendingTextBuffer + surface 失败回调）+ 变化归因重构（cwd 前缀纯函数）+ 版本 baseline 进目录预录。171 测试。
- 2026-06-16 **S18 系统入口**（M5 Phase 2）：`pathdeck://` URL Scheme + Finder Services + Open With 经 `AppRouter` 归一路由 + `reveal([URL])` 跨目录多选。149 测试。
- 2026-06-15 **S17 窗口状态恢复**（M5 Phase 1）：全量窗口状态持久化 + writeText 竞态修复（pending buffer）+ 1k 性能基线。126 测试。
- 2026-06-15 **S16 P1 合并交付**（M5 衔接）：Preview Pane + Terminal cwd 同步 + Pinned bookmark 持久化 + Settings 窗口。117 测试。
- 2026-06-15 **S15 Diff View + Restore**（M4 核心，killed D1）：Myers diff + inline diff view + restore + FSWatcher 聚合重写。
- 2026-06-15 **S14 终端归因 + 文件版本快照**（M3 闭合 + M4 基础，killed D1）：ChangeEvent 归因 + VersionStore。
- 2026-06-15 **S13 窗口布局骨架**：NavigationSplitView 两列 + 底部 Terminal 面板 + Terminal exit 自动关闭。82 测试。
- 2026-06-14 **M2 闭合**（S8–S12）：Terminal Panel + Context Bridge + 变化面板增强 + 忽略规则 + 多 Terminal Tab。82 测试。
- 2026-06-14 **M1 闭合**（S4–S7）：导航/排序/隐藏文件 + 右键菜单 + Quick Look + 打开文件夹/搜索。56 测试。
- 2026-06-14 **M0 闭合**（S3）：FSEvents 变化记录（SQLite 存储已在 D1 移除）。
- 2026-06-13 **技术验证**（S1–S2）：文件浏览 + libghostty 嵌入冒烟。
- 2026-06-13 初始化 AGENTS.md 体系；固化 D1/D2/D3 决策；libghostty 构建攻坚。
