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

首个业务模块 `FileWorkspace` 已落地（S1 文件浏览）。

```
PathDeck/                  App 源码
PathDeck/FileWorkspace/    文件工作台模块（目录浏览、列表视图），见其 AGENTS.md
PathDeck.xcodeproj/        Xcode 工程
PathDeckTests/             单元测试
PathDeckUITests/           UI 测试
vendor/                    第三方二进制（GhosttyKit.xcframework，不进 git，按 libghostty recipe 重建）
docs/prd.md                产品需求文档（权威产品定义）
docs/plans/                开发计划，按 `YYYY-MM-DD-<需求名>.md` 每需求一份
```

规划模块（落地时各自补一份子目录 AGENTS.md）：`Terminal` / `ContextBridge` / `ChangeJournal` / `Extensions`（`FileWorkspace` 已落地）。

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

### libghostty 集成（已验证可构建，产物在 `vendor/`）

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

**集成方式（依据 Kytos 先例 + `ghostty.h` 分析，PathDeck 尚未实测嵌入）**：拖入 target 的 "Frameworks, Libraries, and Embedded Content"；`OTHER_LDFLAGS` 加 `-lstdc++`；把 terminfo（`xterm-ghostty`，由 Ghostty 构建产出 `zig-out/share/terminfo`）打进 app bundle 并运行时设 `GHOSTTY_RESOURCES_DIR`/`TERMINFO`；自定义 `NSView`(CAMetalLayer backing) 调用顺序 `ghostty_init`→`ghostty_app_new`(填 wakeup/action/clipboard 回调)→`ghostty_surface_config_new`(platform.macos.nsview)→`ghostty_surface_new`，`drawRect` 调 `ghostty_surface_draw`、resize 调 `ghostty_surface_set_size`、事件转发 text/key/mouse。约 1500 行 Swift 胶水量级。

**约束**：

- 必须 pin Ghostty commit；升级当作 breaking 处理、预算迁移成本。
- 业务层只依赖 `TerminalEngine` 协议，禁止在业务代码直接散用 libghostty C 符号。
- fallback：SwiftTerm（纯 SPM、开箱即用，CPU 渲染、特性 / 性能低一档）。

### 编码与协作

- 外科手术式修改：每行改动可追溯到明确需求，不顺手重构 / 改格式 / 动死代码。
- 里程碑式提交；commit message 用英文，第三方可读产出物中不出现个人称谓。
- 改完跑构建 + 测试。
- 用户可见文案避免：Agent Runtime / Profile、Tool Calling、Git / branch / commit / worktree / checkout、sandbox、orchestration、Finder Replacement、AI Finder（见 `docs/prd.md` §20.4）。

## 变更日志

- 2026-06-13 初始化 AGENTS.md 体系；固化 D1/D2/D3 决策；对齐 Bundle ID 至 `in.riverflows.PathDeck`。
- 2026-06-13 验证 libghostty 可在本机 macOS 26.5 构建（攻克 zig 0.15.2 × Xcode 26.4+ 的 arm64e tbd 链接死结，改用 Homebrew patched zig）；产出 `vendor/GhosttyKit.xcframework`（arm64 Release strip，~23MB），固化重建 recipe；临时构建工具链（zig/llvm@20/lld@20/Metal Toolchain）已清理。
- 2026-06-13 S1 文件浏览切片落地：新增 `FileWorkspace` 模块（启动即家目录的 `NSTableView` 文件列表 + 双击进入 / ⌘↑ 返回上级）；关闭 App Sandbox 落实 D1（移除 `ENABLE_USER_SELECTED_FILES`）；建立 `docs/plans/` 计划目录（按日期 + 需求名命名）。
