# AGENTS.md — PathDeck

> macOS 原生文件工作台。本文件是根级工作约束；子目录 AGENTS.md 就近覆盖本文。
> 开工前先读：本文件 + 相关子目录 AGENTS.md + `docs/prd.md`。

## 项目概述

PathDeck 是一个 Finder-first 的 macOS 文件工作台：以文件浏览为主心智，需要命令行时就地长出真 Terminal，并透明记录 Terminal / CLI / AI agent 对文件系统造成的变化。

四大支柱：

1. Finder-like 文件工作台（浏览 / 预览 / 搜索 / 路径导航）
2. 内嵌 libghostty 真 Terminal（经 `TerminalEngine` 协议隔离）
3. Context Bridge（文件 ↔ Terminal 双向上下文桥）
4. Change Journal（FSEvents + SQLite 透明变化记录 + 轻量版本 / diff / restore）

完整产品定义见 `docs/prd.md`（v0.2 Draft，唯一权威产品来源）。

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
| 文件监听 | FSEvents | 目录树变化 |
| 存储 | SQLite | 事件 / 版本 / 会话 |
| 搜索 | Spotlight + SQLite FTS | |
| 预览 | Quick Look / PDFKit / AVKit | |
| 分发 | Developer ID + Notarization | 见决策 D1 |

环境基线：

- 部署目标 macOS 26.5（见 D3）
- 工程 `SWIFT_VERSION = 5.0`（语言模式；本机编译器 Swift 6.3.2）（见 D2）
- Bundle ID：`in.riverflows.PathDeck`
- URL Scheme：`pathdeck://`
- 芯片：Apple Silicon（arm64）

## 目录索引

`FileWorkspace` 已完成 M1 全部 scope（S1–S7）+ S9 Send Path to Terminal + S10 拖拽到终端 + 文件变化标记 + S16 Preview Pane（右侧文件预览/元数据/Quick Actions）；`ChangeJournal` 已落地（S3 FSEvents + SQLite）+ S10 时间分组/类型过滤/点击定位增强 + S11 忽略规则（默认噪音过滤 + 用户自定义 glob）+ S14 终端活跃期间变化归因（弱关联到活跃终端 session）+ 轻量文件版本快照（文本类自动快照，独立 `versions.db`，hash 去重，大小上限与版本保留数从 Settings 读取）+ S15 Inline Diff View + Restore（Myers diff + 底部面板 diff tab + 恢复前自动快照 + FSWatcher 跨批次聚合重写）；`Terminal` 已完成 S2 冒烟 + S8 面板嵌入主窗口 + S9 文本注入 + S12 多 Terminal Tab（独立 PTY/cwd/scrollback，tab bar 切换/新建/关闭/重命名）+ S16 cwd 同步（OSC 7 → `GHOSTTY_ACTION_PWD` → tab bar 显示当前 cwd + 点击跳转文件浏览器）。M2 闭合，M3 闭合。S13 窗口布局骨架：NavigationSplitView 两列（sidebar + detail）+ 底部面板 Terminal/Changes tab 共存。S16 新增 Settings 窗口（Terminal shell/font/scrollback + Changes 开关/大小上限/版本保留数/忽略规则管理）+ Pinned 升级为 bookmark data 持久化。

