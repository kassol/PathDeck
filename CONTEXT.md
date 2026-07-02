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
