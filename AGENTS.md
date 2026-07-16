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

四个已落地模块：`FileWorkspace`（文件工作台）/ `Terminal`（libghostty 终端）/ `Workspace`（NSWindow tabbing + per-window 状态）/ `Settings`（外观偏好）。当前能力：多 NSWindow workspace（系统级 tabbing，拖出/合并/Mission Control）+ 目录就地展开/折叠 + 多终端 tab + 文件↔Terminal cwd 双向桥 + 6 套终端主题热重载 + i18n（en/zh-Hans）+ 系统入口（`pathdeck://` / Finder Services / Open With / CLI）。逐 sprint scope 见文末变更日志与各子目录 AGENTS.md。

```
PathDeck/                  App 源码
PathDeck/PathDeckApp.swift @main（Settings scene 唯一 SwiftUI scene + 五组 CommandMenu）；workspace window 完全由 `AppDelegate` 经 AppKit 自管
PathDeck/ShortcutRegistry.swift  全部快捷键与命令元数据唯一真相源（S37 命令表：action/isEnabled；S38 键位单源：`KeyMatch` 机器 matcher + `dispatchVia`/`targetPolicy`/`indexedAction`），键帽 token、菜单键位、浮窗、Command Palette、`appReservedShortcuts` 终端拦截全部派生；改键位/动作只改这里
PathDeck/CommandDispatch.swift   Command Dispatch（命令派发，S38/ADR-0002）：`resolve(stroke, focus, target)` 纯决策函数——R1 仲裁（语境精确>global>跨语境，首个 enabled 胜出，全不可用放行）、textEditing 一律放行、非 workspace keyWindow 仅 allowsFallback；`menuShouldRun` 菜单入口守卫（monitor 返回 nil 拦不住同 sendEvent 内菜单 key-equivalent，monitor 型命令键盘触发菜单一律跳过防双执行）；`CommandDispatchTelemetry` 派发遥测测试缝；执行侧全局唯一 monitor adapter 在 `WorkspaceManager.installCommandMonitor`
PathDeck/AppDelegate.swift NSApplicationDelegate：启动构造 `WorkspaceManager` + `restoreSession` + `NSWindow.allowsAutomaticWindowTabbing = false`；kAEGetURL 拦截 URL Scheme + `application(_:open:)` Open With + Services 注册；`AppRouter.pending` FIFO 队列由 `drainPendingRoutes` 循环消费（命中 cwd 已有 window 激活，否则新建合入；`withObservationTracking` 注册后续 observation）
PathDeck/Workspace/        Workspace 模块（NSWindow tabbing 接管 + per-window 状态拆分），见其 AGENTS.md
PathDeck/SidebarView.swift Sidebar（统一 Favorites 区块，`List.onMove` 手动重排）+ PinnedFolders bookmark 持久化（首次启动 seed 默认五项，删空不恢复）
PathDeck/ReorderTransferables.swift  Terminal session reorder 自定义 UTType（`pathDeckTerminalSession`）+ `TerminalSessionDragID` Transferable 类型 + `TabDropEdge` enum
PathDeck/ArrayMove.swift     Foundation-only `Array.moveElement(from:to:)`（SwiftUI 单元素 move 语义等价，让模型层不吃 SwiftUI 框架）
PathDeck/AppRouter.swift   外部入口（URL Scheme/Services/Open With）归一中介，@Observable FIFO 路由队列（Finder 多选 Open With 一次 enqueue 多条 `.open`，由 `AppDelegate.drainPendingRoutes` 循环消费）
PathDeck/URLSchemeHandler.swift  pathdeck:// 解析 + 安全校验（查询参数式，目录/存在性校验）
PathDeck/ServicesProvider.swift  Finder Services @objc handler（NSPasteboard → AppRouter.Route）
PathDeck/CLIInstaller.swift "Install Command Line Tool…" 菜单逻辑（原子 replace 到 /usr/local/bin/ + shell-escaped sudo 提示）
PathDeck/Info.plist        URL Scheme / NSServices / CFBundleDocumentTypes / UTExportedTypeDeclarations（`in.riverflows.PathDeck.terminalSession`，SwiftUI `.draggable` / `.dropDestination` 须 plist 注册才能跨 NSItemProvider 桥接）/ 单实例（synchronized group 排除，靠 INFOPLIST_FILE 引用）
CLI/                       pathdeck 命令行工具 target（pathdeck-cli，product name: pathdeck）
CLI/main.swift             CLI 入口：解析参数 → CLICommand.parse → /usr/bin/open pathdeck://
CLI/CLICommand.swift       参数解析 + URL 构造纯函数（synchronized group 同时编译到 PathDeck app target 供单测，main.swift 经 membershipExceptions 排除）
PathDeck/ContextBridge/    Context Bridge 纯逻辑模块（Path Link 检测，FR-BRIDGE-003 / ADR-0003），见其 AGENTS.md
PathDeck/FileWorkspace/    文件工作台模块（目录浏览、列表视图、Preview Pane、FSWatcher），见其 AGENTS.md
PathDeck/Terminal/         内嵌 libghostty 真终端模块（多 Tab + TerminalEngine 协议 + cwd 同步 + 外观/主题偏好透传），见其 AGENTS.md
PathDeck/Settings/         Settings 窗口（左分类右详情：Appearance 主题画廊+字体/透明度 / Terminal shell+scrollback），见其 AGENTS.md
PathDeck.xcodeproj/        Xcode 工程
PathDeckTests/             单元测试
PathDeckUITests/           UI 测试
vendor/                    第三方二进制（GhosttyKit.xcframework，不进 git；`scripts/fetch-ghostty.sh` 从 deps/ghostty-* prerelease 下载，或按 libghostty recipe 重建）
docs/prd.md                产品需求文档（权威产品定义）
docs/design.md             UI 设计系统与原型参考（视觉权威，从 design/ 设计稿抽取）
docs/plans/                开发计划，按 `YYYY-MM-DD-<需求名>.md` 每需求一份
design/                    设计稿源文件（standalone HTML，可浏览器打开看可视参考），不进 build
```

