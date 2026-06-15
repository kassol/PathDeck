# S16：P1 功能合并交付（Preview Pane / cwd 同步 / Security-scoped Bookmarks / Settings）

> Sprint：S16  
> 里程碑：M4+ → M5 衔接  
> 前置：S15 闭合（M0–M4 全部闭合，106 单测通过）  
> PRD 对应：FR-PREVIEW-001 部分、FR-BRIDGE-004、FR-SETTINGS-001/002、Sidebar P1（security-scoped bookmark）

---

## 目标

合并交付 M5（Beta）前最影响日用体验的四组 P1 功能，使 PathDeck 从"可运行的原型"跨入"可日用的工作台"。按独立可合并的子切片组织，每个切片完成后 App 处于可用状态。

## 不做

- 多视图模式（列视图/图标/画廊，FR-FILE-003）——与 Preview Pane 无依赖，留 M5+
- Terminal 输出路径可点击（FR-BRIDGE-003）——需 libghostty 文本提取 API，风险高，单独切片
- Side-by-side diff——inline diff 已满足核心场景
- Content search / Change search（FR-SEARCH-002/003）——独立于本批次
- 隐私设置（FR-SETTINGS-003）——Beta 首版先不做敏感目录排除 UI，VersionStore 已有 1MB 阈值 + 内置忽略

---

## 子切片 A：Preview Pane（右侧预览面板）

### 动机

设计原型的核心差异特征。当前 App 是两栏（sidebar + file browser），PRD 信息架构和设计稿定义了右侧 Preview / Inspector 面板，包含：文件缩略图/Quick Look 预览、元数据表（Kind/Size/Where/Created/Modified）、版本状态与"比较上一版"入口、Quick Actions（Open Terminal Here / Send Path to Terminal / Reveal in Finder）。

### 方案

**布局变更**：`ContentView` 的 detail 区域从纯 `FileTableView` 改为 `HSplitView`（左 file browser + 右 preview pane）。Preview Pane 宽度 220–280pt，可拖拽调整，可折叠（toolbar toggle）。

**PreviewPane.swift**（新增）：

```
PreviewPane
├── 缩略图区（QuickLookThumbnail via QLThumbnailGenerator）
├── 文件名 + 扩展名 chip
├── 元数据表（Kind / Size / Where / Created / Modified）
├── 版本状态行（条件显示：有快照时显示"已修改/有上一版"+ 比较按钮）
└── Quick Actions 区
    ├── Open Terminal Here
    ├── Send Path to Terminal
    └── Reveal in Finder
```

**数据来源**：

- 选中文件：`model.selectedURLs.first`（多选时显示首个文件预览 + 计数提示"共选中 N 项"）
- 元数据：`FileManager.attributesOfItem` 读取，缓存到 `PreviewPane` 内部 `@State`
- 缩略图：`QLThumbnailGenerator.shared.generateBestRepresentation` → `NSImage`（异步，最大 240×240pt）
- 版本状态：`model.versionedPaths.contains(path)`
- 无选中时：显示当前文件夹摘要（项数 + 总大小 + 可用空间）

**交互**：

- 比较按钮点击 → 与 S15 复用同一路径：`onDiff?(path)` → `activeBottomTab = .diff(path:)`
- Send Path to Terminal → 复用 `sendPathToTerminal`
- Reveal in Finder → `NSWorkspace.shared.activateFileViewerSelecting([url])`
- Open Terminal Here → 打开底部面板 + 新建/切换 terminal tab

**文件清单**：

| 文件 | 操作 |
|---|---|
| `PathDeck/FileWorkspace/PreviewPane.swift` | **新增** |
| `PathDeck/ContentView.swift` | 修改：detail 区域插入 HSplitView 包裹 PreviewPane |
| `PathDeck/PathDeckApp.swift` | 修改：toolbar 增加 Preview Pane toggle |

**测试**：

- 单测：`QLThumbnailGenerator` 为系统 API 无需 mock；元数据读取用临时文件验证 Kind/Size/Date 正确性
- 手动验证：选中 .md / .png / .pdf / 文件夹 分别查看缩略图 + 元数据；多选显示计数；无选中显示文件夹摘要；Quick Actions 各按钮可用

---

## 子切片 B：Terminal cwd 同步

### 动机

FR-BRIDGE-004。用户在 Terminal 中 `cd` 后，App 应能感知 cwd 变化并提供"跳转到该目录"操作。当前 `TerminalSession.cwd` 是创建时固定的，不跟踪运行时变化。

