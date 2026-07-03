# Return 重命名、⌘↓ 打开（完全对齐 Finder）

文件列表的 Return 键语义定为 inline 重命名（自 S35 起已如此实现），打开选中项绑 ⌘↓（S36 新增，与既有 ⌘↑ 上级目录对称），双击与 Space Quick Look 不变——完全复刻 Finder 的键位语义，复用 macOS 用户最强的肌肉记忆。S36 评审曾考虑改为「Return=打开」的列表型 app 惯例，明确否决。

## Considered Options

- **Return=打开、⌘⇧R 给文件重命名**：拒绝——高频动作不该配次级键位，且与 Finder 语义相反，两套心智并存。
- **Return=打开、重命名无键位**：拒绝——重命名是文件管理器的一级操作。

## Consequences

- Return 只在无修饰键时触发重命名（⌘↩ 属 Send Path to Terminal，见 `docs/plans/2026-07-03-s36-shortcut-overhaul.md` 键位总表）。
- 键盘打开路径 = ⌘↓，与双击共用同一打开逻辑（目录进入、文件交系统默认 app）。
