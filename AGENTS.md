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

`FileWorkspace` 已完成 M1 全部 scope（S1 文件浏览 → S7 打开文件夹 + 搜索）+ S9 Send Path to Terminal；`ChangeJournal` 已落地（S3 FSEvents + SQLite）；`Terminal` 已完成 S2 冒烟 + S8 面板嵌入主窗口（`TerminalEngine` 协议 + ⌃\` 切换）+ S9 文本注入能力。M2 进行中。

```
PathDeck/                  App 源码
PathDeck/FileWorkspace/    文件工作台模块（目录浏览、列表视图），见其 AGENTS.md
PathDeck/Terminal/         内嵌 libghostty 真终端模块（S2 冒烟），见其 AGENTS.md
PathDeck/ChangeJournal/    文件变化感知与记录模块（FSEvents + SQLite），见其 AGENTS.md
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
- 业务层只依赖 `TerminalEngine` 协议，禁止在业务代码直接散用 libghostty C 符号（`Terminal` 模块当前为 S2 spike，暂直连 C 符号、未抽象协议，M1 接入文件工作台时补——见 `PathDeck/Terminal/AGENTS.md`）。
- fallback：SwiftTerm（纯 SPM、开箱即用，CPU 渲染、特性 / 性能低一档）。

### 编码与协作

- 外科手术式修改：每行改动可追溯到明确需求，不顺手重构 / 改格式 / 动死代码。
- 里程碑式提交；commit message 用英文，第三方可读产出物中不出现个人称谓。
- 改完跑构建 + 测试（涉及 synchronized group 资源变动时用 **clean build**：同名 resource 冲突等问题增量 build 不暴露）。
- 新增子目录 `AGENTS.md` 或其他 `.md` / 文档后，须在 `PathDeck.xcodeproj` 把它加入 `PathDeck` synchronized group 的 `membershipExceptions`（`PBXFileSystemSynchronizedBuildFileExceptionSet`）——否则各目录同名 `AGENTS.md` 都拷向 `Contents/Resources/AGENTS.md` 冲突，致 build 失败。当前已排除 `FileWorkspace/AGENTS.md`、`Terminal/AGENTS.md`。
- 用户可见文案避免：Agent Runtime / Profile、Tool Calling、Git / branch / commit / worktree / checkout、sandbox、orchestration、Finder Replacement、AI Finder（见 `docs/prd.md` §20.4）。

## 变更日志

