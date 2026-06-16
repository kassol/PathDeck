# Design：PathDeck — UI 设计系统

> 版本：v0.1（从设计稿抽取）
> 日期：2026-06-13
> 平台：macOS 26（AppKit + SwiftUI）
> 状态：视觉权威参考。产品定义以 `docs/prd.md` 为准，布局与交互原型见 `design/PathDeck Prototype (standalone).html`。

---

## 0. 本文是什么

从 `design/PathDeck Design System (standalone).html` 抽取并核验的 design tokens + 组件规格，作为 macOS 原生实现 UI 时的视觉权威来源。

布局、屏幕、交互状态、UX 流程不在本文档范围——这些由交互原型定义，直接用浏览器打开查看：

| 参考 | 文件 | 涵盖内容 |
|---|---|---|
| 交互原型 | `design/PathDeck Prototype (standalone).html` | 窗口骨架、三栏布局、Toolbar/Sidebar/File Browser/Preview/Terminal 各区域构成、屏幕流转（Welcome → Workspace → Settings/Palette）、交互状态（Layout A/B/C、视图切换、面板展开收起、主题切换）|

设计系统稿同样为 `dc-runtime` 打包的单文件 HTML，真实 UI 在 `<script type="__bundler/template">` 内（内联 style）。需要可视参考时直接用浏览器打开；本文是其规格化提炼。

**坐标系约定**：设计稿用 CSS `px`。macOS 实现按 `1px → 1pt` 1:1 映射（Apple Silicon @2x 渲染）。下文数值默认单位即目标 `pt`。

**Web → Native 映射**贯穿全文以「实现注记」标出，不要把 web 实现细节（CSS 变量名、`rgba` hover）直接照搬，按 macOS 原生能力落地。

---

## 1. 设计基础 Foundations

### 1.1 色彩系统

双外观（Dark 默认 / Light）。表面、文字、分隔线随外观切换；强调色随外观切换；变化语义色与终端主题固定不变。

**表面层级 Surfaces**

| 语义 | Dark | Light | 用途 |
|---|---|---|---|
| Window | `#1e1e1e` | `#ffffff` | 窗口主背景 |
| Sidebar | `#2a2a2c` | `#e8e8eb` | 侧栏 |
| Toolbar | `#2c2c2e` | `#f1f1f3` | 顶部工具栏 |
| Panel | `#252527` | `#f6f6f8` | 面板/卡片底（结构层）|
| Elevated | `#34343a` | — | 抬升层（如视图分段选中底）|
| Card | — | `#fbfbfc` | 内容卡片（亮色实测值）|
| Page | — | `#ececed` | 设计系统稿页面底 |
| Terminal | `#161618` | `#161618` | 终端背景（固定深色）|

**文字层级 Text**

| 语义 | Dark | Light | 用途 |
|---|---|---|---|
| Primary | `rgba(255,255,255,0.92)` | `#1a1a1c` | 主文字、按钮文字、数值 |
| Secondary | `rgba(255,255,255,0.56)` | `#5a5a5e` | 副标题、次级文字 |
| Tertiary | `rgba(255,255,255,0.36)` | `#6a6a6e` | 描述、禁用态文字 |
| Muted / Caption | — | `#86868b` | 占位符、caption、时间戳、section 标签 |

> Light 态另有 `#3a3a3e`（色组小标题）、`#9a9a9f`（更浅的 muted）。原生实现优先用语义色，散值按最近语义归并。

**强调色 Accent**

| 语义 | Dark | Light | 用途 |
|---|---|---|---|
| Accent | `#5e9eff` | `#0a6cff` | 主品牌色：主按钮、选中行、分段选中、焦点 |
| Selection 高亮 | `rgba(10,108,255,0.22)` | `rgba(10,108,255,0.22)` | 文本 `::selection` |

> 实现注记：`#0a6cff` ≈ `controlAccentColor`/`systemBlue`。优先绑定系统 `NSColor.controlAccentColor`，让强调色随用户系统偏好走；上表是设计默认值。

**变化语义色 Change semantics**（贯穿文件行高亮、变化条目、状态点）