### 方案

**cwd 跟踪机制**：libghostty 本身不暴露 cwd 变化回调。利用 macOS 标准机制：

1. **OSC 7 序列**：现代 shell（zsh/bash/fish）在每次 prompt 时发送 `\e]7;file:///path\a`。libghostty 解析 OSC 7 并通过 `working_directory_cb` 回调通知宿主。在 `GhosttySurfaceView` 中注册该回调，更新 `TerminalSession.currentCwd`。

2. **备选（若 libghostty 无 `working_directory_cb`）**：定时轮询 `proc_pidinfo` / `PROC_PIDVNODEPATHINFO` 获取子进程 cwd。每 2 秒轮询一次，仅在 terminal 活跃时运行。

**UI**：

- `TerminalTabBar` 每个 tab 右侧显示 cwd 最后一段路径名（灰色小字，溢出截断）
- cwd 文本可点击 → `model.navigate(to: currentCwd)`（文件浏览器跳转到该目录）
- 可选：toolbar 增加"Follow Terminal CWD"开关（默认 off），开启后 terminal cwd 变化自动带动文件浏览器导航

**改动**：

| 文件 | 操作 |
|---|---|
| `PathDeck/Terminal/TerminalSession.swift` | 修改：新增 `currentCwd: URL`，初始值 = `cwd` |
| `PathDeck/Terminal/TerminalEngine.swift` | 修改：协议新增 `var cwdDidChange: ((UUID, URL) -> Void)?` |
| `PathDeck/Terminal/GhosttySurfaceView.swift` | 修改：注册 `working_directory_cb`（或实现轮询 fallback） |
| `PathDeck/Terminal/GhosttyTerminalEngine.swift` | 修改：桥接 cwd 回调到 `cwdDidChange` |
| `PathDeck/Terminal/TerminalTabBar.swift` | 修改：显示 currentCwd 并支持点击跳转 |
| `PathDeck/ContentView.swift` | 修改：接收 `cwdDidChange`，更新 session 的 `currentCwd`；可选 follow 模式 |

**测试**：

- 单测：`TerminalSession` 的 `currentCwd` 更新逻辑
- 手动验证：打开终端 → `cd /tmp` → tab 显示 `/tmp` → 点击 cwd 文本 → 文件浏览器跳转到 `/tmp`

---

## 子切片 C：Security-scoped Bookmarks（Pinned 持久化）

### 动机

Sidebar P1。当前 `PinnedFolders` 用 `UserDefaults` 存路径字符串，重启后若目录被移动/重命名则残留死条目。App 使用 Developer ID 签名（非沙盒），但 security-scoped bookmark 仍是 macOS 推荐的持久化目录访问方式，且为后续可能的受限签名留空间。

### 方案

**改动范围**：仅 `PinnedFolders` 内部实现，对外接口不变。

1. `add(_ url:)` 时调用 `url.bookmarkData(options: [.withSecurityScope], ...)` 生成 bookmark data
2. 持久化存储从 `[String]`（路径数组）改为 `[Data]`（bookmark data 数组），key 改为 `pinnedFolderBookmarks`（新 key，首次启动迁移旧 key）
3. `init()` 加载时用 `URL(resolvingBookmarkData:options:[.withSecurityScope], ...)` 解析，`isStale` 为 true 时重新生成 bookmark
4. 解析失败的条目静默丢弃（不显示死条目）
5. 如果非沙盒环境下 `withSecurityScope` 报错（Developer ID 可能不需要），降级为普通 bookmark（不带 security scope option）

**迁移**：首次读取新 key 为空时，读旧 key `pinnedFolders`，对每个路径尝试生成 bookmark data 并写入新 key，成功后删除旧 key。

| 文件 | 操作 |
|---|---|
| `PathDeck/SidebarView.swift` | 修改：`PinnedFolders` 内部实现替换 |

**测试**：

- 单测：bookmark 生成 → 序列化 → 反序列化 → URL 一致；stale bookmark 重新生成；无效数据跳过
- 手动验证：pin 文件夹 → 退出 App → 重命名该文件夹 → 重新打开 App → pin 条目消失（不残留）

---

## 子切片 D：Settings 窗口

### 动机

FR-SETTINGS-001/002。Beta 必须有基础偏好设置。无设置窗口时用户无法配置 Terminal shell、调整 Change Journal 行为。