- 2026-06-13 初始化 AGENTS.md 体系；固化 D1/D2/D3 决策；对齐 Bundle ID 至 `in.riverflows.PathDeck`。
- 2026-06-13 验证 libghostty 可在本机 macOS 26.5 构建（攻克 zig 0.15.2 × Xcode 26.4+ 的 arm64e tbd 链接死结，改用 Homebrew patched zig）；产出 `vendor/GhosttyKit.xcframework`（arm64 Release strip，~23MB），固化重建 recipe；临时构建工具链（zig/llvm@20/lld@20/Metal Toolchain）已清理。
- 2026-06-13 S1 文件浏览切片落地：新增 `FileWorkspace` 模块（启动即家目录的 `NSTableView` 文件列表 + 双击进入 / ⌘↑ 返回上级）；关闭 App Sandbox 落实 D1（移除 `ENABLE_USER_SELECTED_FILES`）；建立 `docs/plans/` 计划目录（按日期 + 需求名命名）。
- 2026-06-13 调研 cmux（Swift+Ghostty，与 PathDeck 同栈）+ con-terminal（Rust+同一套 libghostty C API）两生产项目的宿主集成实现，实证嵌入路径可行；据此修正集成方式（`-lstdc++`→`-lc++`+frameworks、`@import GhosttyKit` module 桥接、**宿主不调 `ghostty_surface_draw`**（Ghostty 内部 CVDisplayLink 自驱）、`read_clipboard_cb` importer 陷阱、surface 须挂 window 后再建、xcframework 不含 zig-out 资源）；产出 S2 冒烟计划 `docs/plans/2026-06-13-s2-libghostty-smoke.md`。
- 2026-06-13 从 `design/` 两份 standalone 设计稿（设计系统 + 交互原型）抽取 `docs/design.md`（UI 视觉权威参考）；交叉核验 metrics/色值/布局后定稿。
- 2026-06-13 S2 libghostty 嵌入冒烟落地：新增 `Terminal` 模块（`GhosttyApp`/`GhosttySurfaceView`/`TerminalSmokeView` + ⌃⌥⌘T 独立终端窗口）；pbxproj 链接 `GhosttyKit.xcframework` + 生产 LDFLAGS + `membershipExceptions` 排除各 `AGENTS.md` 出 bundle resource（修同名 resource 冲突）。Debug/Release clean build + 链接单测（`GhosttyLinkTests`）通过，证明自构建 xcframework 符号完整、`read_clipboard_cb` 实测导入为 `Bool`。渲染 + `echo`/`ls` 键盘回显 GUI 走查通过——**产品最脆弱假设（libghostty 能嵌入跑 PTY）证实，主路成立，不启用 SwiftTerm fallback**。
- 2026-06-14 S4 路径导航 + 排序 + 隐藏文件落地（M1 第一切片）：路径面包屑栏（`PathBarView`，可点击段跳转 + 家目录显示 `~`）+ NSTableView 四列列头排序（`sortDescriptorPrototype` + 目录始终在前 + nil 排末尾）+ ⌘⇧. 隐藏文件切换 + ⌘⌥C 复制路径。排序职责从 `DirectoryLister` 移至 `WorkspaceModel.sortedItems`（纯函数，可单测）。菜单命令通过 `@FocusedValue` + `@Entry` 宏连接 ContentView ↔ Commands。5 个排序单测通过。
- 2026-06-14 S3 FSEvents + SQLite 事件写入落地：新增 `ChangeJournal` 模块（`ChangeEvent`/`ChangeStore`/`FSWatcher`/`ChangeListView`）；引入 GRDB.swift 7.11.0（SPM）；SQLite 模式 WAL + `synchronous=NORMAL` + `busy_timeout=5s` + `auto_vacuum=INCREMENTAL`；FSEvents 用 `kFSEventStreamCreateFlagFileEvents` 逐文件粒度，事件分类用 flag 组合 + 文件存在性兜底；`ContentView` 底部固定 180pt 变化列表面板。Debug/Release clean build + 5 个 ChangeStoreTests 通过。**M0 三项验收标准全部达成**。
- 2026-06-14 S5 右键菜单 + 文件操作落地（M1 第二切片）：NSTableView 右键菜单（单选/多选/空白区域三态）+ Open/Open With…/Move to Trash（⌘⌫）/Rename（Enter 触发 inline editing，Esc 取消）/New Folder（⌘⇧N，创建后自动进入重命名）/Reveal in Finder/Copy Path。`FileNSTableView` 子类处理 Return 键；`Coordinator` 实现 `NSMenuDelegate` + `NSTextFieldDelegate` + `doCommandBy:` 拦截 Esc；`WorkspaceModel` 新增 `selectedURLs`/`pendingRenameURL` + 文件操作方法（`trashItems`/`renameItem`/`newFolder`）；双击文件改为用默认应用打开。修复：FSWatcher 加 `kFSEventStreamEventFlagItemIsDir` 处理（目录事件此前被过滤）；`menu.autoenablesItems = false`（多选时重命名正确灰掉）；编辑中跳过 `reloadData()`；`menuNeedsUpdate` 加 `clickedRow` 越界保护；⌘⌫ 改为独立 CommandMenu（原 `replacing: .undoRedo` 吞掉了 Edit 菜单的 Undo/Redo）。Debug/Release build + 46 个单测通过（新增 FSWatcherClassify×8 + WorkspaceModelFileOps×19 + newFolderName×4）。
- 2026-06-14 S6 Quick Look 预览落地（M1 第三切片）：空格键触发 `QLPreviewPanel`（打开/关闭切换）；`FileNSTableView` 实现 QL 所有权协议（`acceptsPreviewPanelControl`/`beginPreviewPanelControl`/`endPreviewPanelControl`）；`Coordinator` 遵循 `QLPreviewPanelDataSource`（基于选中文件提供 items，多选支持翻页）+ `QLPreviewPanelDelegate`（源 frame 动画锚定名称列单元格）；`handle` 只转发上下箭头 + 显式处理空格关闭（不能转发所有键盘事件回 table view，否则空格 keyUp 重新触发关闭）；选中文件切换时 QL 面板 `reloadData()`。`updateNSView` 加 `itemsChanged` 守卫——`@Observable` 任意属性变化都会触发 `updateNSView`，无条件 `reloadData()` 会破坏 QLPreviewPanel responder chain。仅改动 `FileTableView.swift`，~80 行。Debug/Release build + 46 个单测通过。
- 2026-06-14 S7 打开任意文件夹 + 文件名搜索落地（M1 收尾切片）：⌘O 打开文件夹（NSOpenPanel）+ Open Recent 菜单（`RecentFolders`，UserDefaults 持久化，10 项上限去重）+ 启动恢复上次目录（`lastOpenedFolder`）+ 拖放文件夹到窗口（`.onDrop` + `UTType.fileURL`）+ ⌘F 搜索栏（`SearchBarView` 包装 `NSSearchField`）+ 文件名实时过滤（`localizedCaseInsensitiveContains`，`allItems` → `applySearch()` → `items`）+ Esc 关闭搜索并恢复完整列表。`FileCommands` 改为 `replacing: .newItem`；`ViewCommands` 添加 `replacing: .textEditing`（⌘F）。新增 `RecentFolders.swift` + `SearchBarView.swift`。Debug/Release clean build + 56 个单测通过（新增 RecentFolders×4 + SearchFilter×6）。**M1 全部 scope 闭合**。
- 2026-06-14 S9 Send Path to Terminal 落地（M2 第二切片，Context Bridge 首切）：右键菜单「发送路径到终端」（单选/多选，POSIX 单引号 shell-escaped）+ 菜单快捷键 ⌘⇧T + 终端隐藏时自动展开再注入。`TerminalEngine` 协议新增 `writeText`；`GhosttySurfaceView.insertText` 调用 `ghostty_surface_text` C API；`GhosttyTerminalEngine` 持有 surface view 弱引用。新增 `ShellEscape.swift` 纯函数。`ContentView` 通过 `FocusedValues.sendPathAction` 暴露给菜单命令。Debug/Release build + 66 个单测通过（新增 ShellEscape×10）。
- 2026-06-14 S8 Terminal Panel 嵌入主窗口落地（M2 第一切片）：新增 `TerminalEngine` 协议（`makeTerminalView(cwd:) -> NSView`）+ `GhosttyTerminalEngine` 实现 + `TerminalPanelView`（`NSViewRepresentable`，只依赖协议）。`GhosttySurfaceView` 新增 `initialCwd` 属性支持可配置工作目录。主窗口底部可展开/收起终端面板（⌃\` / Toolbar 按钮切换，可拖拽分割线调整高度）；终端展开时隐藏「最近变化」面板。冒烟窗口保留。Review 修复：① 终端 view 始终在 tree 中（`frame(height:0)+clipped` 隐藏），避免 SwiftUI `if/else` 销毁 surface 导致 shell 会话丢失；② 分割线拖拽改用 `coordinateSpace(.named)` + `location` 定位，消除 `translation` 坐标系偏移引起的闪烁。Debug/Release build + 56 个单测通过。
