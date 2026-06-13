# AGENTS.md — Terminal

> 内嵌 libghostty 真终端模块。本文就近覆盖根 `AGENTS.md`。

## 职责

把 libghostty（`vendor/GhosttyKit.xcframework`）嵌进 `NSView` 跑真 PTY shell。
当前是 **S2 冒烟切片**：验证「我们自构建的 xcframework 能缝进 AppKit 渲染 + 键盘回显」。
完整终端（resize / 复制粘贴 / 选区 / IME / 完整键映射）属 M1。

## 目录结构

- `GhosttyApp.swift` — 进程级 runtime 单例：`ghostty_init` + `app_new` + 6 个 runtime callbacks + `wakeup`→合并主队列 `app_tick`
- `GhosttySurfaceView.swift` — `CAMetalLayer`-backed `NSView`：surface 生命周期 + 尺寸/缩放/display 同步 + 键盘转发
- `TerminalSmokeView.swift` — `NSViewRepresentable` 包装，供独立冒烟窗口承载

入口：`PathDeckApp` 的 `Window("Terminal (Smoke)", id: "terminal-smoke")` + ⌃⌥⌘T 菜单命令。

## 构建前置

`vendor/GhosttyKit.xcframework` 不进 git。clone 后须先按根 `AGENTS.md` 的 libghostty recipe 重建，否则链接 undefined symbol。

链接配置（pbxproj，cmux 生产验证）：`FRAMEWORK_SEARCH_PATHS = $(PROJECT_DIR)/vendor`；`OTHER_LDFLAGS = -lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UniformTypeIdentifiers -framework Carbon`。桥接走 `import GhosttyKit`（xcframework module，无 bridging header）。

## 模块规范

- **本模块当前是 spike**：直连 libghostty C 符号，未抽象 `TerminalEngine` 协议（决策 D-S2-2）。M1 接入文件工作台时按 con-terminal 实证分层补协议（只暴露平台无关语义，NSView 创建/backing 同步收进实现内）；届时业务层禁止直接散用 C 符号（根 AGENTS.md 约束）。
- 渲染由 libghostty 内部 CVDisplayLink 自驱，**本模块从不调 `ghostty_surface_draw`**。宿主义务：`CAMetalLayer`-backed NSView + `set_display_id` + 创建/resize 后 `refresh` + `wakeup`→主队列 `app_tick`。
- surface 必须在 view 挂上 window 后再建（gate `window != nil`），否则黑屏。
- runtime callbacks 是 `@convention(c)`；app 级 userdata = `GhosttyApp`（`passUnretained`）。surface 级回调（剪贴板/关闭）冒烟 no-op。
- terminfo：冒烟经 surface `env_vars` 注入 `TERM=xterm-256color`，不依赖 `GHOSTTY_RESOURCES_DIR`。预编译 xcframework 不含 zig-out 的 `xterm-ghostty` terminfo / shell-integration / themes，M1 须单独获取。
- `read_clipboard_cb`：**本仓库当前 xcframework 正确导入为返回 `Bool`，直接赋字面闭包**。若换 GhosttyKit 构建把它导入成 `Void`，改用顶层函数 + `unsafeBitCast`（cmux 模式）。

## 依赖关系

依赖 GhosttyKit（vendor xcframework）；被 `PathDeckApp` 引用（终端窗口 scene）。与 `FileWorkspace` 无相互依赖。

## 验证

- 自动：`PathDeckTests/GhosttyLinkTests`（`ghostty_info()` 链接冒烟）+ `build`。
- GUI 冒烟（渲染 + 键盘回显）人工在 Xcode 走查，见 `docs/plans/2026-06-13-s2-libghostty-smoke.md` §目标与验证标准。

## 变更日志

- 2026-06-13 S2 落地：libghostty 嵌入冒烟（`GhosttyApp` / `GhosttySurfaceView` / `TerminalSmokeView` + 独立终端窗口）。Debug/Release clean build + 链接单测通过；GUI 走查（渲染 + `echo`/`ls` 回显）通过，最脆弱假设证实、不启用 SwiftTerm fallback。实测本 xcframework 符号完整、`read_clipboard_cb` 正确导入为 `Bool`（无需 cmux 的 `unsafeBitCast` 兼容）。pbxproj 用 `membershipExceptions` 排除 `AGENTS.md` 出 bundle resource。
