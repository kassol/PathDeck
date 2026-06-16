# PRD：PathDeck — Finder-first Command Workspace for macOS

> 版本：v0.2 Draft  
> 日期：2026-06-13  
> 平台：macOS  
> 项目名：PathDeck  
> App 名称：PathDeck  
> Repo 名：pathdeck  
> CLI helper：pathdeck  
> URL Scheme：pathdeck://  
> Bundle ID：in.riverflows.PathDeck  
> Tagline：A Finder-first command workspace for macOS.  
> 核心定位：一个 Finder-first 的 macOS 命令工作台：以文件浏览为主导，原生集成高质量 Terminal，并透明感知文件变化。

---

## 0. 一句话定义

PathDeck 是一个 **Finder-first 的 macOS 文件工作台**：用户以文件夹、文件、预览、搜索、整理为主心智工作；需要命令行时，Terminal 就在当前文件上下文中自然出现；Terminal 中运行的任意 CLI、脚本或第三方 AI coding agent 对文件系统造成的变化，会被 App 自动感知、聚合、展示，并尽可能提供预览与恢复能力。

---

## 1. 背景与发心

### 1.1 现状问题

macOS 用户在处理文件、项目、资料、下载内容、脚本任务、AI CLI agent 时，通常需要在以下工具之间频繁切换：

```txt
Finder
Terminal
编辑器 / IDE
Quick Look
Git / diff 工具
AI CLI agent
第三方文件管理器
```

这些工具各自强，但上下文割裂：

| 工具 | 优点 | 主要问题 |
|---|---|---|
| Finder | 原生、稳定、文件浏览直觉强 | 批处理弱、terminal 弱、上下文操作弱、变化可见性弱 |
| Terminal | 操作能力强、可运行任意 CLI | 文件浏览弱、预览弱、变化不可见、上下文依赖用户手动维护 |
| AI CLI Agent | 能自动执行任务 | 文件改动不透明、结果散落在 terminal 输出和文件系统中 |
| IDE | 代码能力强 | 与普通文件工作流绑定过重，不适合所有文件场景 |

PathDeck 的核心发心不是做一个 coding IDE，也不是做一个 Agent Runtime，而是解决：

```txt
Finder 看文件强，但操作弱；
Terminal 操作强，但上下文弱；
CLI Agent 能做事，但对文件变化不可见。
```

### 1.2 产品机会

用户真正需要的是一个 **文件工作台**：

```txt
以 Finder 的方式进入
以 Terminal 的能力执行
以 Preview / Recent Changes 的方式理解结果
```

这意味着产品主心智应是：

```txt
Folder
File
Selection
Preview
Search
Recent Changes
Terminal Here
```

而不是：

```txt
Agent
Session
Branch
Worktree
Task Graph
Runtime
```

---

## 2. 产品定位

### 2.1 定位语

**A Finder-first command workspace for macOS.**

中文表达：

> 一个长出 Terminal、能看见文件变化的 Finder 工作台。

品牌短句：

> PathDeck：文件路径上的 command deck。

### 2.1.1 命名规范

| 项 | 值 | 说明 |
|---|---|---|
| Project | PathDeck | 对外项目名 |
| App | PathDeck | macOS App 名称 |
| Repo | pathdeck | GitHub / package 命名建议 |
| CLI helper | pathdeck | 后续如需提供命令行入口，使用小写命名 |
| URL Scheme | pathdeck:// | 用于从 Finder、Service、脚本或浏览器唤起 App |
| Internal codename | Deck | 内部模块、设计稿、任务板可使用的短名 |

---

### 2.2 不是做什么

PathDeck 不是：

```txt
不是 AI Agent IDE
不是 coding-first 工作台
不是 Git worktree 管理器
不是 Agent Profile 管理器
不是 Claude Code / Codex / Kimi Code 的封装器
不是 Finder Extension 拼装产品
```

### 2.3 是做什么

PathDeck 是：

```txt
完整 macOS 原生 App
Finder-like 文件工作台
高质量内嵌 Terminal Host
Terminal 与文件系统之间的上下文桥
透明文件变化记录层
普通文件、资料、项目、脚本、AI CLI agent 的统一工作界面
```

---

## 3. 目标与非目标

### 3.1 产品目标

| 编号 | 目标 | 说明 |
|---|---|---|
| G1 | 以 Finder-like 体验作为主界面 | 用户首先是在浏览、管理、预览文件，而不是进入 IDE 或 Agent 控制台 |
| G2 | 原生集成高质量 Terminal | Terminal 应像文件视图的一部分，而不是外部窗口 |
| G3 | 支持任意 CLI / Agent | 用户可在 Terminal 中自由运行 claude、codex、kimi、bub、aider、ssh、python、ffmpeg、rsync 等 |
| G4 | 打通文件与 Terminal 上下文 | 选中文件、路径、预览内容、Terminal cwd、Terminal 输出路径之间自然流转 |
| G5 | 透明记录文件变化 | 用户不需要理解 Git，也能知道最近发生了什么、哪些文件被创建/修改/删除 |
| G6 | 尽可能提供预览和恢复 | 对适合的文件提供 before/after、版本、恢复上一版等能力 |
| G7 | 保持普通用户心智低负担 | 不强迫用户理解 branch、worktree、agent profile、runtime、tool calling |

### 3.2 非目标

| 编号 | 非目标 | 说明 |
|---|---|---|
| NG1 | 不做内置 Agent Runtime | 不负责 planner、tool calling、memory、multi-agent orchestration |
| NG2 | 不为每个 Agent 做深度 adapter | 不强绑定 Claude Code、Codex、Kimi Code 等 CLI 行为 |
| NG3 | 不把 Git 作为用户主心智 | Git 可作为内部辅助能力，但不能让普通用户承担 Git 概念 |
| NG4 | 不承诺任意 Terminal 操作 100% 可撤销 | 对任意 CLI 写入，只能尽力观察、记录和恢复有快照的内容 |
| NG5 | 不做 Finder 插件型产品 | Finder Extension 只作为入口，主体必须是完整 App |
| NG6 | 不优先跨平台 | 第一阶段聚焦 macOS 原生体验 |

