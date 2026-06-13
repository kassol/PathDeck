# S2：libghostty 嵌入冒烟

> 日期：2026-06-13　需求：libghostty-smoke（M0 切片 S2）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-13-s1-file-browser.md`。
> 本计划的接口契约 / 链接配置 / 渲染模型均由两个生产项目（cmux、con-terminal）实证，锚点见末节「参考来源」。

## 背景定位（M0 切片路线）

| 切片 | 内容 | 状态 |
|---|---|---|
| S1 | 启动即家目录 + NSTableView 文件列表 + 进出目录 | 已完成 ✓ |
| **S2** | **libghostty 嵌入冒烟** | **完成 ✓（build + 单测 + GUI 渲染/回显走查均通过）** |
| S3 | FSEvents 监听 demo + SQLite 事件写入 demo | 待办 |

S2 验证整个产品最脆弱的假设：libghostty「能嵌入进我们自己的 NSView 并跑起真 PTY shell」。`vendor/GhosttyKit.xcframework` 已构建但从未实测嵌入。

**调研后风险已大幅下降**：cmux（Swift+AppKit+Ghostty，与 PathDeck 完全同栈）与 con-terminal（Rust+同一套 libghostty C API）两个生产项目，已证实这条嵌入路径可行，且给出了渲染驱动、链接配置、回调桥接的确切做法。S2 从「探索式验证」变为「照搬式落地 + 验证照搬正确」。

## 目标与验证标准

App 内开出一个独立终端窗口，渲染出真实 shell 提示符，键盘输入能回显并执行命令。

可验证（手动，GUI 冒烟性质）：
1. 构建链接通过：`GhosttyKit.xcframework` + 生产链接 flag 成功链接，无 undefined symbol。
2. 菜单命令 / 快捷键（⌃⌥⌘T）打开「Terminal (Smoke)」独立窗口。
3. 窗口内 Ghostty 自驱渲染出当前用户默认 shell 提示符（Metal 出图，非黑屏）。
4. 键入 `echo hi` + 回车 → 回显并打印 `hi`。
5. 键入 `ls` → 列出 `working_directory`（家目录）内容。

通过即证明嵌入链路成立，S2 收尾、进 S3；不通过即触发 fallback（见末节）。

**（2026-06-13 人工 Xcode 走查通过：终端窗口渲染出 shell 提示符、`echo`/`ls` 键盘回显正常。最脆弱假设证实，S2 完成，不启用 SwiftTerm fallback。）**

## 前置体检（已核实）

| 项 | 结果 |
|---|---|
| `vendor/GhosttyKit.xcframework` | ✓ arm64 静态库 + `Headers/ghostty.h` + `module.modulemap` |
| 工程链接配置 | ✗ pbxproj 无 Ghostty 引用，S2 第一步建立（配置已由 cmux 实证，见下） |
| 核心 C API | ✓ `ghostty_init`/`app_new`/`surface_new`/`surface_set_display_id`/`surface_refresh` 全在 |
| **渲染驱动模型** | ✓ **已实证：Ghostty 内部自驱，宿主不调 `draw`**（见接口契约§渲染） |
| terminfo `xterm-ghostty` | ✗ 仓库无；冒烟注入 `TERM=xterm-256color`（系统自带）解决（决策 D-S2-1） |
| **xcframework 缺 zig-out 资源** | ⚠ 预编译产物拿不到 Ghostty 的 terminfo / shell-integration / themes（正式集成成本，见 Non-scope） |

**构建前置（团队约定）**：`vendor/*.xcframework` 不进 git。pbxproj 引用该路径，clone 后须先按根 `AGENTS.md` recipe 重建，否则链接失败。写入 `Terminal/AGENTS.md`。

## Scope

- 工程链接 `GhosttyKit.xcframework` + 生产验证过的系统库
- 最小 runtime 胶水：`ghostty_init` → `ghostty_app_new`（填 6 个 runtime callbacks，含 importer 陷阱处理）
- `CAMetalLayer`-backed `NSView` 承载 surface，转发尺寸 / 焦点 / 文本输入 / 基础按键
- 独立终端窗口入口（与 S1 文件列表主窗口隔离）

## Non-scope（有意推后，非遗漏）

- `TerminalEngine` 协议抽象 → 决策 D-S2-2：冒烟直连 C，M1 接入时按 con 实证的分层（协议只暴露平台无关语义，NSView 创建/backing 同步收进实现内）补
- **打包 Ghostty 资源**（`xterm-ghostty` terminfo / shell-integration / themes）→ xcframework 不含，需正式集成时单独从 Ghostty 源码取并放进 `Resources/`；冒烟用 `TERM=xterm-256color` 不依赖这些资源
- 完整键盘映射（功能键 / IME marked text / option-as-alt 全套）→ 冒烟接 `ghostty_surface_text` + 回车 / 退格 / Ctrl 基础键
- 复制粘贴保真、选区、滚动、resize 优化、多 surface / split / tab
- 剪贴板回调真实实现（冒烟用最小桩，read 返回 false）
- 字体 / 配色 / 配置文件加载（用 libghostty 默认）
- 业务接入：terminal 嵌进文件工作台布局（M1）

## 文件清单

新建模块目录 `PathDeck/Terminal/`（synchronized group 自动纳入 target）：

| 文件 | 职责 |
|---|---|
| `Terminal/GhosttyApp.swift` | 进程级单例：`ghostty_init`（一次）+ `config_new/finalize` + 填 `ghostty_runtime_config_s` + `ghostty_app_new`；`wakeup_cb`→合并到主队列的 `ghostty_app_tick`；维护 `appRegistry`（action_cb 只给 app 指针） |
| `Terminal/GhosttySurfaceView.swift` | `NSView`（`makeBackingLayer` 返回 `CAMetalLayer`）：建 surface、`set_display_id`/`set_content_scale`/`set_size`/`refresh`、转发 key/text/mouse/focus |
| `Terminal/TerminalSmokeView.swift` | `NSViewRepresentable` 包 `GhosttySurfaceView`，供 SwiftUI 窗口承载 |
| `Terminal/AGENTS.md` | 子目录规范（职责 / 结构 / 依赖 / 构建前置 / spike 标注 / 变更日志） |
| `PathDeckTests/GhosttyLinkTests.swift` | 链接冒烟单测：`ghostty_info()` 读版本，证明符号可调、库已链接、不依赖窗口 |

改动：
- `PathDeck/PathDeckApp.swift`：加 `Window("Terminal (Smoke)", id: "terminal-smoke")` scene + `.commands` 菜单命令（`openWindow`，⌃⌥⌘T）。S1 主 `WindowGroup` 不动。
- `PathDeck.xcodeproj/project.pbxproj`：链接配置（见下）。

S1 的 `FileWorkspace/` 与 `ContentView.swift` **不改**。

## 工程链接配置（直接采用 cmux 生产配置）

1. `vendor/GhosttyKit.xcframework` 加入 PathDeck target Frameworks，Embed = **Do Not Embed**（静态库）。
2. **桥接走 module，非 modulemap/非 bridging include**：Swift 文件直接 `import GhosttyKit`（xcframework 自带 module）。无需写 `.modulemap`，无需把 `ghostty.h` 加进 bridging header。
3. `OTHER_LDFLAGS`（cmux 实证，pbxproj 3777-3789）：
   ```
   -lc++ -framework Metal -framework QuartzCore -framework IOSurface -framework UniformTypeIdentifiers -framework Carbon
   ```
   注意是 **`-lc++` 非 `-lstdc++`**（libghostty 用 libc++）。`Carbon` 为键码、`IOSurface` 为渲染共享面。
4. 运行时无需 Metal Toolchain（shader 已编进 `.a`）。

## 接口契约（已据 `ghostty.h` + cmux/con 实证，无 placeholder）

### 调用链（冒烟最小路径）

```
启动（GhosttyApp 单例）：
  ghostty_init(CommandLine.argc, CommandLine.unsafeArgv)             // 全局一次
  cfg = ghostty_config_new(); ghostty_config_finalize(cfg)
  填 ghostty_runtime_config_s（见下，6 回调 + userdata）
  app = ghostty_app_new(&runtime, cfg)

开窗（GhosttySurfaceView，必须已挂上 window）：
  view.wantsLayer = true; makeBackingLayer() -> CAMetalLayer
      (pixelFormat=.bgra8Unorm, isOpaque=false, framebufferOnly=false)
  sc = ghostty_surface_config_new()
    sc.platform_tag = GHOSTTY_PLATFORM_MACOS
    sc.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
    sc.scale_factor = window.backingScaleFactor
    sc.working_directory = 家目录
    sc.env_vars=[{"TERM","xterm-256color"}]; sc.env_var_count=1     // 决策 D-S2-1，strdup
    sc.command = nil                                                 // 用户默认 shell
  surface = ghostty_surface_new(app, &sc)                           // gate: view.window != nil
  ghostty_surface_set_display_id(surface, displayID)                // 让内部 CVDisplayLink 锁刷新率
  ghostty_surface_set_content_scale(x, y)
  ghostty_surface_set_size(wpx, hpx)                                // backing 像素
  ghostty_surface_set_focus(surface, true)
  ghostty_surface_refresh(surface)                                  // kick 首帧，防 miss vsync

事件：
  viewDidChangeBackingProperties / setFrameSize → set_content_scale + set_size + set_display_id
  becomeFirstResponder / 焦点变化            → ghostty_surface_set_focus
  insertText(字符/IME)                       → ghostty_surface_text(s, bytes, len)
  keyDown(回车/退格/Ctrl)                     → ghostty_surface_key(s, ghostty_input_key_s)
  shell 退出                                  → 轮询 ghostty_surface_process_exited → 关窗
```

### runtime_config_s 六回调（C 函数指针 + importer 陷阱）

| 回调 | 冒烟实现 |
|---|---|
| `wakeup_cb(userdata)` | 取回 GhosttyApp，`scheduleTick()`：`_tickScheduled` 布尔 + `NSLock` 合并到主队列一次 `ghostty_app_tick`（wakeup 在 I/O 线程高频触发，禁止每次都 tick） |
| `action_cb(app,target,action)->bool` | 冒烟 `return false`；用 `appRegistry[UInt(bitPattern:app)]` 取 GhosttyApp（此回调首参是 app 指针，非 userdata） |
| `read_clipboard_cb` | **顶层函数 + `unsafeBitCast` 到 `ghostty_runtime_read_clipboard_cb`**：预编译 xcframework 可能把返回 `bool` 误导入成 `Void`，bitcast 兼容两种 importer（cmux 实证陷阱，照抄） |
| `confirm_read_clipboard_cb` | `@convention(c)` 闭包，no-op |
| `write_clipboard_cb` | `@convention(c)` 闭包，no-op |
| `close_surface_cb(userdata,bool)` | 标记应关闭，主线程关窗 |
| `userdata` | app 用 `Unmanaged.passUnretained(GhosttyApp.shared).toOpaque()`；surface 级回调用 `passRetained` 的 callback context（显式 `.release()`） |
| `supports_selection_clipboard` | `false` |

### 渲染驱动（已实证，无须再测）

**Ghostty 内部完全自驱，宿主从不调 `ghostty_surface_draw`。** cmux 全仓库 grep `ghostty_surface_draw` 零调用（与 PathDeck 完全同栈：Swift+AppKit+预编译 xcframework）。机制：宿主把 `nsview` 指针交给 libghostty，它内部取得该 view 的 `CAMetalLayer` 并**自起 CVDisplayLink 驱动 Metal 渲染**。宿主三个义务：① 提供 `CAMetalLayer`-backed NSView；② `ghostty_surface_set_display_id` 让其 CVDisplayLink 锁对刷新率；③ 创建/resize 后 `ghostty_surface_refresh` nudge 一帧。`ghostty_app_tick` 是 app 事件循环泵（PTY I/O / action），**不是渲染**。

> 注：con-terminal 走 `action_cb` 的 `GHOSTTY_ACTION_RENDER` 事件驱动调 draw——那是因 con 用 GPUI 非 AppKit 原生。PathDeck 与 cmux 同构，**抄 cmux 的自驱模型，不要走 con 的 RENDER 帧泵**。

### 事件转发（冒烟最小）

- `keyDown`：构造 `ghostty_input_key_s`（action=PRESS/REPEAT、`keycode=UInt32(event.keyCode)`、mods、`text` 经 `withCString` 临时指针——仅在 `ghostty_surface_key` 调用期内有效），调 `ghostty_surface_key` 返 Bool=是否消费；未消费再交 `interpretKeyEvents` 给 IME。
- 文本：`ghostty_surface_text(s, ptr, len)`。
- 鼠标（冒烟可选）：`ghostty_surface_mouse_pos/button/scroll`，坐标用 backing 像素。

## 最脆弱假设（premise collapse）

cmux/con 证明的是「libghostty 这条嵌入路径一般可行」，**没有证明 PathDeck 这个具体产物 + 工程 + 环境可行**。冒烟存在的核心理由从「探索能不能嵌入」转为「验证我们自己的 xcframework 缝进去能不能跑」。剩余真实风险（按根本性排序）：

1. **我们自构建的 `GhosttyKit.xcframework` 完整性（冒烟的首要验证目标）**：本产物由 patched zig 0.15.2 + `--depth 1` 最新 main 构建、`strip -S`、只取 arm64 slice（见 AGENTS.md recipe）。`strip` 是否伤到运行期必要符号、Metal shader 是否真编进 `.a`、我们构建用的 Ghostty commit 与 cmux pin 的 commit 间 C API 漂移（`ghostty.h` 自述 "API in flux"）——这三点 cmux/con 无法替我们消除。冒烟用最小代价点亮「我们的产物能渲染 + 回显」这个绿灯，是后续照搬 cmux 的前提。
2. **预编译 xcframework 的 importer 差异**：`read_clipboard_cb` bool↔Void（已有 cmux 的 `unsafeBitCast` 解法）；其余符号 module 导入是否完整需链接时确认。
3. **缺 zig-out 资源**：冒烟用 `TERM=xterm-256color` 规避，不阻塞；正式集成需补 terminfo/shell-integration（已记 Non-scope）。

若仍黑屏 / 崩溃且无解 → fallback SwiftTerm（见末节）。

## 测试

- **自动**：`GhosttyLinkTests` 调 `ghostty_info()` 断言返回非空版本——证明库链接正确、C 符号可从 Swift 调、不依赖窗口/GPU。
- **手动**：Sir 在 Xcode 运行，按 5 条验证标准走查。依 memory：实现方不自动 `open` app，自动验证限 `build + 单测`。

```
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -only-testing:PathDeckTests test
```

## 回滚

纯新增 `Terminal/` + `PathDeckApp.swift` 加一个 scene/命令 + pbxproj 链接配置。无数据写入、无外部状态。`git checkout` 即完全回退；S1 不受影响。

## 收尾（实现后）

- 新建 `PathDeck/Terminal/AGENTS.md`（构建前置、spike 标注、实测渲染模型、importer 陷阱）
- 更新根 `AGENTS.md`：目录索引补 `Terminal`；技术栈表确认嵌入已实测；变更日志记 S2 结果
- 本文件状态表 S2 标记已完成；S1 plan 的 M0 切片表同步
- 实现方只跑 build + 单测，GUI 冒烟交 Sir 走查

---

## 关键决策记录

- **D-S2-1 terminfo 用 `env_vars` 注入 `TERM=xterm-256color`**：cmux 实证子进程 TERM 即用 `xterm-256color`（求最大兼容，`TerminalStartupEnvironment.swift:9`），而非 `xterm-ghostty`。冒烟经 `surface_config.env_vars` 注入，不依赖 `GHOSTTY_RESOURCES_DIR`/打包 terminfo。正式集成再补 `xterm-ghostty` terminfo + 资源目录。
- **D-S2-2 冒烟直连 C，不先建 `TerminalEngine` 协议**：与 AGENTS.md「业务层只依赖协议」有张力，临时豁免（CLAUDE.md：单次使用不抽抽象）。M1 接入时按 con 实证分层补：协议只暴露平台无关语义（app/surface 生命周期 + input + 读文本 + 回调注册），NSView 创建与 backing 同步收进实现内、不外泄 libghostty 类型。
- **D-S2-3 验收边界 = 渲染 + 键盘回显**：冒烟证伪「能否嵌入跑 PTY」，不做完整终端。
- **独立终端窗口而非嵌进文件列表**：与 S1 主界面隔离，冒烟代码易演进 / 移除。

## 参考来源（实证锚点，路径相对各仓库根）

> 临时 clone 于 `/tmp/pd-ref/{cmux,con-terminal}`，会被清理；需要时重新 clone。

**cmux（manaflow-ai，Swift+AppKit+Ghostty，与 PathDeck 同栈 → 逐行可抄）**
- runtime init + 6 回调：`Sources/GhosttyTerminalView.swift:2097-2341`
- `read_clipboard_cb` unsafeBitCast 陷阱：`:247` + `:2159-2165`
- userdata 双轨 + appRegistry：`:2147` / `:4398-4428` / surface `:6534`
- wakeup→tick 合并：`:3519-3550`
- surface 创建 + env/command/cwd：`:6487-6750`；window gate：`:6418-6433`
- CAMetalLayer 配置：`:8558-8568`
- set_display_id/refresh/content_scale/size：`:6817-6862`
- keyDown / 事件转发：`:10140-10318`
- 启动环境两层：`cmuxApp.swift:234-285` / `TerminalStartupEnvironment.swift:9-21`
- 链接配置：`cmux-Bridging-Header.h`（`@import GhosttyKit;`）/ `cmux.xcodeproj/project.pbxproj:3777-3789`
- 踩坑测试：`cmuxTests/Ghostty{EnsureFocusWindowActivation,PasteboardFidelity,CommandShiftForwarding,TerminalStartupEnvironment}Tests.swift`

**con-terminal（nowledge-co，Rust+同一套 libghostty C API → 架构分层启发）**
- 同一套 C API + build.rs 编 zig 静态库：`crates/con-ghostty/src/ffi.rs:491-625` / `build.rs:64-148`
- runtime_config 回调全非 nil（ghostty 不做 null 检查）：`ffi.rs:504`
- 跨平台同名类型隔离（TerminalEngine 协议分层范本）：`lib.rs:11-14,63-104`
- backing 同步独立层：`objc/ghostty_surface_trampoline.m:31,74-78,130-145`（Swift 原生 NSView 可删整层）

## Fallback（S2 证伪时）

若嵌入不可行（黑屏无解 / 崩溃），切 **SwiftTerm**（纯 SPM、CPU 渲染、特性低一档），见根 `AGENTS.md`。届时按 D-S2-2，确定走 SwiftTerm 后再定 `TerminalEngine` 协议形状。