源码内存在两套用色，是分层用色而非冲突——大面积/圆点用鲜艳系统色，小面积文字符号 chip 用加深版以保证在浅色 tint 底上的对比度。两套都保留：

| 状态 | 系统色（dot / 大色块 / swatch）| 文字色（符号 chip / 小面积）| tint 底 |
|---|---|---|---|
| Added | `#30d158` | `#1f9d3f` | `rgba(48,209,88,0.13)` |
| Modified | `#ff9f0a` | `#cf8500` | `rgba(255,159,10,0.13)` |
| Deleted | `#ff453a` | `#e0382b` | — |
| Renamed | `#bf5af2` | `#a23bd6` | — |

> 系统色对应 `systemGreen / systemOrange / systemRed / systemPurple`。符号 chip 文字用加深版，chip 底为「文字色 @15% 透明」。

**文件类型标记色 File-type marks**（扩展名 chip：文字色 = 下表，chip 底 = 该色 @15%）

| md | pdf | png | csv | py | yaml | zip | txt |
|---|---|---|---|---|---|---|---|
| `#2f6fed` | `#e0382b` | `#a23bd6` | `#1f9d3f` | `#d98a00` | `#14b8a6` | `#8a8a8e` | `#64748b` |

**文件夹色 Folder**：设计稿出现三个相近值（`#3b82f6` / `#5b9bf5` / `#4f93f7`）。实现统一取一个，建议 `#3b82f6`（Light）/ `#5b9bf5`（Dark）。

**辅助语义**

| 用途 | 值 |
|---|---|
| 交通灯 红/黄/绿 | `#ff5f57` / `#febc2e` / `#28c840` |
| 计数 badge 底 / 文字 | `#ff9f0a` / `#1a1206` |
| 标准边框（控件/卡片）| `rgba(0,0,0,0.10~0.14)`（Dark 对应 `rgba(255,255,255,0.07~0.16)`）|
| 分隔线 | Light `#dcdcdf`；表内 `rgba(0,0,0,0.06~0.07)`；Dark `rgba(255,255,255,0.09)` |
| Hover 底 | Light `#ededf0`；通用 `rgba(255,255,255,0.06)` |

### 1.2 字体排印 Typography

**字体族**

| 角色 | 字体链 |
|---|---|
| UI（sans）| `-apple-system, 'SF Pro Text', 'SF Pro Display', system-ui, sans-serif` |
| 等宽（mono）| `ui-monospace, 'SF Mono', Menlo, monospace` |

等宽用于：终端、路径、文件尺寸、代码、扩展名 chip、快捷键。渲染开 `antialiased`。无自定义字体。

**字号 / 字重体系（Type scale）**

| 角色 | size | weight | 备注 |
|---|---|---|---|
| Large Title | 30 | 700 | letter-spacing −0.02em |
| Title | 17 | 680 | 卡片/面板标题 |
| Headline | 15 | 640 | 预览文件名 |
| Body | 13 | 450 | 文件列表行正文 |
| Subhead | 12 | 500 | |
| Caption | 11 | 600 | letter-spacing 0.01em；section 标签用 12/700 + 0.08em uppercase |
| Mono sample | 12.5 | — | 终端正文、控件文字 |

实测出现的全部 size：`30 / 17 / 15 / 13 / 12.5 / 12 / 11.5 / 11 / 10.5 / 10 / 8.5`。
控件文字普遍 `12.5`；列头 `11.5`；徽章/分组标题 `11`；变化条目时间 `10.5`；扩展名 chip `8.5`。

**字重映射（SF Pro 可变字重 → AppKit 离散档）**

设计稿用了密集非整百字重（450/520/540/560/590/640/680/700/800）。AppKit 标准档建议映射：

| 设计值 | NSFont.Weight |
|---|---|
| 450 | `.regular` |
| 500 / 520 | `.medium` |
| 540 / 560 / 590 | `.semibold` |
| 640 / 680 / 700 | `.bold` |
| 800 | `.heavy` |