---

## 4. 目标用户

### 4.1 核心用户画像

#### Persona A：重度 macOS 文件工作者

```txt
使用 Finder、Downloads、Documents、iCloud Drive、外置盘、项目文件夹频繁处理文件。
经常需要预览、重命名、整理、搜索、批处理。
偶尔需要 Terminal，但不想频繁切换窗口。
```

核心诉求：

```txt
更强的文件浏览
更快的预览
更方便的路径操作
更低摩擦地打开 Terminal
知道刚刚发生了哪些文件变化
```

#### Persona B：CLI 熟练用户

```txt
每天使用 Terminal、shell、ssh、脚本、包管理器、ffmpeg、rsync 等。
对 Finder 的可视化能力有需求，但不希望离开命令行工作流。
```

核心诉求：

```txt
Terminal 和当前文件夹绑定
拖文件到 Terminal 插入路径
Terminal 输出路径可点击
运行命令后立即看到生成/修改文件
```

#### Persona C：AI CLI Agent 使用者

```txt
使用 Claude Code、Codex、Kimi Code、aider、bub 等 CLI agent。
不一定只做代码，也可能整理资料、生成文档、处理文件、批量改名。
```

核心诉求：

```txt
Agent 改了什么要看得见
新文件在哪里要自动浮现
修改前后能预览
不希望被迫使用某个 Agent 管理系统
```

#### Persona D：轻量开发者 / 创作者

```txt
经常在项目文件夹、素材文件夹、文档文件夹、脚本目录之间切换。
既需要 Finder，又需要 Terminal，但不想打开完整 IDE。
```

核心诉求：

```txt
一个轻量工作台
能浏览、预览、运行命令、查看变化
比 Finder 强，比 IDE 轻
```

---

## 5. 核心使用场景

### 5.1 场景一：在文件夹中自然打开 Terminal

用户打开一个文件夹，浏览文件时发现需要运行命令。

期望流程：

```txt
打开文件夹
↓
浏览文件 / 预览内容
↓
点击 Open Terminal Here
↓
底部或右侧出现 Terminal
↓
Terminal cwd 自动为当前文件夹
↓
用户运行任意命令
```

成功标准：

```txt
不用复制路径
不用切换到外部 Terminal
不用 cd 到目录
```

---

### 5.2 场景二：文件选择与 Terminal 打通

用户在文件列表中选中一个或多个文件，希望把路径发给 Terminal。

期望能力：

```txt
选中文件 → Send Path to Terminal
拖文件 → Terminal 自动插入 shell-escaped path
右键 → Copy Relative Path / Copy Absolute Path
预览中选中文本 → Send Selection to Terminal
```

成功标准：

```txt
路径正确转义
多文件路径格式可控
Terminal 不丢失当前输入状态
```

---

### 5.3 场景三：Terminal 生成文件后自动可见

用户在 Terminal 中运行命令：

```txt
python script.py
ffmpeg ...
claude
codex
kimi
npm run build
```

App 自动观察到文件变化。

期望表现：

```txt
新文件在文件列表中高亮
Recent Changes 显示新增/修改/删除
相关文件可直接预览
文本类文件可显示前后差异
```

成功标准：

```txt
用户不需要重新打开 Finder
用户不需要手动 find 文件
用户能知道刚才命令造成了什么变化
```

---

### 5.4 场景四：AI CLI Agent 修改文件后查看结果

用户在 Terminal 中运行任意第三方 AI CLI agent。

期望流程：

```txt
打开项目/文件夹
↓
打开 Terminal
↓
用户自行运行 claude / codex / kimi / bub / aider 等
↓
Agent 修改或生成文件
↓
PathDeck 自动聚合 Recent Changes
↓
用户查看文件、diff、preview
↓
必要时恢复上一版
```

成功标准：

```txt
App 不需要知道具体是哪种 Agent
用户不需要配置 Agent Profile
Agent 造成的文件变化仍然能被看见
```

---

### 5.5 场景五：普通文件整理

用户下载了一批文件，希望整理、重命名、预览和批处理。

期望能力：

```txt
Finder-like 浏览
快速预览
批量 rename
标签/收藏
搜索
需要时打开 Terminal 跑脚本
Recent Changes 展示整理结果
```

成功标准：

```txt
不需要打开 IDE
不需要外部 Terminal
不需要复杂自动化工具
```

---

## 6. 产品设计原则

| 原则 | 说明 |
|---|---|
| Finder-first | 文件浏览和管理是主入口，Terminal 是增强能力 |
| Terminal-native | Terminal 必须是真 terminal，不是玩具命令框 |
| Agent-agnostic | 不内置、不绑定、不假设用户使用哪种 Agent |
| Transparent | 自动观察变化，但不制造额外心智负担 |
| Low-friction | 常见动作一步完成：打开、预览、复制路径、Terminal Here |
| Native macOS | 交互、性能、权限、拖拽、预览都应符合 macOS 习惯 |
| Progressive Power | 普通用户只看到简单能力，高级用户可启用版本、规则、自动化 |
| Safe by Default | 不主动扩大权限，不默默删除，不承诺不可实现的完全回滚 |

---

## 7. 信息架构

### 7.1 主界面结构

