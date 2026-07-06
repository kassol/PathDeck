# 单表命令派发：全局 monitor + R1 仲裁

全部直接动作型 Command 的 keystroke 派发收敛为一条路径：全局唯一 NSEvent monitor
（`WorkspaceManager.installCommandMonitor`）→ `CommandDispatch.resolve` 纯函数 →
`ShortcutRegistry` 命令表 action（S38）。键位以机器可匹配的 `KeyMatch` 单源存储，
键帽 token、SwiftUI 菜单键位、终端拦截三元组、monitor 匹配谓词全部派生。

背景：手动 NSWindow + 无 WindowGroup 架构下，SwiftUI `.keyboardShortcut` 在纯 AppKit
first responder（FileNSOutlineView / GhosttySurfaceView）时不派发，S32 曾因此让文件焦点
⌘T 静默失效；此前修法是逐键加 per-window monitor，导致同一键位写三份（registry 展示、
monitor 内联匹配、菜单字面量）、目标 Workspace 解析三套语义、真实派发路径零测试。

## 决策要点

- **派发方式表内声明**（`dispatchVia`）：直接动作型 → `monitor`；responder-chain 型
  （⌘C/⌘V/⌘D/⌘A/⌘⌥V）→ `menuOnly`（monitor 吞键会劫持文本编辑）；裸键（↩/Space）与
  ⌘↓ → `viewLocal`（裸键匹配必吞正常输入；⌘↓ 因 Quick Look 面板 handle-event 直调
  `outlineView.keyDown` 绕过 monitor，须留在视图）。
- **R1 仲裁**：同一 keystroke 候选按「语境精确 > global > 跨语境」排序，首个 isEnabled
  执行；全部不可用放行事件。后果：⌘⇧T 终端焦点且终端关闭历史为空时回退重开窗口
  （原 monitor 吞键 no-op），对齐「重开最近关闭之物」心智。
- **textEditing 语境一律放行**：first responder 为 NSText（inline rename / 搜索框 /
  Palette 输入框）时 monitor 不参与——否则重命名中 ⌘⌫ 会把正在改名的文件移入废纸篓。
- **目标解析归一**（`targetPolicy`）：严格 key workspace 为默认；仅全局偏好 / 全局
  窗口栈型命令声明 `allowsFallback`，keyWindow 非 workspace window（Settings/alert）时
  只有它们执行，其余放行给系统与菜单（Settings 的 ⌘W 仍关 Settings）。
- **菜单键位派生**：SwiftUI `.keyboardShortcut` 从 `KeyMatch` 派生，仅作菜单显示与
  非 workspace keyWindow 的兜底；⌘1–9 行为收进表内 `indexedAction`。

## Considered Options

- **维持 per-window monitor + 手写三份键位**：拒绝——改一个键要同步三个文件，
  S36/S37 连续两个 sprint 在此区域返工，回归无测试防护。
- **全量命令（含 responder-chain 型）走 monitor**：拒绝——⌘C/⌘V 必须留给
  responder 链，吞键破坏文本编辑与终端内复制粘贴。
- **仲裁规则 R2（语境精确即终局，禁用一律放行菜单）**：拒绝——回退路径重新依赖
  SwiftUI 菜单派发的可靠性，与本决策的动机相悖。

## Consequences

- **（2026-07-05 补充，⌘T 双开回归实测）local monitor 返回 nil 只拦截事件向
  window/responder 的继续派发，拦不住同一次 `sendEvent` 内的菜单 key-equivalent
  处理**（判别实验：只 dequeue 不 sendEvent 时 monitor 零触发且事件原样返回——
  monitor 挂在 sendEvent 内部；带 sendEvent 时 monitor 与菜单各执行一次）。因此
  monitor 型命令的菜单执行必须经 `CommandDispatch.menuShouldRun` 守卫：键盘触发
  （`NSApp.currentEvent` 为 keyDown）一律跳过，鼠标点击照常。S38 之前不双开是因为
  per-window monitor 场景下 SwiftUI 菜单派发本来就死（S32 已知），并非 nil 抑制成立。

- 改键位 / 加命令只改 `ShortcutRegistry`；monitor、菜单、浮窗、Palette、终端拦截自动跟随。
- 派发决策可测：`CommandDispatchTests` 矩阵（键 × 焦点 × enabled）+
  `CommandMonitorAdapterTests` 合成 NSEvent（含 S32 回归）。
- **monitor 型命令的键位不得在视图层再绑 `.keyboardShortcut`**（2026-07-06 回归实证：
  WorkspaceRootView 面包屑按钮的 ⌘↑ 视图级快捷键与 monitor 双发——视图级快捷键
  同样不受 monitor 返回 nil 抑制）。视图按钮保留点击，键位一律交 CommandDispatch。
- **monitor 对已认领键位的 isARepeat 吞而不执行**：菜单 key-equivalent 天然不响应
  按键重复，前菜单键（⌘⇧. 等）迁到 monitor 后必须保持同语义，否则长按连发
  （偶数次 toggle 视觉上「失效」，2026-07-06 回归）。
- 新增可派发快捷键时默认 `dispatchVia: .monitor`，不再评估「SwiftUI 会不会派发」。
