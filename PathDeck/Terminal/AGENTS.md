# AGENTS.md — Terminal

> 内嵌 libghostty 真终端模块。本文就近覆盖根 `AGENTS.md`。

## 职责

把 libghostty（`vendor/GhosttyKit.xcframework`）嵌进 `NSView` 跑真 PTY shell，并通过 `TerminalEngine` 协议向业务层暴露。
S2 完成冒烟验证；S8 补齐协议抽象并将终端嵌入主窗口底部面板；S9 新增 `writeText` 文本注入能力（Context Bridge 基础）。完整终端（resize / 复制粘贴 / 选区 / IME / 完整键映射）属后续切片。

## 目录结构

- `TerminalEngine.swift` — 协议定义：多 session API（`createSession(cwd:) -> UUID` / `closeSession` / `terminalView(for:)` / `writeText(_:to:)` / `onCwdChange`），业务层唯一依赖
- `GhosttyTerminalEngine.swift` — 协议实现：管理多个 `GhosttySurfaceView` 实例（`[UUID: GhosttySurfaceView]` 字典），延迟创建 surface，关闭时释放；`pendingTexts` buffer 解决 surface 未就绪时 `writeText` 丢失（`onSurfaceReady` flush，5 秒超时保护）；通过 `GhosttyApp.registerPwdHandler` 订阅 cwd 变化
- `TerminalSession.swift` — 会话值类型（id, title, cwd, currentCwd）+ `TerminalTabState`（Codable，用于跨重启 tab 恢复），SwiftUI 可 ForEach
- `ShellIntegration.swift` — zsh/bash shell integration：ZDOTDIR 注入 OSC 7 precmd/chpwd hook（zsh），PROMPT_COMMAND 注入（bash）
- `TerminalTabBar.swift` — 多 Tab 栏 SwiftUI 视图：tab 切换 / 新建（+按钮）/ 关闭（×按钮）/ 双击重命名
- `TerminalPanelView.swift` — `NSViewRepresentable` 多 session 容器：container NSView + `isHidden` 切换活跃 surface + 焦点跟随
- `GhosttyApp.swift` — 进程级 runtime 单例：`ghostty_init` + `app_new` + runtime callbacks + `wakeup`→合并主队列 `app_tick` + `action_cb` 处理 `GHOSTTY_ACTION_PWD`/`SET_TITLE`（多 handler 注册）
- `GhosttySurfaceView.swift` — `CAMetalLayer`-backed `NSView`：surface 生命周期 + 尺寸/缩放/display 同步 + 键盘转发 + `initialCwd` 可配置 + `onSurfaceReady` 回调（`createSurface` 成功后触发）+ 读取 Settings（shell/font size）+ shell integration env vars 注入
- `TerminalSmokeView.swift` — `NSViewRepresentable` 包装，供独立冒烟窗口承载（S2 遗留，保留作调试入口）