> 需精确还原时用可变字重 API（`NSFont` + `variableFontWeight`），否则就近取档即可。

### 1.3 间距 Spacing

**Scale**：`4 6 8 10 14 18 22`（约束元素间小间隙 gap 与小 margin）。

容器级内边距自成一套，不纳入上述 scale：卡片 `26×28` 或 `24×26`；终端面板 `16×18`；页面外边距 `48 / 40 / 80`。实现时区分「元素间隙（走 scale）」与「容器留白（独立值）」两套。

### 1.4 圆角 / 边框 / 阴影

**Radius（语义命名）**

| 名称 | 值 | 应用 |
|---|---|---|
| window | 11 | 窗口圆角 |
| control | 7 | 按钮 / 输入框 / 下拉 / 分段 |
| row | 6 | 列表行 |
| pill | 高度的一半 | 状态 pill / 开关轨道（如 22 高→11）|
| card | 16 | 内容卡片 |
| small chip | 5 | 列表行内扩展名 chip |
| type chip | 9 | 文件类型大方块（38×38）|
| app icon | 17 | 72×72 应用图标 |

**Border**：统一 `0.5pt` hairline（`0.5px solid`），色见 §1.1。无更粗边框。

**Shadow**

| 语义 | 值 |
|---|---|
| Card | `0 1px 2px rgba(0,0,0,0.04)` |
| Popover | `0 16px 40px rgba(0,0,0,0.22)` |
| Window | `0 22px 70px rgba(0,0,0,0.55)` + `0 0 0 0.5px rgba(0,0,0,0.4)` |
| App icon | `0 8px 22px rgba(59,111,212,0.34)` |
| Toggle 旋钮 | `0 1px 3px rgba(0,0,0,0.3)` |

### 1.5 关键尺寸 Metrics（原生实现硬约束）

| 项 | 值 |
|---|---|
| 窗口 | `1180 × 752`，radius 11 |
| Toolbar 高 | 52 |
| Sidebar 宽 | 220 |
| 右侧面板宽 | 312（默认）/ 344（Changes co-star）|
| 底部终端高 | 236 |
| 右侧终端宽 | 480 |
| 列表行高 | 30（column 视图行 26）|
| 控件高 | 28（纯文字按钮 30）|
| 交通灯 | 12，间距 8 |

### 1.6 动效 Motion

**设计稿未定义任何 transition / animation / keyframes。** 选中、hover、面板展开收起、开关切换的过渡需自定。建议遵循 macOS 系统默认时长（约 0.2–0.35s，标准缓动），保持原生体感。

### 1.7 图标 Icon

无图标库依赖。三种来源：

- **内联手写 SVG**（24×24 viewBox，stroke/fill currentColor）：品牌/终端 glyph（`>` 折线 `5 8 9 12 5 16` + 横线）、文件夹、放大镜。
- **等宽文字 chip 代替文件类型图标**：直接渲染扩展名大写（MD/PDF/PNG…）。
- **符号字符**：`✓ ✕ ⌄ ➜ ⚠ + ~ − →`。

> 实现注记：原生应将上述映射到 **SF Symbols**（设计稿未引用任何 SF Symbol 名，需自行选型）。品牌图标保留自定义 SVG/asset。

---

## 2. 组件库 Components

仅列设计稿真实定义的状态；未定义的交互态（多数 hover/disabled/focus）需按系统规范补齐。