规划模块（落地时各自补一份子目录 AGENTS.md）：`Extensions`（`FileWorkspace`、`Terminal`、`Workspace`、`ContextBridge` 已落地；`ChangeJournal` 已在 D1 Dogfood 中移除）。

### Sidebar 扩展路线

当前 Sidebar 单一 Favorites section：首次启动 seed Desktop/Documents/Downloads/Home/Applications 五项默认入口（基于 `UserDefaults.object(forKey: "pinnedFolderBookmarks") == nil` 判定），其余拖拽添加 / 右键移除，`PinnedFolders` + bookmark data 持久化（S16 升级、S30 合并 Favorites 静态块），`DropDelegate` 仅接受 `UTType.folder`，用户删空后不自动恢复默认。参照 Finder 侧边栏，后续按优先级扩展：

**P1**：iCloud Drive 入口 / Volumes & Locations（外置盘、网络盘，需评估 FSEvents 对非本地卷可靠性）/ ~~Pinned 升级 security-scoped bookmark~~（✅ S16 已完成）/ Recents 入口

**P2**：Tags（`NSURLTagNamesKey` 按颜色/名称分组）/ Smart Folders（保存搜索条件为虚拟文件夹）/ ~~Pinned 拖拽重排序~~（✅ S31 已完成）

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
# 仅单元测试（跳过 UITests，纯逻辑验证用这个）
# 注 1：本机 macOS 26.5 实测 `-destination 'platform=macOS,arch=arm64'` 单独不足以绕过 Developer Mode 关闭时的 LaunchServices 报错（"Could not launch PathDeckTests"），需先 sudo /usr/sbin/DevToolsSecurity -enable 一次开机器全局 Developer Mode，或直接在 Xcode 内 ⌘U
# 注 2：必须 `-parallel-testing-enabled NO`——并行 test worker 各自拉起 test host，与 app 单实例约束冲突，同报 IDELaunchErrorDomain Code=20（log 取证特征 "LAUNCHING: … is already running"）；跑前确认无运行中的 PathDeck 实例
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -only-testing:PathDeckTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO test
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
- 新增子目录 `AGENTS.md` 或其他 `.md` / 文档后，须在 `PathDeck.xcodeproj` 把它加入 `PathDeck` synchronized group 的 `membershipExceptions`（`PBXFileSystemSynchronizedBuildFileExceptionSet`）——否则各目录同名 `AGENTS.md` 都拷向 `Contents/Resources/AGENTS.md` 冲突，致 build 失败。同理 `PathDeck/Info.plist` 也必须排除（否则 synchronized group 把它当 resource 拷入 bundle，与 `INFOPLIST_FILE` 指向的同一文件冲突）。当前已排除 `ContextBridge/AGENTS.md`、`FileWorkspace/AGENTS.md`、`Workspace/AGENTS.md`、`Terminal/AGENTS.md`、`Settings/AGENTS.md`、`Info.plist`。
- i18n：用户可见字符串用英文 key，SwiftUI 直接写字面量（`Text("Key")`、`.help("Key")`）自动走 `LocalizedStringKey`；AppKit 用 `String(localized: "Key")`。翻译在 `Localizable.xcstrings`（String Catalog，en + zh-Hans）。条件文案用 `LocalizedStringKey(condition ? "A" : "B")`（三元返回 `String` 不走自动本地化）。
- 用户可见文案避免：Agent Runtime / Profile、Tool Calling、Git / branch / commit / worktree / checkout、sandbox、orchestration、Finder Replacement、AI Finder（见 `docs/prd.md` §20.4）。