入口：主窗口底部 Terminal Panel（⌃\` 或 Toolbar 按钮切换），支持多 tab；独立冒烟窗口（⌃⌥⌘T）。

## 构建前置

`vendor/GhosttyKit.xcframework` 不进 git。clone 后须先按根 `AGENTS.md` 的 libghostty recipe 重建，否则链接 undefined symbol。

链接配置（pbxproj，cmux 生产验证）：`FRAMEWORK_SEARCH_PATHS = $(PROJECT_DIR)/vendor`；`OTHER_LDFLAGS = -lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UniformTypeIdentifiers -framework Carbon`。桥接走 `import GhosttyKit`（xcframework module，无 bridging header）。

## 模块规范

- **协议已补齐（S8）**：业务层（`ContentView` 等）只依赖 `TerminalEngine` 协议，不 `import GhosttyKit`。libghostty C 符号限于 `GhosttyApp.swift` 和 `GhosttySurfaceView.swift` 内部。`GhosttyTerminalEngine` 是唯一桥接点——后续切换到 SwiftTerm 只需新增一个 `SwiftTermEngine` 实现。
- 渲染由 libghostty 内部 CVDisplayLink 自驱，**本模块从不调 `ghostty_surface_draw`**。宿主义务：`CAMetalLayer`-backed NSView + `set_display_id` + 创建/resize 后 `refresh` + `wakeup`→主队列 `app_tick`。
- surface 必须在 view 挂上 window 后再建（gate `window != nil`），否则黑屏。
- runtime callbacks 是 `@convention(c)`；app 级 userdata = `GhosttyApp`（`passUnretained`）。surface 级回调（剪贴板/关闭）冒烟 no-op。
- terminfo：冒烟经 surface `env_vars` 注入 `TERM=xterm-256color`，不依赖 `GHOSTTY_RESOURCES_DIR`。预编译 xcframework 不含 zig-out 的 `xterm-ghostty` terminfo / shell-integration / themes，M1 须单独获取。
- `read_clipboard_cb`：**本仓库当前 xcframework 正确导入为返回 `Bool`，直接赋字面闭包**。若换 GhosttyKit 构建把它导入成 `Void`，改用顶层函数 + `unsafeBitCast`（cmux 模式）。

## 依赖关系

依赖 GhosttyKit（vendor xcframework）；被 `ContentView`（终端面板）和 `PathDeckApp`（冒烟窗口）引用。`ContentView` 通过 `TerminalEngine` 协议间接依赖，不直接 `import GhosttyKit`。

## 验证

- 自动：`PathDeckTests/GhosttyLinkTests`（`ghostty_info()` 链接冒烟）+ `build`。
- GUI 冒烟（渲染 + 键盘回显）人工在 Xcode 走查，见 `docs/plans/2026-06-13-s2-libghostty-smoke.md` §目标与验证标准。

## 变更日志

- 2026-06-16 修复 `exit` 不自动关闭 tab（需 GUI 验证）：根因——当前 libghostty 产物的子进程退出走 embedder action `GHOSTTY_ACTION_SHOW_CHILD_EXITED`，**不**走 `wait_after_command`/`close_surface_cb`；未处理该 action 时 Ghostty 显示默认 "press any key" overlay（S13 假设的 `wait_after_command=false` 机制在 embedder 模型下不负责退出关闭）。`GhosttyApp.handleAction` 新增处理 `GHOSTTY_ACTION_SHOW_CHILD_EXITED`：post `ghosttySurfaceDidClose` 通知触发关闭退出 surface 对应 tab（经 `process_exited` 反查），`return true` 抑制 overlay。`config.wait_after_command = false`（GhosttySurfaceView）保留无害。此行为依赖真实 libghostty 子进程退出，单测覆盖不到。
- 2026-06-16 S19 writeText 竞态加固：新增 `PendingTextBuffer`（纯值类型，FIFO + 条数 64 / 字节 256KB 上限，超限丢队头最旧、单条超限仍接受），取代 `GhosttyTerminalEngine` 裸数组 `pendingTexts`。`GhosttySurfaceView` 新增 `onSurfaceFailed` 回调：`createSurface` 两条失败出口（app 未初始化 / `ghostty_surface_new` 返回 nil）显式通知 engine 立即丢弃 pending 并经 `onPendingDropped` 上报，不再等盲目 5s 超时静默丢。超时 token 化可取消（flush/close/失败均 cancel，消除 close 后残留 timer 误触发）。`handleSurfaceClose` 改遍历**全部**已退出 surface（抽 `exitedSessionIDs` 纯函数），修复同周期多 tab 退出只关一个。`pendingBuffers`/`pendingTimeoutTokens` 降 internal 作测试缝。156 个单测通过（+7：PendingTextBufferTests ×4 + TerminalSessionTests exitedSessionIDs/overflow 上报/close 取消超时）。
- 2026-06-15 S17 writeText 竞态修复 + tab 恢复：`GhosttyTerminalEngine` 新增 `pendingTexts` buffer，surface 未就绪时缓存文本，`onSurfaceReady` flush（5 秒超时保护）。`GhosttySurfaceView` 新增 `onSurfaceReady` 闭包。新增 `TerminalTabState`（Codable）用于 terminal tab 跨重启序列化恢复。
- 2026-06-15 S16 cwd 同步 + shell integration + Settings 适配：`GhosttyApp.action_cb` 从 no-op 改为处理 `GHOSTTY_ACTION_PWD`/`GHOSTTY_ACTION_SET_TITLE`，多 handler 注册（`registerPwdHandler`/`unregisterPwdHandler`）防多窗口覆盖。新增 `ShellIntegration.swift`（ZDOTDIR 注入 zsh 的 precmd/chpwd OSC 7 hook + bash PROMPT_COMMAND，percent-encode 路径）。`TerminalEngine` 协议新增 `onCwdChange`。`TerminalSession` 新增 `currentCwd`。`TerminalTabBar` 显示 cwd 尾段 + 点击跳转。`GhosttySurfaceView.createSurface` 读取 `TerminalDefaults`（shell/font size）+ `ShellIntegration.envVars`。
- 2026-06-15 S13 Terminal exit 自动关闭：`GhosttySurfaceView` 设 `wait_after_command=false`（跳过 "Press any key"），`surface` 改为 `private(set)` 供 engine 查询。`GhosttyApp.close_surface_cb` 发 `ghosttySurfaceDidClose` 通知。`GhosttyTerminalEngine` 新增 `onSessionClose` 回调 + 通知监听 → `ghostty_surface_process_exited` 反查 → 回调关闭 tab。`TerminalPanelView` 新增 `isActive` 参数，tab 切回时恢复键盘焦点。
- 2026-06-14 S12 多 Terminal Tab 落地：`TerminalEngine` 协议从单 session 改为多 session API（`createSession`/`closeSession`/`terminalView(for:)`/`writeText(_:to:)`）。新增 `TerminalSession.swift` 值类型 + `TerminalTabBar.swift`（tab 切换/新建/关闭/双击重命名）。`GhosttyTerminalEngine` 管理 `[UUID: GhosttySurfaceView]` 字典，surface 延迟到首次 `terminalView(for:)` 时创建。`TerminalPanelView` 重写为 container NSView（子 view `isHidden` 切换，保活所有 session PTY）。关闭最后一个 tab → 终端面板隐藏。Send Path / 拖拽路由到 active tab。Debug/Release build + 82 个单测通过（新增 TerminalSessionTests ×4）。
- 2026-06-13 S2 落地：libghostty 嵌入冒烟（`GhosttyApp` / `GhosttySurfaceView` / `TerminalSmokeView` + 独立终端窗口）。Debug/Release clean build + 链接单测通过；GUI 走查（渲染 + `echo`/`ls` 回显）通过，最脆弱假设证实、不启用 SwiftTerm fallback。实测本 xcframework 符号完整、`read_clipboard_cb` 正确导入为 `Bool`（无需 cmux 的 `unsafeBitCast` 兼容）。pbxproj 用 `membershipExceptions` 排除 `AGENTS.md` 出 bundle resource。
- 2026-06-14 S9 落地：`TerminalEngine` 协议新增 `writeText`；`GhosttySurfaceView` 新增 `insertText`（调用 `ghostty_surface_text` C API）；`GhosttyTerminalEngine` 持有 surface view 弱引用实现 `writeText`。Context Bridge 文本注入能力就绪。
- 2026-06-14 S8 落地：`TerminalEngine` 协议 + `GhosttyTerminalEngine` 实现 + `TerminalPanelView`（主窗口底部面板）。`GhosttySurfaceView` 新增 `initialCwd` 属性。⌃\` / Toolbar 按钮切换面板；可拖拽分割线调整高度；展开时隐藏「最近变化」。终端 view 始终在 tree 中（`frame(height:0)+clipped` 隐藏，避免 shell 会话丢失）；分割线用 `coordinateSpace` + `location` 定位（消除拖拽闪烁）。冒烟窗口保留。Debug/Release build + 56 个单测通过。