```txt
┌─────────────────────────────────────────────────────────────┐
│ Toolbar: Back / Forward / Path / Search / View / Terminal    │
├──────────────┬────────────────────────┬─────────────────────┤
│ Sidebar      │ File Browser           │ Preview / Inspector │
│              │                        │                     │
│ Favorites    │ List / Column / Grid   │ Quick Look          │
│ Recents      │ Sort / Filter          │ Metadata            │
│ Workspaces   │ Selection              │ Versions            │
│ Tags         │ Highlight Changes      │ Actions             │
│ Changes      │                        │                     │
├──────────────┴────────────────────────┴─────────────────────┤
│ Terminal Panel / Recent Changes Panel                        │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 主要区域

| 区域 | 说明 |
|---|---|
| Sidebar | 收藏、最近位置、工作区、标签、最近变化 |
| File Browser | 文件夹内容主视图，支持列表、列视图、图标/画廊视图 |
| Preview Pane | 文件预览、元数据、版本、操作 |
| Terminal Panel | 内嵌 Terminal，可底部/右侧/独立 tab 展示 |
| Recent Changes | 当前文件夹/工作区的文件变化聚合 |
| Command Palette | 快速执行常见动作，如 Terminal Here、Copy Path、Reveal Changes |

---

## 8. 功能需求总览

优先级定义：

```txt
P0：MVP 必须具备
P1：Beta 必须具备
P2：增强能力
P3：长期愿景
```

---

## 9. 功能需求明细

## 9.1 文件工作台

### FR-FILE-001：打开文件夹 / 工作区

优先级：P0

用户可以从 App 内打开任意本地文件夹作为当前工作区。

验收标准：

```txt
支持 Open Folder
支持最近打开列表
支持窗口恢复上次打开路径
支持权限不足时给出明确提示
```

---

### FR-FILE-002：Finder-like 文件浏览

优先级：P0

提供接近 Finder 的基础浏览能力。

功能包括：

```txt
文件列表
文件夹进入/返回
排序：名称、日期、大小、类型
隐藏文件开关
多选
拖拽
右键菜单
Reveal in Finder
Open With
Move to Trash
Rename
New Folder
```

验收标准：

```txt
常见文件夹内 10,000 个文件时仍可滚动浏览
多选操作符合 macOS 习惯
拖拽到 Finder / Terminal / App 内部路径有效
```

---

### FR-FILE-003：多视图模式

优先级：P1

支持多种文件展示方式。

```txt
列表视图
列视图
图标视图
画廊视图
```

验收标准：

```txt
用户可在 toolbar 切换视图
每个文件夹可记忆上次视图偏好
```

---

### FR-FILE-004：路径导航

优先级：P0

提供路径栏与面包屑导航。

验收标准：

```txt
可点击上级路径
可复制当前路径
可输入路径跳转
支持 ~ 展开
支持相对路径解析
```

---

## 9.2 Preview 能力

### FR-PREVIEW-001：基础文件预览

优先级：P0

支持常见文件的内置预览。

类型包括：

```txt
图片
PDF
文本
Markdown
代码文本
音频/视频基础信息
文件夹摘要
未知文件元数据
```

验收标准：

```txt
点击文件后 300ms 内显示元数据
常见图片/PDF/文本可直接预览
不支持的文件显示清晰 fallback
```

---

### FR-PREVIEW-002：Quick Look 集成

优先级：P0

支持 macOS Quick Look 式预览体验。

验收标准：

```txt
Space 键触发快速预览
支持缩略图生成
Preview Pane 与 Quick Look 快捷预览不冲突
```

---

### FR-PREVIEW-003：预览内容发送到 Terminal

优先级：P1

用户可以把预览中的路径、文本片段、文件引用发送到当前 Terminal。

验收标准：

```txt
文本选区可 Send to Terminal
文件路径可 Send Path to Terminal
Markdown section 可发送引用
发送内容可选择 plain text / quoted / heredoc 模式
```

---

## 9.3 Terminal Layer

### FR-TERM-001：内嵌 libghostty Terminal

优先级：P0

App 内集成基于 libghostty 的 Terminal 视图。

设计要求：

```txt
Terminal 应是真 PTY 会话
支持 zsh/fish/bash 等用户 shell
支持常见 ANSI/VT 序列
支持复制/粘贴
支持鼠标、选择、滚动
支持字体与主题设置
```

验收标准：

```txt
能运行用户默认 shell
能运行 vim / less / top / ssh 等 TUI 程序
复制粘贴符合 macOS 习惯
Terminal 可停靠在底部或右侧
```

技术备注：

```txt
通过 TerminalEngine 协议隔离 libghostty 依赖
避免业务逻辑直接绑定 libghostty 具体 API
```

---

### FR-TERM-002：Open Terminal Here

优先级：P0

在当前文件夹上下文中打开 Terminal。

触发入口：

```txt
Toolbar 按钮
右键菜单
快捷键
Command Palette
Sidebar folder context menu
```

验收标准：

```txt
Terminal cwd 为当前文件夹
已有 Terminal 可选择复用或新建
文件浏览器路径变化时可选择是否同步 Terminal cwd
```

---

### FR-TERM-003：多 Terminal Pane / Tab

优先级：P1

支持多个 Terminal 会话。

验收标准：

```txt
支持新建 Terminal tab
每个 tab 保持独立 cwd、进程、scrollback
可重命名 tab
可关闭 tab
关闭含有活跃进程的 tab 时需要确认
```

---

### FR-TERM-004：Terminal 与文件夹绑定

优先级：P0

Terminal 会话与当前工作区/文件夹建立弱绑定。

记录信息：

```txt
terminal_id
workspace_id
cwd
created_at
last_active_at
associated_folder
```

验收标准：

```txt
切换文件夹时可显示相关 Terminal
Terminal 当前 cwd 可在 UI 中显示
Terminal 活跃期间产生的文件变化可被归入该 Terminal 时间窗口
```

---

### FR-TERM-005：任意 CLI / Agent 支持

优先级：P0

用户可以在 Terminal 中自由运行任意命令或第三方 CLI agent。

验收标准：

```txt
不要求配置 Agent Profile
不限制可执行命令
不要求 App 知道具体 agent 类型
支持用户自定义 shell 环境
```

明确不做：

```txt
不为 Claude Code / Codex / Kimi Code / Bub 做深度适配
不解析 agent 私有协议
不接管 agent 权限模型
```

---

### FR-TERM-006：命令预设

优先级：P2

提供轻量 command preset，而不是 Agent Profile。

示例：

```txt
New Terminal
New Terminal with Command...
Pin Command: claude
Pin Command: codex
Pin Command: npm run dev
Pin Command: python script.py
```

验收标准：

```txt
用户可添加/编辑/删除预设
预设只包含 command、args、cwd 策略、env override
预设不包含 agent runtime 语义
```

---

## 9.4 Context Bridge

### FR-BRIDGE-001：Send Path to Terminal

优先级：P0

用户可将选中文件/文件夹路径发送到当前 Terminal。

触发方式：

```txt
右键菜单
快捷键
拖拽
Command Palette
Toolbar action
```

发送格式：

```txt
绝对路径
相对路径
shell-escaped path
多路径空格分隔
多路径换行分隔
```

验收标准：

```txt
空格、引号、特殊字符路径必须正确转义
多选文件顺序与 UI 选择顺序一致
若 Terminal 当前有输入，插入行为不破坏用户已有内容
```

---

### FR-BRIDGE-002：拖拽文件到 Terminal

优先级：P0

拖拽文件到 Terminal 后自动插入 shell-escaped path。

验收标准：

```txt
支持单文件/多文件
支持文件夹
支持 Option/Command 修饰键切换绝对/相对路径
```

---

### FR-BRIDGE-003：Terminal 输出路径可点击

优先级：P1

Terminal 输出中的路径应可识别并点击打开。

能力包括：

```txt
相对路径识别
绝对路径识别
file:line 格式识别
URL 识别
点击后在文件浏览器中定位或预览
```

验收标准：

```txt
点击 README.md 打开当前 cwd 下 README.md
点击 src/main.ts:42 打开文件并定位行号
不存在路径不误触发
```

---

### FR-BRIDGE-004：Terminal cwd 与文件浏览器同步

优先级：P1

Terminal cwd 变化时，App 可感知并提供同步操作。

设计要求：

```txt
默认不强制文件浏览器跟随 Terminal cwd
提供 Follow Terminal CWD 开关
提供 Reveal Terminal CWD 操作
```

验收标准：

```txt
Terminal cd 到新目录后，UI 能展示当前 cwd
用户点击 cwd 可让文件浏览器跳转
```

---

### FR-BRIDGE-005：当前选择上下文发送

优先级：P1

将当前选择作为上下文发送到 Terminal。

发送内容可包括：

```txt
文件路径
文件名
相对路径
文件摘要
预览选中文本
```

验收标准：

```txt
默认只发送路径，避免隐私泄露
发送文件内容前必须由用户显式选择
```

---

## 9.5 Recent Changes / Change Journal

### FR-CHANGE-001：工作区文件变化监听

优先级：P0

App 在用户打开工作区后，自动监听文件系统变化。

记录事件：

```txt
created
modified
deleted
renamed
moved
metadata_changed
```

验收标准：

```txt
文件创建后在 Recent Changes 出现
文件修改后在 Recent Changes 出现
文件删除后记录路径与时间
大批量变更需聚合展示，不能刷屏
```

---

### FR-CHANGE-002：Recent Changes 面板

优先级：P0

提供用户可理解的变化聚合，而不是原始 event log。

展示方式：

```txt
Just now
5 min ago
Today
Yesterday
This week
```

变化分组示例：

```txt
刚刚新增 3 个文件
刚刚修改 7 个文件
当前 Terminal 活跃期间产生 12 个变化
Downloads 中删除 2 个文件
```

验收标准：

```txt
点击变化组可展开文件列表
点击文件可预览
变化条目可过滤：新增/修改/删除/重命名
```

---

### FR-CHANGE-003：Terminal 活跃期间变化归因

优先级：P1

在不深度监控进程的前提下，将文件变化弱关联到活跃 Terminal 时间窗口。

归因原则：

```txt
Terminal Pane 处于活跃状态
Terminal cwd 位于当前工作区内
文件变化发生在命令运行或输出活跃窗口附近
```

验收标准：

```txt
UI 文案使用“可能由当前 Terminal 产生”或“Terminal 活跃期间产生”
不宣称精确归因到某个命令或 Agent
```

---

### FR-CHANGE-004：轻量文件版本

优先级：P1

对适合的文件自动保存轻量版本。

默认适用：

```txt
文本文件
Markdown
JSON/YAML/XML
代码文本
CSV
小型配置文件
小于配置阈值的普通文档
```

默认不全量保存：

```txt
大型视频
大型压缩包
大型图片
大型二进制
node_modules
.git
build/dist/cache 目录
```

验收标准：

```txt
文本文件修改前后可查看差异
有快照的文件可恢复上一版
超过大小阈值时只记录元数据
用户可配置忽略规则与大小上限
```

---

### FR-CHANGE-005：Diff / Before After

优先级：P1

对文本类文件提供修改前后对比。

验收标准：

```txt
支持 inline diff
支持 side-by-side diff
支持从 Recent Changes 打开 diff
支持从 Preview Pane 打开版本比较
```

用户文案：

```txt
查看变化
比较上一版
恢复上一版
```

避免使用：

```txt
git diff
checkout
branch
worktree
```

---

### FR-CHANGE-006：恢复上一版

优先级：P1

对有快照的文件提供恢复能力。

验收标准：

```txt
恢复前展示确认
恢复操作本身也进入 Change Journal
恢复后可再次撤销到恢复前版本
删除文件若无快照，只展示删除记录，不承诺恢复
```

---

### FR-CHANGE-007：变化忽略规则

优先级：P1

用户可配置不监听或不展示的目录/文件。

默认忽略示例：

```txt
.git
node_modules
.DS_Store
build
dist
.cache
venv
__pycache__
```

验收标准：

```txt
默认忽略规则可查看
用户可添加 glob 规则
Recent Changes 中可临时显示被忽略变化
```

---

## 9.6 搜索与筛选

### FR-SEARCH-001：文件名搜索

优先级：P0

支持当前文件夹/工作区内按文件名搜索。

验收标准：

```txt
支持模糊匹配
支持最近搜索
支持按类型/大小/时间过滤
```

---

### FR-SEARCH-002：内容搜索

优先级：P1

支持文本内容搜索。

验收标准：

```txt
支持文本文件内容索引
支持按文件类型过滤
支持点击结果进入 Preview
```

---

### FR-SEARCH-003：变化搜索

优先级：P1

支持搜索 Recent Changes。

示例：

```txt
今天修改的 PDF
刚刚新增的图片
当前 Terminal 活跃期间生成的文件
```

验收标准：

```txt
可按时间、事件类型、路径、文件类型筛选变化记录
```

---

## 9.7 Finder 外围入口

### FR-EXT-001：Finder 右键 Open in PathDeck

~~优先级：P1~~ → **Kill**

通过 FinderSync Extension 提供从 Finder 进入 PathDeck 的右键菜单入口。

**决策**：Kill FinderSync Extension。FinderSync 只能承载右键菜单，无法提供主工作台能力；投入产出比不足。外部入口由 Services + URL Scheme + Open With + CLI helper 覆盖，已满足从外部唤起 PathDeck 的全部场景。

---

### FR-EXT-002：Finder 右键 Open Terminal Here in PathDeck

~~优先级：P2~~ → **Kill**（同 FR-EXT-001 理由：FinderSync Extension 承载不了主工作台能力）

---

### FR-EXT-003：URL Scheme

优先级：P1

支持通过 URL Scheme 打开路径或触发动作。

示例：

```txt
pathdeck://open?path=/Users/me/Downloads
pathdeck://terminal?path=/Users/me/Project
```

验收标准：

```txt
路径解析安全
无权限路径需要用户确认
```

---

## 9.8 设置与偏好

### FR-SETTINGS-001：Terminal 设置

优先级：P0

设置项：

```txt
默认 shell
字体
字号
主题
光标样式
scrollback 行数
打开位置：底部/右侧
默认 cwd 策略
```

---

### FR-SETTINGS-002：Change Journal 设置

优先级：P1

设置项：

```txt
是否启用 Recent Changes
是否启用轻量版本
快照文件大小上限
忽略目录
保留时间
最大磁盘占用
```

---

### FR-SETTINGS-003：隐私设置

优先级：P1

设置项：

```txt
是否保存 Terminal scrollback
是否保存 Terminal transcript
是否索引文件内容
是否保存文件版本
是否允许崩溃日志附带路径信息
```

默认原则：

```txt
敏感内容默认不上传
Terminal transcript 默认不做云同步
文件内容索引和版本保存需要清晰说明
```

---

## 10. 用户体验流程

## 10.1 首次启动

```txt
启动 App
↓
欢迎页：Open Folder / Recent / Preferences
↓
用户选择文件夹
↓
系统权限确认
↓
进入 Finder-like Workspace
↓
提示：可按快捷键打开 Terminal
```

首启文案重点：

```txt
管理文件
打开 Terminal
查看最近变化
```

避免首启强调：

```txt
AI Agent
Git
Worktree
Runtime
```

---

## 10.2 打开 Terminal

```txt
用户在文件夹中点击 Terminal 按钮
↓
底部展开 Terminal
↓
Terminal 自动进入当前目录
↓
用户运行任意命令
↓
文件变化自动出现在 Recent Changes
```

---

## 10.3 文件发送到 Terminal

```txt
用户选中 3 个文件
↓
右键 Send Path to Terminal
↓
Terminal 当前光标处插入 shell-escaped paths
↓
用户继续输入命令或按 Enter
```

可选弹层：

```txt
Send as:
- Absolute paths
- Relative paths
- Newline separated
- Quoted list
```

---

## 10.4 查看 Terminal 造成的变化

```txt
Terminal 中运行命令
↓
文件系统发生变化
↓
Recent Changes badge 更新
↓
用户点击 Recent Changes
↓
看到“刚刚新增 4 个文件，修改 2 个文件”
↓
点击文件查看 preview / diff
↓
必要时恢复上一版
```

---

## 10.5 恢复上一版

```txt
用户在 Recent Changes 中打开一个修改过的文本文件
↓
点击 Compare with Previous Version
↓
查看 before / after
↓
点击 Restore Previous Version
↓
确认
↓
文件恢复，恢复动作进入 Recent Changes
```

---

## 11. 技术架构

## 11.1 总体架构

```txt
PathDeck.app
├── Native macOS App Layer
│   ├── SwiftUI shell
│   ├── AppKit file views
│   ├── macOS menu / shortcuts / drag & drop
│   └── window/tab management
│
├── File Workspace Layer
│   ├── file browser
│   ├── preview engine
│   ├── search
│   ├── metadata
│   └── permissions
│
├── Terminal Layer
│   ├── libghostty adapter
│   ├── TerminalEngine protocol
│   ├── PTY/session manager
│   ├── cwd tracking
│   └── scrollback/transcript policy
│
├── Context Bridge
│   ├── selection → terminal
│   ├── preview → terminal
│   ├── terminal cwd → browser
│   ├── terminal output path → preview
│   └── drag/drop path bridge
│
├── Change Journal
│   ├── FSEvents watcher
│   ├── SQLite event store
│   ├── lightweight version store
│   ├── diff engine
│   └── restore engine
│
└── Extensions
    ├── Finder Sync / Services entry
    ├── URL scheme
    └── optional Quick Look extensions