## Agent skills

### Issue tracker

Issues tracked on GitHub (`kassol/PathDeck`) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles use their default names (`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## 变更日志

里程碑级变更记录。各切片详细实现见 `docs/plans/` 和子目录 `AGENTS.md` 变更日志。

- 2026-07-16 **S39 FR-BRIDGE-003 Terminal 输出路径可点击（#4 URL + #5 绝对路径骨干）**（ADR-0003：⌘Click 只定位不打开）：#4 `GhosttyApp.handleAction` 接通 `GHOSTTY_ACTION_OPEN_URL`——core 检测的 URL（含 OSC 8）⌘Click 交系统默认程序打开。#5 新模块 `ContextBridge/`（`PathLinkDetector` 纯函数：token 切分/包裹符剥离/尾部标点逐字符剥离+每步存在性检查，probe 注入可单测）；`GhosttySurfaceView.mouseDown` ⌘Click 拦截（`ghostty_surface_size` 像素→格子 + `ghostty_surface_read_text` 读行，命中不进 core 绕过 mouse reporting）；链路 view → `TerminalEngine.onPathLinkClick` → `WorkspaceManager` 反查 → `WorkspaceController.locate`（文件 reveal 不夺焦、目录 navigate；`WorkspaceModel.reveal` 新增 `takingFocus:` 参数）。相对路径/cwd/~/行号/引号/file:// 见 #6，⌘悬停反馈见 #7。测试 +21（`GhosttyOpenURLTests` 6 + `PathLinkDetectorTests` 15），全量 336。
- 2026-07-06 **Fix ⌘↑ 双发 + ⌘⇧. 连发回归**（ADR-0002 再补两条规则）：① WorkspaceRootView 面包屑按钮残留视图级 `.keyboardShortcut(.upArrow, ⌘)` 与 monitor 双发（视图级快捷键同样不受 monitor 返回 nil 抑制；S38 评审期「⌘↑ 原无绑定」结论有误，真实绑定就在这里）——删视图绑定，规则：monitor 型命令键位禁止视图层重复绑定。② 前菜单键迁 monitor 后失去菜单对 isARepeat 的天然抑制，⌘⇧. 长按连发偶数次 toggle 视觉「失效」——`dispatchCommand` 对已认领键位 repeat 吞而不执行。新增管线矩阵测试（全 monitor 键位按键位去重断言无双派发）+ repeat 抑制测试。全量 315。
- 2026-07-05 **Fix ⌘T 双开回归**（S38 上线后发现，ADR-0002 补充）：local monitor 返回 nil 只拦事件向 responder 的派发，拦不住同一 `sendEvent` 内的菜单 key-equivalent 处理——monitor 与菜单各执行一次致双开；S38 前不双开是 SwiftUI 菜单派发在 AppKit first responder 下本来就死。修复：`CommandDispatch.menuShouldRun` 守卫 `runCommand`/`runIndexedCommand`（monitor 型命令键盘触发菜单一律跳过，点击照常；Palette 直调 action 不受影响）。回归测试 `CommandTSingleFireTests`（真事件 sendEvent 泵 + `CommandDispatchTelemetry` 遥测测试缝）。顺带发现并同日修复既有隐患：`NSApp.delegate as? AppDelegate` 运行时为 nil（SwiftUI adaptor 转发 delegate），`fallbackManager` 兜底分支恒 nil，Settings 焦点 allowsFallback 命令实际 no-op（S37 起即如此）——新增 `WorkspaceManager.appShared`（static weak，AppDelegate 启动唯一注册点）替换 delegate cast，删同模式孤儿 helper `PathDeckApp.workspaceManager()`。全量 313 测试。
- 2026-07-04 **S38 Command Dispatch 收拢**（架构评审首推候选，ADR-0002）：键位三处分写（registry 展示 / 6 个 per-window monitor 内联匹配 / 菜单字面量）收敛为单源单路径。`ShortcutSpec` 增 `match: KeyMatch`（char/keyCode/digit-range + 修饰集，键帽/菜单键位/终端拦截全派生）+ `dispatchVia`（monitor/menuOnly/viewLocal）+ `targetPolicy`（workspaceStrict/allowsFallback）+ `indexedAction`（⌘1–9 行为进表，原 monitor 与菜单各一份）。新增 `CommandDispatch.resolve` 纯决策函数（R1 仲裁：语境精确>global>跨语境、首个 enabled 胜出、全不可用放行；textEditing 一律放行——重命名中 ⌘⌫ 不得移废纸篓；非 workspace keyWindow 仅 allowsFallback 执行）。`WorkspaceManager.installCommandMonitor` 全局唯一 monitor adapter（AppDelegate 启动装载），删 `WorkspaceController` 5 个键位 monitor（浮窗 hold-tracker 保留）。行为变化：⌘⇧T 终端栈空回退重开窗口（原吞键 no-op）；⌘↑ Go to Parent 获得实际绑定（原仅浮窗展示无派发路径）。测试 +17（resolve 矩阵 11 + adapter 合成 NSEvent 6，含 S32 ⌘T 回归）；全量 309。本地跑单测须 `-parallel-testing-enabled NO`（见常用命令注 2）。详见 `docs/plans/2026-07-04-s38-command-dispatch.md`。
- 2026-07-03 **S37 预留位转正：Command Palette + Reopen Closed Tab**（GitHub #1/#2/#3）：`ShortcutRegistry` 升级为命令表（每条 `action: (WorkspaceController?) -> Void` + `isEnabled` 谓词；workspace 型经 `requiresController` 收 nil no-op，responder-chain 型封装 `sendAction`，全局偏好型不依赖 controller），PathDeckApp 菜单动作一次到位改经 `runCommand(id)` 派发；Rename Workspace / Send Path 逻辑迁入 `WorkspaceController`，`WorkspaceModel.openSelection()` 新增。⌘⇧T 双语义对称 ⌘W：`CloseHistoryStack`（@Observable 泛型，LIFO 上限 10、仅进程内）终端栈挂 controller、窗口栈挂 manager；仅用户关闭手势入栈（engine exit 回调传 `recordHistory: false`）；重开按快照重建（终端恢复 cwd/标题/位置，窗口走 `restoreController` 恢复布局+终端组，原 tab 组存活即归位）——组关系必须用存活期缓存 `lastKnownTabGroup`（becomeKey/resignKey + 程序化 addTabbedWindow 后显式刷新），`windowWillClose` 时窗口已脱组取不到。⌘⇧P Command Palette：窗口内可交互 overlay（`CommandPaletteView` + `CommandPaletteFilter` subsequence fuzzy 纯函数），内容派生自 `paletteSpecs`，不可用置灰（↑↓ 跳过/↩ 无效），show/dismiss 经 controller 记录并还原 first responder。窗口类测试注意：Swift Testing 默认并行 + 非活跃 app 下 key 事件不可靠 → `@Suite(.serialized)` + 不依赖 becomeKey 的显式钩子。详见 `docs/plans/2026-07-03-s37-command-palette-reopen.md`。
- 2026-07-03 **S36 快捷键收束 + 长按 ⌘ 浮窗 + 键位对齐**：新建 `ShortcutRegistry`（快捷键元数据唯一真相源），`GhosttySurfaceView.appReservedShortcuts` 与快捷键浮窗内容改为派生，单测守护查重。键位全面对照业界惯例调整：⌘B 切换 Sidebar（新增）、⌘⇧B 接替 ⌘⇧P 切换 Preview Pane、⌘↩ 接替 ⌘⇧T Send Path、⌃⇧` 接替 ⌃⇧N New Terminal、⌘↓ 打开选中项（新增，与双击同路径）；⌘⇧P/⌘⇧T 留作预留位（命令面板 / 重开 tab）。长按 ⌘ 800ms 显示快捷键浮窗（`ShortcutOverlayHoldTracker` 纯状态机 + per-window 观察型 NSEvent monitor + SwiftUI overlay，阈值内按键/鼠标取消，⌘+点击多选不受影响）。Sidebar/Preview Pane 显隐从全局偏好迁为 per-window Session State（旧快照兼容，旧全局值作新窗口默认）。Return 重命名语义加纯键守卫并立 ADR（`docs/adr/0001`）。详见 `docs/plans/2026-07-03-s36-shortcut-overhaul.md`。
- 2026-07-02 **重启持久化补全（窗口 frame / 列宽 / 排序指示器）**：窗口 frame 进 session 快照（`WorkspaceGroupState.frame`，每 tab 组一个；越界回退默认居中），新独立窗口继承最近活跃窗口 frame + 级联偏移；列宽进全局偏好（`WorkspacePreferences.columnWidths`，不用 NSTableView autosaveName——写死 standard defaults 测试无法隔离）；排序列头指示箭头改按持久化排序初始化（原硬编码 name↑）。顺带修复既有 bug：`window.contentViewController = NSHostingController(...)` 赋值会把窗口 resize 到 SwiftUI fitting size（720×480），吞掉 contentRect——init 赋值后重新 setFrame。另修列宽还原 bug（`autoresizesOutlineColumn = false`，见 FileWorkspace/AGENTS.md）。首建根 `CONTEXT.md`（Preference vs Session State 术语边界）。
- 2026-07-02 **开源门面**：新增 README.md（英文、用户优先、首版无截图、如实标注开发中/无 release）、LICENSE（MIT，署名 Kassol）、CONTRIBUTING.md（构建方法 + issue-first PR 政策）、`.github/workflows/ci.yml`（`macos-26` runner，build + PathDeckTests，`CODE_SIGNING_ALLOWED=NO` 免证书，push main + PR 触发）、issue 模板（bug/feature，自动挂 `needs-triage`）、`vendor/GHOSTTY-LICENSE`（分发 libghostty 二进制的 MIT 合规副本）。GitHub 侧：repo description/topics 已设，五个 triage 标签已建。暂不做 release/签名/公证（无 Apple Developer 订阅，AGENTS.md D1 的 Developer ID 分发待订阅后启动）。GhosttyKit.xcframework 不进 git，改存 `deps/ghostty-20260613` prerelease 资产，CI 与贡献者统一走 `scripts/fetch-ghostty.sh` 下载（更新二进制时：ditto 打 zip → 新建 deps/ghostty-<date> release → 改脚本 TAG）。CI 落地踩坑三连：runner 宿主 macOS 26.4 低于 deployment target 26.5，test 步骤临时 `MACOSX_DEPLOYMENT_TARGET=26.4` override（镜像升级后移除）；测试大面积 0.000s failed = test host 进程死亡（读 xcresult 的 testFailures 而非 xcodebuild stdout，`xcresulttool export diagnostics` 拿 host stderr）；根因是 `windowWillClose` 后残留 SwiftUI 渲染触碰 `engineHandle` fatalError（修复见 Workspace/AGENTS.md）。

- 2026-06-25 **S33 Terminal Appearance + Hot Reload**：终端外观升级为 6 套内置主题画廊 + 字体族/字号/cursor/padding/透明度/模糊/copy-on-select，经受管 `runtime.conf` 透传（vendored xcframework 无逐键 setter，只能写文件 → `ghostty_config_load_file`）。热重载分层：主题/字号/光标/copy-on-select 实时作用活动 surface 不重建（保 scrollback/PTY/cwd），font-family/padding/透明度/scrollback/shell 仅新建终端生效（设置面板 footer 如实标注）。新增 `Terminal/TerminalPreferences` / `TerminalConfigWriter` / `ThemePreset`；Settings 重构为左分类右详情 + `ThemeGalleryView`。详见 `docs/plans/2026-06-25-s33-terminal-appearance-hot-reload.md` 与 `Terminal/`、`Settings/` AGENTS.md。
- 2026-06-18 **S32 NSWindow Tabbing**：文件 tab 升级为系统级 NSWindow tabbing —— 每个文件 tab 是独立 `WorkspaceController: NSWindowController`（统一 `tabbingIdentifier` + `tabbingMode = .preferred` 自动合并），免费拿到拖出/合并/Mission Control/Window menu/`Cmd+1..9`/视觉随系统升级。删 `TabManager` / `FileTab` / `FileTabBar` / `ContentView` 自绘 tab 栈及测试；状态拆为全局 `WorkspacePreferences` + per-window `WorkspaceController`（含 `WorkspaceModel` / `TerminalSessionStore` / `WorkspaceViewState`）；`AppDelegate` 拆出独立文件接管 window 生命周期 + URL/Services/Open With drain；`AppRouter` 跨 window 匹配 cwd 激活 vs 新建合入；旧 `fileTabsState` 一次性迁移到 `workspaceSessionState`；terminal 横/纵 tab 视觉对齐 NSWindowTab token。详见 `docs/plans/2026-06-18-s32-nswindow-tabbing.md` 与 `Workspace/`、`Terminal/` AGENTS.md。
- 2026-06-18 **S31 Reorder**：Sidebar Favorites + 文件 Tab Bar + Terminal Tab Bar（横/纵）三域手动拖拽排序。`PinnedFolders.move(from:to:)` Foundation-only 多元素 extract-then-insert 同序重排 items 与 bookmarks 后 `persist()`，`SidebarView` ForEach 挂 `.onMove`。新增 `ReorderTransferables.swift` 定义 `pathDeckFileTab` / `pathDeckTerminalSession` UTType（`conformingTo: .data` + Info.plist `UTExportedTypeDeclarations` 注册）+ `FileTabDragID` / `TerminalSessionDragID` 两个 Codable Transferable 类型 + `TabDropEdge` enum（.start/.end），靠类型系统跨域隔离。新增 `ArrayMove.swift` Foundation-only `Array.moveElement(from:to:)` 单元素 helper（与 SwiftUI `move(fromOffsets:toOffset:)` 单元素语义等价），让 `TabManager` 状态模型层不吃 SwiftUI 框架。`TabManager.moveFileTab(source:to:)` / `moveTerminalSession(in:source:to:)` 只动数组顺序，`WorkspaceModel` / `TerminalSession` / PTY / surface 实例不重建，active ID / anchor cwd 保留，noop 时不触发 `saveTabState()`（避免无意义持久化；`StatePersistenceModifier` 只监听 `count`，reorder 不会自动触发）。`FileTabBar` / `TerminalTabBar` / `VerticalTerminalTabBar` 接入 `.draggable(payload)` + `.dropDestination(for:)`，dropDestination 内 `source == target` 短路替代条件包装守卫（先前 `if allowed { .draggable } else { content }` ViewModifier 形式被验证会打断 `.draggable` 初始化）：横向按 `location.x < width/2` 判 before/after，纵向按 `location.y < height/2`；hover 期 `onContinuousHover` 实时 location 半区切 `hoveredEdge: TabDropEdge?`，hovered 边（`== .start` / `== .end`，nil 时不画方向线避免与 drop 落点矛盾）显 2pt accent 插入线（横向 leading/trailing、纵向 top/bottom），hoveredEdge=nil 时落到 hover 高亮兜底（onContinuousHover 不 fire 也能识别"目标 tab 被命中"）；GeometryReader 量测自身尺寸。`ContentView` 加 ⌘T `NSEvent.addLocalMonitorForEvents`：firstResponder is `GhosttySurfaceView` 时拦截 → `createTerminalTab()`，否则放行让 SwiftUI menu 创建文件 tab（与 ⌘W monitor 同模式）。新增 `PinnedFoldersReorderTests`（5 例）+ `TabManagerTests` 追加 11 例 reorder。
- 2026-06-18 **S30 Sidebar Merge**：`PinnedFolders` 增 `init(userDefaults:)` 注入入口 + `seedDefaults()` 首次启动 seed 五项默认（Desktop/Documents/Downloads/Home/Applications），seed 判定基于 `UserDefaults.object(forKey:) != nil` 区分"首次启动"与"用户删空"。`SidebarView` 删除静态 Favorites 数组与双 section 结构，合并为单一 `Section("Favorites")` 渲染 `pinnedFolders.items`，视觉沿用 `NSWorkspace.shared.icon` 系统彩色图标。`Localizable.xcstrings` 删除未引用的 `Pinned` 条目（73→72）。新增 4 个 seed/migrate/idempotent 单测。
- 2026-06-18 **S29 Convergence**：崩溃防御（OutlineDataSource `child(index:of:)` inert placeholder + 搜索模式 flat guard）+ 本地操作保留展开态（`reload()` 改用 `refreshAll`、`navigate()` 独立路径 `loadRoot`）+ IME 合成期按键对齐 Ghostty 原生（合成中 Ctrl+key 流向 `interpretKeyEvents` 让 IME 先处理、binding 快速路径 `markedText==nil` 守卫、合成期控制符 <0x20 抑制、`flagsChanged` 合成期跳过、`clearComposition()` 仅 `resignFirstResponder` 清残留）+ FSWatcher `stop()` deadlock 修复（`DispatchSpecificKey` 检测已在目标 queue）。200 测试。
- 2026-06-18 **S28 Quality Gate**：FSWatcher 补 3 个边界测试（re-watch 重启 / 动态 expanded dirs / 移除 expanded dir 停止匹配）。PRD 全量同步 D1 Kill Change Journal 决策。10k 性能基线阈值记录。
- 2026-06-17 **S27 Terminal Input Compat**：`GhosttySurfaceView` 全面接入键盘/鼠标/IME/剪贴板事件。P1 剪贴板（surface userdata 反查 view，confirmed=false 安全检查）+ performKeyEquivalent 三层拦截（Ctrl 直发/appReservedShortcuts 过滤/is_binding 判断）。P2 keyUp + flagsChanged（物理 keyCode 追踪，左右修饰键独立）。P3 完整鼠标（view point 坐标、焦点点击抑制、pressedMouseButtons 配对追踪、otherMouse 按钮映射、mouseExited 负坐标）。P4 IME NSTextInputClient（keybinding 快速路径 + interpretKeyEvents + keyTextAccumulator 累积 + preedit 提交 keycode=0）。forwardedKeyPresses 追踪 press/release 配对。
- 2026-06-17 **S26 目录就地折叠/展开**：NSTableView→NSOutlineView 迁移。新增 `FileNode`（NSObject 引用包装，跨 reload identity 稳定）+ `OutlineDataSource`（树状数据层：根/子项加载、缓存、`refreshRoot` 保留展开状态精确刷新、`reloadChildren` 裁剪已删除嵌套缓存、per-level 排序）。`FileTableView` Coordinator 从 NSTableViewDataSource/Delegate 切换到 NSOutlineViewDataSource/Delegate。搜索模式回退 flat 列表（`FlatFileNode`），dirty reload 走全量刷新避免 invalid item。FSWatcher handler 签名从 `() -> Void` 改为 `(Set<String>) -> Void`（传 dirty 目录集合），新增 `setExpandedDirectories` 支持多目录匹配，模型层所有展开状态变更后同步 watcher scope。拖拽源显式设置 local + non-local operation mask。WorkspaceModel 持有 OutlineDataSource + `dirtyDirectories` 精确刷新信号。11 个 OutlineDataSource 单测 + 4 个 FSWatcher 多目录单测。
- 2026-06-17 **S25 i18n**：建立 `Localizable.xcstrings` String Catalog（en 基语言 + zh-Hans），提取 11 个源文件的全量硬编码中文字符串为英文 key（SwiftUI 用 `LocalizedStringKey`、AppKit 用 `String(localized:)`），72 个翻译条目（S30 删除未引用的 `Pinned` 条目），跟随系统语言自动切换。pbxproj `knownRegions` 补 `zh-Hans`。
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
