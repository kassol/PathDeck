# AGENTS.md — ContextBridge

> 文件 ↔ Terminal 双向上下文桥模块。本文就近覆盖根 `AGENTS.md`。

## 职责

承载 Context Bridge 中「终端输出 → 文件工作台」方向的纯逻辑：把终端一行文本解析成可 Locate 的 Path Link（FR-BRIDGE-003，点击语义见 `docs/adr/0003-cmd-click-locates-never-opens.md`，术语见根 `CONTEXT.md`「文件与终端联动」）。

「文件 → 终端」方向（Send Path、cwd 双向同步）历史上散落在 `FileWorkspace` / `Terminal` / `Workspace`，暂不回迁。

## 目录结构

- `PathLinkDetector.swift` — `PathLink` 值类型（url + isDirectory）+ `PathLinkDetector.detect(line:index:probe:)` 纯函数：token 切分（空白边界）→ 剥离前导包裹符 → 绝对路径前缀判定 → 尾部标点逐字符剥离且每步做存在性检查（防吃掉扩展名的点）。存在性经 `probe` 闭包注入（生产 `fileSystemProbe`，测试注假文件系统）。

## 模块规范

- 本模块只依赖 Foundation：不 import AppKit / GhosttyKit / SwiftUI。像素/格子换算、`ghostty_surface_read_text` 等宿主事实属 `Terminal/GhosttySurfaceView`；Locate 的执行（navigate/reveal）属 `Workspace/WorkspaceController.locate`。
- 检测器保持纯函数 + 注入式存在性检查，新增识别形态（相对路径、`~`、`path:line`、引号包裹、file://，见 issue #6）必须先补 `PathLinkDetectorTests` 再实现。
- 解析不出目标或目标不存在的文本段不构成 Path Link——存在性检查是构造 `PathLink` 的前提，不允许绕过。

## 依赖关系

依赖 Foundation。被 `Terminal/GhosttySurfaceView`（⌘Click 命中检测）引用；`PathLink` 值类型贯穿 `TerminalEngine` 协议回调 → `WorkspaceManager` → `WorkspaceController.locate`。

## 验证

`PathDeckTests/PathLinkDetectorTests`（纯函数全覆盖：命中/负例/token 边界/标点剥离）。像素→格子换算与真实终端行读取无法脱离 GPU surface 单测，走 GUI 人工走查。

## 变更日志

- 2026-07-16 S39 FR-BRIDGE-003 #5 模块落地：`PathLinkDetector` 首版（仅绝对路径形态）。相对路径/cwd 语义/`~`/行号/引号/file:// 见 issue #6，⌘悬停反馈见 issue #7。