```
PathDeck/                  App 源码
PathDeck/ContentView.swift NavigationSplitView 主布局 + 底部面板 tab 切换 + Preview Pane + 终端/变化协调
PathDeck/SidebarView.swift Sidebar（Favorites + Pinned）+ PinnedFolders bookmark 持久化
PathDeck/FileWorkspace/    文件工作台模块（目录浏览、列表视图、Preview Pane），见其 AGENTS.md
PathDeck/Terminal/         内嵌 libghostty 真终端模块（多 Tab + TerminalEngine 协议 + cwd 同步），见其 AGENTS.md
PathDeck/ChangeJournal/    文件变化感知与记录模块（FSEvents + SQLite + 版本快照），见其 AGENTS.md
PathDeck/Settings/         Settings 窗口（Terminal + Changes 偏好设置）
PathDeck.xcodeproj/        Xcode 工程
PathDeckTests/             单元测试
PathDeckUITests/           UI 测试
vendor/                    第三方二进制（GhosttyKit.xcframework，不进 git，按 libghostty recipe 重建）
docs/prd.md                产品需求文档（权威产品定义）
docs/design.md             UI 设计系统与原型参考（视觉权威，从 design/ 设计稿抽取）
docs/plans/                开发计划，按 `YYYY-MM-DD-<需求名>.md` 每需求一份
design/                    设计稿源文件（standalone HTML，可浏览器打开看可视参考），不进 build
```

规划模块（落地时各自补一份子目录 AGENTS.md）：`ContextBridge` / `Extensions`（`FileWorkspace`、`Terminal`、`ChangeJournal` 已落地）。

### Sidebar 扩展路线

当前 Sidebar 含两个 section：Favorites（Desktop/Documents/Downloads/Home/Applications，静态）+ Pinned（用户拖拽文件夹固定，右键移除，`PinnedFolders` + bookmark data 持久化（S16 升级），`DropDelegate` 仅接受 `UTType.folder`）。参照 Finder 侧边栏，后续按优先级扩展：

**P1**：iCloud Drive 入口 / Volumes & Locations（外置盘、网络盘，需评估 FSEvents 对非本地卷可靠性）/ ~~Pinned 升级 security-scoped bookmark~~（✅ S16 已完成）/ Recents 入口

**P2**：Tags（`NSURLTagNamesKey` 按颜色/名称分组）/ Smart Folders（保存搜索条件为虚拟文件夹）/ Pinned 拖拽重排序 / Badge 计数（目录下变化数量，`ChangeStore` 查询）

**约束**：Sidebar 条目点击 = 导航（`model.navigate(to:)`），不做展开子树；文件树浏览是主区 FileTableView 职责。

## 常用命令

```bash
# 列出可用 scheme / target
xcodebuild -list -project PathDeck.xcodeproj
# 构建
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build
# 测试（全量，含会拉起 GUI 的 UITests）
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck test
# 仅单元测试（跳过 UITests，纯逻辑验证用这个）
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -only-testing:PathDeckTests test
# 打开工程
open PathDeck.xcodeproj
```

## 全局规范

### 关键技术决策

- **D1 分发 = Developer ID + Notarization，不走 App Store 沙盒。**
  理由：监听任意目录的 FSEvents + fork PTY + 真 terminal 在 App Store sandbox 下基本不可行。该决策反向约束权限模型：用 security-scoped bookmark 持久化用户显式授权的目录，默认不申请 Full Disk Access。

- **D2 Swift 语言模式暂定 5.0，编译器 6.3.2。**
  FSEvents watcher / PTY / SQLite 均涉并发。未来切 Swift 6 strict concurrency 时要统一并发模型；新增并发代码应预留 `Sendable` / actor 隔离，避免后期大改。

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
- 新增子目录 `AGENTS.md` 或其他 `.md` / 文档后，须在 `PathDeck.xcodeproj` 把它加入 `PathDeck` synchronized group 的 `membershipExceptions`（`PBXFileSystemSynchronizedBuildFileExceptionSet`）——否则各目录同名 `AGENTS.md` 都拷向 `Contents/Resources/AGENTS.md` 冲突，致 build 失败。当前已排除 `FileWorkspace/AGENTS.md`、`Terminal/AGENTS.md`、`ChangeJournal/AGENTS.md`。
- 用户可见文案避免：Agent Runtime / Profile、Tool Calling、Git / branch / commit / worktree / checkout、sandbox、orchestration、Finder Replacement、AI Finder（见 `docs/prd.md` §20.4）。

## 变更日志

里程碑级变更记录。各切片详细实现见 `docs/plans/` 和子目录 `AGENTS.md` 变更日志。

