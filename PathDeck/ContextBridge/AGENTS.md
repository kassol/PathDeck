# AGENTS.md — ContextBridge

> 文件 ↔ Terminal 双向上下文桥模块。本文就近覆盖根 `AGENTS.md`。

## 职责

承载 Context Bridge 中「终端输出 → 文件工作台」方向的纯逻辑：把终端一行文本解析成可 Locate 的 Path Link（FR-BRIDGE-003，点击语义见 `docs/adr/0003-cmd-click-locates-never-opens.md`，术语见根 `CONTEXT.md`「文件与终端联动」）。

「文件 → 终端」方向（Send Path、cwd 双向同步）历史上散落在 `FileWorkspace` / `Terminal` / `Workspace`，暂不回迁。

## 目录结构

- `PathLinkDetector.swift` — `PathLink` 值类型（url + isDirectory + line/column，行列号解析保留、无消费方，ADR-0003）+ `PathLinkDetector.detect(line:index:cwd:home:probe:)` 纯函数：引号区候选优先（含空格路径唯一入口，撇号假引号区落空回退 token）→ token 切分（空白边界）+ 剥离前导包裹符 → 形态解析（绝对 / `~` 展开 / `file://` percent-decode / 相对仅挂非 nil `cwd`，`~user` 与 Windows 反斜杠不支持）→ 候选循环：原样 → 剥 `:line` → 剥 `:line:col`（字面命中优先），全落空剥一个尾部标点重来（防吃扩展名点）。另有 `link(fromFileURL:probe:)` 供 OPEN_URL file:// 改道入口。存在性经 `probe` 闭包注入（生产 `fileSystemProbe`，测试注假文件系统）。

## 模块规范

- 本模块只依赖 Foundation：不 import AppKit / GhosttyKit / SwiftUI。像素/格子换算、`ghostty_surface_read_text` 等宿主事实属 `Terminal/GhosttySurfaceView`；Locate 的执行（navigate/reveal）属 `Workspace/WorkspaceController.locate`。
- 检测器保持纯函数 + 注入式存在性检查（cwd/home 显式传参，不在检测器内读全局状态），新增识别形态必须先补 `PathLinkDetectorTests` 再实现。
- 解析不出目标或目标不存在的文本段不构成 Path Link——存在性检查是构造 `PathLink` 的前提，不允许绕过。

## 依赖关系

依赖 Foundation。被 `Terminal/GhosttySurfaceView`（⌘Click 命中检测）引用；`PathLink` 值类型贯穿 `TerminalEngine` 协议回调 → `WorkspaceManager` → `WorkspaceController.locate`。

## 验证

`PathDeckTests/PathLinkDetectorTests`（纯函数全覆盖：命中/负例/token 边界/标点剥离）。像素→格子换算与真实终端行读取无法脱离 GPU surface 单测，走 GUI 人工走查。

## 变更日志

- 2026-07-16 S39 FR-BRIDGE-003 #6 识别语法全集：`detect` 增 `cwd`/`home` 参数（相对路径仅挂 OSC 7 cwd，未知不触发；`~`/`~/…` 按注入 home 展开，`~user` 不支持）；`path:line[:col]` 剥离查存在、行列号进 `PathLink.line/column`（字面含冒号文件名优先）；引号区候选优先支持含空格路径（撇号假区落空回退）；`file://` percent-decode 后按本地路径处理 + `link(fromFileURL:probe:)` 供 OPEN_URL 改道；Windows 反斜杠自然 miss（负例测试）。`PathLinkDetectorTests` 15 → 36 例。
- 2026-07-16 S39 FR-BRIDGE-003 #5 模块落地：`PathLinkDetector` 首版（仅绝对路径形态）。⌘悬停反馈见 issue #7。
