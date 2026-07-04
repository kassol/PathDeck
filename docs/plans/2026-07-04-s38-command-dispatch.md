# S38 · Command Dispatch 收拢

来源：架构评审首推候选——键位三处分写（ShortcutRegistry 展示 / 6 个 per-window monitor
内联匹配 / SwiftUI 菜单字面量）、目标 Workspace 解析三套语义、真实派发路径零测试。
设计决策全文见 `docs/adr/0002-single-command-dispatch-table.md`；本文记录切片与验证。

## 里程碑

1. **M1 键位单源**（`56ac70f`）：`ShortcutSpec` 增 `match: KeyMatch`（char/keyCode/
   digit-range + `KeyModifiers`）、`dispatchVia`、`targetPolicy`、`indexedAction`、
   `isReservedInTerminal: Bool`；键帽 `keys` 与终端拦截 `reservedInTerminal` 改为派生。
   零行为变化；守卫测试升级（matcher 查重 / 键帽快照 / 分类断言）。
2. **M2 resolve 纯函数**（`aa2168f`）：`CommandDispatch.resolve(stroke, focus, target)`，
   R1 仲裁 + textEditing 放行 + focus nil 仅 allowsFallback。矩阵测试 11 例。
3. **M3 全局 adapter**：`WorkspaceManager.installCommandMonitor`（app 级唯一 monitor，
   AppDelegate 启动装载；测试经 `dispatchCommand(for:context:)` 测试缝喂合成 NSEvent）；
   删 `WorkspaceController` 5 个键位 monitor（浮窗 hold-tracker 保留）；⌘1–9 行为收进
   `indexedAction`（原 monitor 与菜单各写一份）；菜单 `.keyboardShortcut` 全部改
   `menuShortcut(id)` 派生。adapter 测试 6 例，含 S32 回归（文件焦点 ⌘T）。
4. **M4 文档**：ADR-0002、CONTEXT.md「Command Dispatch」术语、AGENTS.md ×2 同步。

## 行为变化（评审时逐条确认）

- ⌘⇧T 终端焦点且终端关闭历史为空 → 回退重开窗口（原吞键 no-op）。
- ⌘↑ Go to Parent 获得实际键盘绑定（原无任何派发路径，仅浮窗展示）。
- ⌘1–9 目标 tab 越界时吞键 no-op（原放行；无可观察差异）。

## 验证

- `xcodebuild ... -only-testing:PathDeckTests -parallel-testing-enabled NO test`：
  309 tests / 36 suites 全绿。**注意必须禁并行**：并行 test worker 会各自拉起
  test host，与 app 单实例约束冲突，报 `IDELaunchErrorDomain Code=20`
  （"LAUNCHING: … is already running"）。
- 手动走查（键盘派发涉及真实事件序，程序覆盖之外）：
  1. 文件焦点按 ⌘T → 新 workspace tab；终端焦点按 ⌘T → 新终端 session。
  2. 终端焦点按 ⌘W（有活动终端）→ 关终端；无终端 → 关窗口。
  3. inline rename 进行中按 ⌘⌫ → 删至行首（不移废纸篓）；按 ⌘T → 不新建 tab。
  4. Settings 为 key：⌘⇧. 生效、⌘B 无动作、⌘W 关 Settings。
  5. 文件焦点按 ⌘↑ → 返回上级目录（新增绑定）。
  6. 终端内 ⌘C/⌘V → 终端复制粘贴不受拦截；⌃⇥ → 切窗口 tab。