- 2026-06-15 **S16 P1 合并交付**（M5 衔接）：新增 `PreviewPane`（右侧文件预览面板，QLThumbnail + 元数据 + 版本状态 + Quick Actions，⌘⇧P toggle）+ Terminal cwd 同步（`GHOSTTY_ACTION_PWD` 回调 → tab bar 显示 cwd + 点击跳转文件浏览器）+ `PinnedFolders` 升级 bookmark data 持久化（旧路径 key 自动迁移，stale bookmark 静默丢弃）+ Settings 窗口（⌘, 打开，Terminal tab: shell/font size/scrollback + Changes tab: 开关/大小上限/版本保留数/忽略规则管理）+ `VersionStore` 大小阈值与版本保留数从 Settings 读取 + `GhosttySurfaceView` 读取 Settings shell/font size + `GhosttyApp.action_cb` 从 no-op 改为处理 PWD/SET_TITLE。117 个单测通过（+11）。
- 2026-06-15 **S15 Diff View + Restore + FSWatcher 聚合重写**（M4 核心用户面）：新增 `DiffEngine`（Myers diff）+ `DiffView`（inline diff + restore + `.task(id:)` 路径切换 + restore 前快照失败中止）+ `VersionStore.previousVersionWithContent`（跳过当前 hash）；`ChangeListView` 行导航与版本图标拆为独立区域；`FSWatcher` 重写为跨批次时间窗口聚合（0.5s debounce + `mergeType` 6 种组合 + `classify` renamed→modified）；`IgnoreRules` 新增 `*.sb-*`/`._*`/`*.tmp`；`ContentView` 底部面板 diff tab + restore 后自动回 changes；移除 `recentEventKeys` 补丁。106 个单测通过（+16）。
- 2026-06-15 **S14 终端归因 + 文件版本快照**（M3 闭合 + M4 基础）：`ChangeEvent` 新增 `terminalSessionID` 归因字段 + `ChangeStore` v2 migration + 新增 `VersionStore`（独立 `versions.db`，文本类 ≤1MB 自动快照，SHA256 hash 去重，per-file 10 版本上限）+ `ChangeListView` 终端归因图标 + 版本快照图标 + `WorkspaceModel` 集成归因传递与快照触发。90 个单测通过（+8）。
- 2026-06-15 **S13 窗口布局骨架**：NavigationSplitView 两列布局（sidebar Finder 风格 Favorites + detail 工作区）+ 底部面板 Terminal/Changes tab 共存（终端不再遮挡变化列表）+ BottomPanelBar 统一 tab bar + `isTerminalVisible` → `isBottomPanelVisible` 语义重命名 + Terminal exit 自动关闭 tab（`wait_after_command=false` + `close_surface_cb` → 通知 → 反查 `process_exited` → 回调关闭）。82 个单测通过。
- 2026-06-14 **M2 闭合**（S8–S12）：Terminal Panel 嵌入主窗口 + Context Bridge（Send Path + 拖拽到终端）+ 变化面板增强（时间分组/类型过滤/点击定位/文件标记）+ 忽略规则（默认噪音过滤 + 用户自定义 glob）+ 多 Terminal Tab（独立 PTY/cwd/scrollback）。82 个单测通过。
- 2026-06-14 **M1 闭合**（S4–S7）：路径导航/排序/隐藏文件 + 右键菜单文件操作 + Quick Look 预览 + 打开文件夹/搜索。56 个单测通过。
- 2026-06-14 **M0 闭合**（S3）：FSEvents + SQLite 变化记录。
- 2026-06-13 **技术验证**（S1–S2）：文件浏览 + libghostty 嵌入冒烟。libghostty 能嵌入跑 PTY 的最脆弱假设证实。
- 2026-06-13 初始化 AGENTS.md 体系；固化 D1/D2/D3 决策；libghostty 构建攻坚（zig 0.15.2 × Xcode 26.4+ arm64e tbd）；设计系统文档提取。