### 方案

**实现方式**：SwiftUI `Settings` scene（`@main` App 中添加 `Settings { SettingsView() }`），macOS 标准 Preferences 窗口（⌘,）。

**Tab 结构**：

| Tab | 设置项 | 存储 |
|---|---|---|
| Terminal | Default shell（picker：zsh/bash/fish/自定义路径）、Font family + size、Color scheme（Dark 固定 / 跟随系统）、Scrollback 行数（slider 1000–50000，默认 10000）| `UserDefaults` + `@AppStorage` |
| Changes | 启用 Recent Changes（toggle，默认 on）、启用轻量版本快照（toggle，默认 on）、快照文件大小上限（slider 256KB–5MB，默认 1MB）、版本保留条数 per file（stepper 5–50，默认 10）、忽略规则管理（复用 `IgnoreRulesPopover` 组件内容，嵌入为设置子项）| `UserDefaults` + `@AppStorage` |

**设置生效机制**：

- Terminal 设置改变 → 下次新建 terminal tab 时生效（已有 tab 不热更新，避免复杂性）
- Change Journal 设置改变 → `VersionStore` / `ChangeStore` / `FSWatcher` 通过 `@AppStorage` 读取最新值。大小上限和版本保留条数在下次快照时生效
- 关闭 Recent Changes → `FSWatcher` 停止；关闭版本快照 → `VersionStore` 不再写入新版本

**GhosttyTerminalEngine 适配**：当前 `createSession` 硬编码 shell 和配置。改为读取 Settings 中的 shell 路径和 scrollback 值，传入 `ghostty_config`。

**文件清单**：

| 文件 | 操作 |
|---|---|
| `PathDeck/Settings/SettingsView.swift` | **新增**：Settings 窗口主视图 |
| `PathDeck/Settings/TerminalSettingsTab.swift` | **新增**：Terminal 设置 tab |
| `PathDeck/Settings/ChangesSettingsTab.swift` | **新增**：Changes 设置 tab |
| `PathDeck/PathDeckApp.swift` | 修改：添加 `Settings` scene |
| `PathDeck/Terminal/GhosttyTerminalEngine.swift` | 修改：`createSession` 读取 settings |
| `PathDeck/ChangeJournal/VersionStore.swift` | 修改：大小阈值 + 保留条数从 `@AppStorage` 读取 |
| `PathDeck/ChangeJournal/FSWatcher.swift` | 修改：尊重 Recent Changes 开关 |

**测试**：

- 单测：Settings 值的默认值验证；VersionStore 大小阈值变更后行为验证（超阈值文件不快照）
- 手动验证：⌘, 打开设置 → 切换 shell 为 bash → 新建 terminal tab → 确认 bash prompt；修改快照上限 → 创建超限文件 → 确认无快照

---

## 实施顺序

```
子切片 C（Bookmarks）→ 子切片 A（Preview Pane）→ 子切片 B（cwd 同步）→ 子切片 D（Settings）
```

理由：
- C 最小（仅 SidebarView.swift 内部），零风险热身
- A 是最大视觉变化，需要尽早进入手动验证
- B 依赖对 libghostty callback 机制的探查，可能需要 fallback 方案
- D 最后做，因为 Settings 需要知道前面子切片引入了哪些可配置项

每个子切片独立提交，完成后 App 处于可用状态。

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| libghostty 无 `working_directory_cb` 回调 | 子切片 B 需 fallback 到轮询 | 先 grep `ghostty.h` 确认；轮询方案已设计 |
| 非沙盒 App 创建 security-scoped bookmark 行为差异 | 子切片 C | 降级为普通 bookmark，功能不受影响 |
| `HSplitView` 与 `NavigationSplitView` 嵌套布局 | 子切片 A | 若冲突，改为 `GeometryReader` + 手动分栏 |
| Settings 改 shell 后旧 tab 用户预期 | 不一致感 | 文档明确"对新 tab 生效"，不做热更新 |

## 验收标准

- [ ] Preview Pane 显示选中文件的缩略图、元数据、版本状态、Quick Actions
- [ ] Terminal tab 显示当前 cwd，点击可跳转文件浏览器
- [ ] Pinned 文件夹使用 bookmark data 持久化，目录移动/删除后不残留
- [ ] ⌘, 打开 Settings 窗口，Terminal 和 Changes 设置可用且生效
- [ ] 所有子切片独立可合并，每步 build + 单测通过
