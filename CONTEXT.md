# PathDeck

macOS 原生文件工作台：Finder 式文件列表 + 内嵌真终端（libghostty），一个窗口一个 workspace。

## Language

### 持久化

**Preference（全局偏好）**:
跨所有 workspace 窗口共享的用户偏好，改一处处处生效；重启后所有窗口拿到同一份。判据：与"哪个窗口"无关的用户习惯（排序、显示隐藏文件、列宽、面板尺寸）。
_Avoid_: 设置（保留给 Settings 界面本身）、配置

**Session State（会话快照）**:
单个窗口的布局快照，按窗口记录、重启时逐窗还原。判据：描述"这个窗口长什么样"（cwd、tab 分组、窗口 frame、终端 tab、模式）。
_Avoid_: 偏好、缓存

### 工作台

**Workspace**:
一个 NSWindow 承载的工作单元：文件列表 + 终端面板 + 独立 cwd。窗口即 workspace。
_Avoid_: Tab（系统 window tab 是 workspace 的宿主形态，不是概念本身）

**Anchor（锚点）**:
终端会话所锚定的目录；文件列表导航离开后，路径栏保留回锚点的入口。

**Sidebar（侧边栏）**:
窗口左列的收藏与固定目录导航区。
_Avoid_: 左侧边栏（指代同一物时统一用 Sidebar）

**Preview Pane（预览面板）**:
文件列表右侧的选中项预览区。
_Avoid_: 右侧边栏、Inspector

### 快捷键与命令

**Command（命令）**:
一条可被用户触达的动作，键位、标题、焦点语境、可用条件全局唯一定义；菜单、快捷键、Command Palette 是同一命令的三种入口。
_Avoid_: 动作、操作（泛指手势时可用，指这一概念时统一用 Command）

**Command Dispatch（命令派发）**:
keystroke 到 Command 的唯一决策路径：全局 monitor 捕键，按命令表（键位 matcher、焦点语境、
可用条件、目标 policy）仲裁出应执行的 Command 或放行。键位只在命令表存一份，菜单显示、
浮窗、终端拦截皆派生。
_Avoid_: 快捷键处理、按键路由

**Command Palette（命令面板）**:
⌘⇧P 呼出的窗口内命令搜索浮层：全量命令可搜、不可用置灰，模糊匹配、回车执行，作用于所在窗口。
_Avoid_: 命令中心、快速操作

**Shortcut Overlay（快捷键浮窗）**:
长按 ⌘ 呼出的全量快捷键速查层，松开 ⌘ 即隐，纯展示不可交互。
_Avoid_: HUD、快捷键面板

**Reserved Shortcut（预留键位）**:
键位表中已规划未来用途、当前不绑定任何动作的组合键；不出现在菜单与浮窗中。

### 关闭与重开

**Close History（关闭历史）**:
可被 ⌘⇧T 逆序重开的关闭记录，栈式、仅存活于本次运行。终端的关闭历史属于其 Workspace，窗口的关闭历史全局共享。仅用户关闭手势（⌘W、关闭按钮）入栈；shell 内 exit 属主动终止，不入栈。
_Avoid_: 重开栈、回收站

**Reopen（重开）**:
按 Close History 快照重建：窗口恢复 cwd、布局与终端组构成，终端恢复 cwd 与标题；已死的 shell 进程状态不可恢复。
_Avoid_: 撤销关闭、还原
