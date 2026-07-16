# ⌘Click 路径只定位、不打开，行号解析保留不消费

Terminal 输出中的 Path Link 经 ⌘Click 在文件浏览器中 Locate（文件 reveal 并选中、目录导航进入），键盘焦点留在终端。`path:line[:col]` 的行列号照常解析并随结果保留，但当前不驱动任何行为——PathDeck 是 preview-only 工作台（PRD §21 Q3 把轻量编辑排到 post-MVP），Quick Look 与 Preview Pane 均无行定位能力，「打开并跳转到行」的闭环不存在。FR-BRIDGE-003 原验收标准「点击 src/main.ts:42 打开文件并定位行号」据此改写为定位语义。

## Considered Options

- **file:line 交外部编辑器打开（code -g 等）**：拒绝——引入编辑器配置项，把 bridge 闭环引出 PathDeck，与 local command workspace 定位相悖；用户要编辑可走 Open With。
- **Preview Pane 增加文本预览并滚动到行**：拒绝（本期）——等于顺带做一个文本查看器，范围失控；行号数据已保留，未来文本预览落地时直接消费。
- **不解析行号**：拒绝——`:line[:col]` 是路径 token 的一部分，不解析会把 `main.ts:42` 当成不存在的文件名，token 边界即错；也丢掉未来能力的地基。

## Consequences

- 行列号进入解析结果模型但暂无消费方；未来文本预览或外部编辑器集成可直接取用。
- 「不存在路径不误触发」由存在性检查保证；`main.ts:42` 需剥离行列号后再做存在性检查。
- Locate 不转移焦点，延续弱绑定锚点哲学：终端是主战场，文件浏览器随动不夺焦。