| 组件 | 规格 |
|---|---|
| **Button · Primary** | h30 · padding `0 15` · radius7 · bg accent · 白字 · 12.5/590 |
| **Button · Secondary** | h30 · padding `0 15` · radius7 · bg surface · 主文字 · border 0.5 · 12.5/540 |
| **Button · Primary+icon** | h28 · padding `0 11` · radius7 · bg accent · 白字 · 12.5/520 · gap6 · 内含 14×14 SVG |
| **Segmented control** | 容器 inline-flex · radius7 · border0.5 · overflow hidden；每段 h26 · padding `0 13` · 12/540；选中段 bg accent 白字，未选 bg surface 主文字 |
| **Toggle / Switch** | 轨道 38×22 · radius11；旋钮 18×18 圆 · 白 · shadow `0 1px 3px rgba(0,0,0,0.3)`；on 态轨道 bg accent |
| **Search field** | w160 · h28 · padding `0 9` · radius7 · border0.5 · gap6 · 内含 13×13 放大镜 · 占位 12.5 muted |
| **Select / Dropdown** | h28 · padding `0 10` · min-w120 · radius7 · border0.5 · 12.5 · 右侧 `⌄` 指示 |
| **Badge（计数）** | min-w18 · h18 · padding `0 5` · radius9 · bg `#ff9f0a` · 文字 `#1a1206` 11/700 |
| **Tag with dot** | gap7 · 12.5 · 前缀 11×11 圆点（语义色）|
| **Status pill** | padding `2px 8px` · radius8 · bg「语义色@16%」· 文字语义色 10.5/600 · 前缀 5×5 圆点 |
| **File-type chip（小）** | 19×19 · radius5 · mono 8.5/800；选中行内用 `rgba(255,255,255,0.22)` 底 |
| **File-type mark（大）** | 38×38 · radius9 · mono 11/800 uppercase · bg「类型色@15%」· 文字类型色 |
| **Change journal item** | padding `7px 8px` · radius7 · gap10；左 19×19 符号 chip（mono 12/800）；中两行 name 12.5 + path 11 muted；右 time 10.5 muted |
| **Card / Panel** | bg card · border0.5 · radius16 · padding `26×28` · shadow card；标题 17/680，描述 13 tertiary |
| **App icon** | 72×72 · radius17 · `linear-gradient(160deg,#5e9eff,#3b6fd4)` · shadow app · 内含 40×40 白色 glyph |

**文件列表行三态**（行 h30 · padding `0 8` · radius6 · gap9 · 13）：

- **default**：无底；文件夹 18px SVG（folder 色）；文件名 weight 560；右侧时间 muted。
- **selected**：bg accent · 白字；左侧类型 chip（半透明白底）；副列文字 `rgba(255,255,255,0.8)`。
- **changed**：bg「modified 色@13%」；行首 6×6 圆点（modified 文字色，margin-left −3 外突）；右侧 "Just now"。

---

## 3. 终端主题 Deck Dark（ANSI 16-color）

两种外观下终端均固定深色。

| 名称 | 值 | 名称 | 值 |
|---|---|---|---|
| fg | `#d6d6d6` | bg | `#161618` |
| red | `#ff6b60` | blue | `#7fb0ff` |
| green | `#7ee49a` | magenta | `#d79bf5` |
| yellow | `#ffcf6b` | cyan | `#6bd6d6` |

终端示例额外：prompt 路径绿 `#7ee49a`、链接蓝 `#5e9eff`（下划线）、错误红 `#ff6b60`、灰输出 `#9a9a9a`、内层面板底 `#0f0f11`、光标块用 fg 色。

> 实现注记：terminfo 经 libghostty 注入，主题色需配置进 `TerminalEngine`。配色与 libghostty 集成细节见 `PathDeck/Terminal/AGENTS.md`。

---

## 4. 实现注记与未决项

**Web → Native 映射要点**
- `px → pt` 1:1；CSS 变量 → 语义化 `NSColor` / asset catalog（双外观用 `NSColor` 的 light/dark 变体）。
- 强调色优先绑 `controlAccentColor`，让其随系统偏好；变化语义色优先用 `systemGreen/Orange/Red/Purple`。
- 字重就近映射到 `NSFont.Weight`（见 §1.2）。
- 内联 SVG/符号字符 → SF Symbols + 自定义品牌 asset。
- 动效设计稿缺失，按系统默认补齐（§1.6）。

**用色待统一**
- 文件夹色三个相近值（`#3b82f6` / `#5b9bf5` / `#4f93f7`），落地取一。
- 变化语义色两套（系统色 / 加深文字色）按 §1.1 分层使用，不要二选一。

---

## 变更日志

- 2026-06-13 v0.1：从 `design/` 两份设计稿抽取，交叉核验 metrics/色值/布局后定稿。