```

---

## 11.2 技术栈建议

| 模块 | 建议技术 | 原因 |
|---|---|---|
| 主 App | Swift + AppKit + SwiftUI | macOS 原生体验、拖拽、菜单、权限、性能 |
| 文件列表 | AppKit NSTableView / NSCollectionView / NSOutlineView | 大目录性能和复杂选择行为更稳 |
| Terminal | libghostty | 高质量原生 terminal core |
| Terminal 抽象 | TerminalEngine protocol | 隔离 libghostty API 变化风险 |
| PTY 管理 | Swift + POSIX PTY/fork/Process | 真 shell 会话 |
| 文件监听 | FSEvents | 监听目录树变化 |
| 数据库 | SQLite | 本地状态、事件、版本索引 |
| 搜索 | Spotlight + SQLite FTS | 元数据搜索与本地全文搜索 |
| 预览 | Quick Look / PDFKit / AVKit / Text renderer | 原生预览能力 |
| Diff | 自研文本 diff 或集成轻量 diff lib | 不暴露 Git 心智 |
| 分发 | Developer ID + Notarization | 避免 Mac App Store 沙盒限制过重 |

---

## 11.3 TerminalEngine 抽象

```swift
protocol TerminalEngine {
    func createSession(config: TerminalSessionConfig) -> TerminalSession
    func attachView(to session: TerminalSession) -> NSView
    func write(_ data: Data, to session: TerminalSession)
    func resize(session: TerminalSession, cols: Int, rows: Int)
    func close(session: TerminalSession)
}
```

设计原则：

```txt
业务层只依赖 TerminalEngine
libghostty 细节封装在 GhosttyTerminalEngine
未来可加入 fallback 或测试实现
```

---

## 11.4 Change Journal 架构

```txt
FSEvents
↓
Event Normalizer
↓
Debounce / Grouping
↓
File Metadata Scanner
↓
Version Capture Policy
↓
SQLite Journal
↓
Recent Changes UI
```

核心原则：

```txt
先记录发生了什么
再判断是否需要保存版本
最后聚合成用户可理解的变化组
```

---

## 12. 数据模型草案

## 12.1 workspaces

```sql
CREATE TABLE workspaces (
  id TEXT PRIMARY KEY,
  root_path TEXT NOT NULL,
  display_name TEXT,
  bookmark_data BLOB,
  created_at INTEGER NOT NULL,
  last_opened_at INTEGER NOT NULL
);
```

---

## 12.2 terminal_sessions

```sql
CREATE TABLE terminal_sessions (
  id TEXT PRIMARY KEY,
  workspace_id TEXT,
  title TEXT,
  initial_cwd TEXT,
  current_cwd TEXT,
  shell_path TEXT,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER,
  closed_at INTEGER,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)
);
```

---

## 12.3 file_events

```sql
CREATE TABLE file_events (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  path TEXT NOT NULL,
  old_path TEXT,
  event_type TEXT NOT NULL,
  file_type TEXT,
  size_before INTEGER,
  size_after INTEGER,
  hash_before TEXT,
  hash_after TEXT,
  version_before_id TEXT,
  version_after_id TEXT,
  likely_terminal_session_id TEXT,
  occurred_at INTEGER NOT NULL,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)
);
```

---

## 12.4 file_versions

```sql
CREATE TABLE file_versions (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  path TEXT NOT NULL,
  content_ref TEXT NOT NULL,
  content_hash TEXT,
  size INTEGER,
  created_at INTEGER NOT NULL,
  reason TEXT,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)
);
```

---

## 12.5 change_groups

```sql
CREATE TABLE change_groups (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  likely_terminal_session_id TEXT,
  event_count INTEGER NOT NULL,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)
);
```

---

## 13. 安全、隐私与权限

## 13.1 权限原则

```txt
默认只访问用户显式打开的文件夹
不默认请求 Full Disk Access
需要持续访问时使用系统授权机制保存访问凭证
权限不足时给出清晰解释
```

---

## 13.2 Terminal 安全边界

因为 PathDeck 承载的是真 Terminal，用户可运行任意命令。产品不应虚假承诺完全隔离或完全回滚。

默认策略：

```txt
不拦截用户手动输入的 shell 命令
不静默修改用户命令
App-mediated paste 可做路径转义
危险命令提示只针对 App 主动生成/粘贴的内容
关闭活跃 Terminal 前提示
```

---

## 13.3 文件版本隐私

轻量版本会保存文件内容副本，必须可控。

要求：

```txt
首次启用时明确说明
可全局关闭
可按文件夹关闭
可配置大小上限
可配置保留时间
可一键清空版本库
敏感目录默认不做内容快照
```

敏感目录示例：

```txt
~/.ssh
~/.gnupg
~/Library/Keychains
浏览器 Profile
.env 文件可默认提示
```

---

## 13.4 Terminal Transcript 隐私

默认不应长期保存完整 Terminal transcript。

建议：

```txt
默认只保存 session 元数据，不保存完整输出
用户可开启 transcript 保存
transcript 保存需支持手动清除
崩溃日志不得默认包含 transcript 内容
```

---

## 14. 非功能需求

## 14.1 性能

| 场景 | 目标 |
|---|---|
| 打开普通文件夹 | 1s 内显示首屏 |
| 10,000 文件目录滚动 | 无明显卡顿 |
| 文件变化聚合 | 大批量变化不阻塞 UI |
| Terminal 输入延迟 | 接近原生 Terminal 体验 |
| Preview 元数据 | 300ms 内显示基础信息 |
| SQLite 查询 Recent Changes | 100ms 级响应 |

---

## 14.2 稳定性

```txt
Terminal 子进程崩溃不能导致 App 崩溃
libghostty adapter 异常需隔离
FSEvents 丢事件时可触发目录 rescan
SQLite 损坏需有恢复策略
版本库达到上限需自动清理
```

---

## 14.3 可访问性

```txt
支持键盘导航
支持 VoiceOver 基础标签
支持系统字体缩放
支持高对比度模式
快捷键可配置
```

---

## 14.4 原生体验

```txt
遵循 macOS 菜单结构
支持 Command 快捷键
支持拖拽
支持右键菜单
支持多窗口
支持窗口状态恢复
支持系统外观明暗模式
```

---

## 15. MVP 范围

## 15.1 MVP 必须包含

```txt
完整 macOS App
打开文件夹
Finder-like 文件列表
基础 Preview
内嵌 libghostty Terminal
Open Terminal Here
文件路径发送到 Terminal
拖文件到 Terminal 插入路径
FSEvents 监听当前工作区变化
Recent Changes 基础面板
SQLite 本地记录
基础设置
```

---

## 15.2 MVP 不包含

```txt
不做 Agent Profile
不做 Agent Runtime
不做 Git worktree
不做复杂版本控制
不做云同步
不做跨平台
不做完整 IDE 编辑器
不做进程级精确归因
```

---

## 16. 里程碑规划

## M0：技术验证

目标：验证核心技术风险。

范围：

```txt
Swift/AppKit 主窗口
libghostty 嵌入 Demo
PTY shell 可运行
文件夹打开与列表展示
FSEvents 监听 Demo
SQLite event 写入 Demo
```

验收：

```txt
能在 App 内打开真实 Terminal
能监听当前文件夹新增/修改/删除
能把变化写入 SQLite 并显示在简单列表中
```

---

## M1：Finder-first MVP

目标：形成可用的文件工作台。

范围：

```txt
文件浏览
路径导航
基础预览
右键菜单
Open With
Move to Trash
Rename
New Folder
搜索文件名
```

验收：

```txt
可以作为轻量 Finder 替代使用 30 分钟以上
常见文件操作稳定
```

---

## M2：Terminal 融合 MVP

目标：Terminal 成为文件工作流的一部分。

范围：

```txt
内嵌 Terminal Panel
Open Terminal Here
Terminal cwd 绑定
Send Path to Terminal
拖文件到 Terminal
多 Terminal Tab 基础能力
```

验收：

```txt
用户无需打开外部 Terminal 即可完成常见命令行任务
路径传递准确稳定
```

---

## M3：Recent Changes MVP

目标：Terminal/命令导致的文件变化可见。

范围：

```txt
FSEvents watcher
变化聚合
Recent Changes 面板
新文件高亮
修改/删除记录
基础 ignore 规则
Terminal 活跃期间弱关联
```

验收：

```txt
运行脚本或 CLI agent 后，用户能看见新增/修改/删除的文件
大批量变更不会淹没 UI
```

---

## M4：透明版本与恢复

目标：对适合的文件提供 before/after 和恢复能力。

范围：

```txt
文本文件轻量快照
Diff view
Restore Previous Version
版本库上限与清理
隐私设置
```

验收：

```txt
小型文本文件修改后可比较和恢复
用户可以关闭版本保存
```

---

## M5：系统入口与 Beta

目标：接入 macOS 工作流。

范围：

```txt
Finder 右键 Open in PathDeck  ← [Kill] FinderSync Extension 承载不了主工作台能力，投入产出比不足
Services
URL Scheme
偏好设置完善
崩溃恢复
性能优化
```

验收：

```txt
用户可从 Finder 快速进入 PathDeck
App 可作为日常文件工作台试用
```

---

## 17. 成功指标

## 17.1 行为指标

| 指标 | 说明 |
|---|---|
| 每日打开工作区次数 | 用户是否把它当作工作入口 |
| Terminal Here 使用次数 | Terminal 融合是否有价值 |
| Send Path to Terminal 使用次数 | 文件与 Terminal 桥是否成立 |
| Recent Changes 打开率 | 变化可见性是否被需要 |
| Preview 打开率 | Finder-like 工作流是否成立 |
| 外部 Finder/Terminal 切换减少 | 核心价值是否达成 |

---

## 17.2 质量指标

```txt
Terminal crash rate
App crash rate
FSEvents missed-event recovery count
版本恢复成功率
大目录打开耗时
路径转义错误率
```

---

## 17.3 用户感知指标

定性问题：

```txt
你是否愿意用它替代 Finder 打开项目/资料文件夹？
你是否减少了 Finder 与 Terminal 之间的切换？
你是否更容易知道 Terminal/Agent 刚刚改了什么？
你是否感觉这个产品比 IDE 更轻、比 Finder 更强？
```

---

## 18. 风险与应对

### R1：libghostty 集成风险

风险：

```txt
API 变化、嵌入复杂度、渲染/输入事件适配成本
```

应对：

```txt
TerminalEngine 抽象隔离
先做 M0 技术验证
保留 fallback 方案
业务层不直接依赖 libghostty API
```

---

### R2：文件变化无法精确归因

风险：

```txt
App 只能观察文件系统变化，不能低成本精确知道哪个进程写了哪个文件
```

应对：

```txt
产品文案使用“Terminal 活跃期间产生”而不是“由该命令产生”
不做虚假精确归因
未来高级版可探索更深系统能力
```

---

### R3：版本保存带来隐私和磁盘压力

风险：

```txt
保存文件副本可能包含敏感内容，也可能占用大量空间
```

应对：

```txt
默认只对小型文本启用
清晰设置
大小上限
保留周期
一键清除
敏感目录默认排除
```

---

### R4：Finder 替代成本高

风险：

```txt
Finder 是系统级产品，用户对细节要求极高
```

应对：

```txt
不一开始承诺完整替代 Finder
先定位为工作区级 Finder-first 文件工作台
优先做好打开文件夹、浏览、预览、Terminal、Recent Changes
```

---

### R5：Agent 生态变化快

风险：

```txt
第三方 CLI agent 输出格式、交互方式、命令行为会变化
```

应对：

```txt
保持 Agent-agnostic
不做深度 adapter
只承载真实 Terminal
只观察文件系统结果
```

---

## 19. 关键产品取舍

### 19.1 为什么不是 Finder Extension 主体？

Finder Extension 能做入口、右键菜单、badge，但承载不了：

```txt
内嵌 Terminal
多 Pane 工作区
Recent Changes
透明版本
文件/Terminal 双向上下文桥
复杂 Preview 与 Diff
```

因此必须做完整 App，Finder Extension 只做外围入口。

---

### 19.2 为什么不做 Agent Profile？

因为产品核心不是管理 Agent，而是增强 Finder + Terminal 的工作流。

用户已有 Terminal 后，可以自行运行：

```txt
claude
codex
kimi
bub
aider
ssh
python
npm
ffmpeg
rsync
任何 shell 命令
```

强行建模 Agent Profile 会带来：

```txt
维护成本
适配负担
产品心智偏移
被第三方 CLI 行为变化拖住
```

因此早期只做轻量 command preset，不做 Agent 管理系统。

---

### 19.3 为什么不把 Git / Worktree 暴露给用户？

因为产品不是 coding-first。

普通文件工作流中，用户更关心：

```txt
刚刚发生了什么
能不能预览
能不能恢复
```

而不是：

```txt
branch
commit
worktree
diff
checkout
```

Git 可以作为某些开发目录中的内部辅助信息，但不能成为产品主心智。

---

## 20. 命名、标识与文案

### 20.1 命名规范

```txt
产品名 / App 名称：PathDeck
项目名：PathDeck
repo 名：pathdeck
CLI helper：pathdeck
URL Scheme：pathdeck://
Bundle ID：in.riverflows.PathDeck
Internal codename：Deck
```

命名含义：

```txt
Path：文件路径、目录导航、Finder-like workspace、文件选择与上下文。
Deck：工作台、控制台、terminal panel、多 pane / 多窗口、command surface。
```

PathDeck 的名字不直接绑定 AI、Agent、Coding 或 Finder 替代品，适合承载更长期的产品愿景：

```txt
以文件路径为核心
以 Finder 体验为入口
以 Terminal 承载命令能力
以 Recent Changes 呈现执行结果
```

---

### 20.2 推荐使用的用户文案

英文：

```txt
Open in PathDeck
Reveal in PathDeck
Open Terminal Here
Send Path to Terminal
Send Selection to Terminal
Copy Relative Path
Copy Absolute Path
Recent Changes
Changed Just Now
Terminal Active Changes
Compare with Previous Version
Restore Previous Version
```

中文：

```txt
在 PathDeck 中打开
在 PathDeck 中显示
在此处打开终端
发送路径到终端
发送选中内容到终端
复制相对路径
复制绝对路径
最近变化
刚刚修改
终端活跃期间的变化
与上一版比较
恢复上一版
```

---

### 20.3 推荐使用的定位文案

英文：

```txt
PathDeck is a Finder-first command workspace for macOS.
Browse files, preview context, open terminals, and track changes in one place.
```

中文：

```txt
PathDeck 是一个 Finder-first 的 macOS 文件工作台。
它把文件浏览、预览、Terminal 和最近变化放在同一个上下文里。
```

一句话版本：

```txt
PathDeck：一个以路径为核心、天然长出 Terminal 的 macOS 文件工作台。
```

---

### 20.4 避免使用的文案

```txt
Agent Runtime
Agent Profile
Tool Calling
Git Worktree
Branch
Commit
Checkout
Sandbox
Orchestration
Finder Replacement
AI Finder
```

这些词会把产品误导到开发者工具、Agent 平台或 Finder 替代品，而不是 Finder-first command workspace。

---

## 21. 后续开放问题

| 编号 | 问题 | 倾向 |
|---|---|---|
| Q1 | 是否默认保存 Terminal scrollback？ | 默认否，只保存 session 元数据 |
| Q2 | 是否默认启用文本版本快照？ | 可在首次打开工作区时引导选择 |
| Q3 | 是否提供代码编辑器能力？ | MVP 不做，只预览；后续可支持轻量编辑 |
| Q4 | 是否做语义搜索？ | P3，先做好文件名/内容/变化搜索 |
| Q5 | 是否支持 iCloud Drive 特殊状态？ | P1/P2，需要处理 placeholder、下载状态 |
| Q6 | 是否支持外置盘和网络盘？ | P1，需处理性能和事件可靠性 |
| Q7 | 是否支持多窗口多工作区？ | P1，MVP 可先单窗口多 tab |
| Q8 | 是否做命令风险提示？ | 只对 App-mediated paste/command preset 做轻提示 |

---

## 22. 最终判断

PathDeck 的产品核心应锁定为：

```txt
Swift/AppKit 原生 Finder-like Workspace
+
libghostty 真 Terminal
+
文件与 Terminal 的 Context Bridge
+
FSEvents + SQLite 的透明 Change Journal
+
Quick Look / Preview / Diff / Restore
+
Finder Extension 作为入口
```

第一版必须避免被以下方向带偏：

```txt
Agent Runtime
Agent Profile
Coding IDE
Git Worktree
Finder Extension-only
Electron 原型产品
```

最重要的体验目标：

> 用户感觉自己仍在以 Finder 的方式处理文件，但每一个路径都天然带着 Terminal、Preview 和 Recent Changes；Terminal 或 AI CLI Agent 对文件系统造成的变化会自动浮现出来。

