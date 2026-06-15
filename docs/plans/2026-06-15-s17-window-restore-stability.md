# S17：窗口状态恢复 + writeText 竞态修复 + 性能基线

> Sprint：S17  
> 里程碑：M5（系统入口与 Beta）Phase 1  
> 前置：S16 闭合（117 单测通过，M0–M4 全部闭合 + M5 衔接 P1 功能已交付）  
> PRD 对应：§14.1 性能、§14.2 稳定性、§14.4 原生体验（窗口状态恢复）

---

## 目标

使 PathDeck 从"每次启动都是全新状态"升级为"关了再开回到上次工作场景"，同时修复已知的 terminal writeText 竞态和建立文件目录性能自动基线。这三项是 Beta 日用的硬性前提——没有状态恢复用户不会把它当工作入口，writeText 丢文本直接破坏 Context Bridge 核心价值。

## 不做

- Finder Sync Extension / URL Scheme（S17-A 单独切片）
- Terminal session 跨重启恢复（复杂度高：需序列化 PTY/scrollback，当前只恢复 tab 占位 + cwd，不恢复进程）
- `NSWindowRestoration` 完整实现（SwiftUI `WindowGroup` 下 `NSWindowRestoration` 受限；用 `@SceneStorage` + `UserDefaults` 组合替代）
- 大目录分页 UI（性能基线验证后若 NSTableView 虚拟化足够则无需额外 UI）
- 多窗口状态独立恢复（当前单 WindowGroup 单 workspace，多窗口留后续）

---

## 子切片 A：Terminal writeText 竞态修复

### 问题

`sendPathToTerminal` 在 terminal session 不存在时会先 `createTerminalTab()`（`ContentView.swift:311-314`），然后立即 `writeText`（`:321-323`）。但 `GhosttyTerminalEngine.createSession()` 只分配 UUID + 存储 cwd（`:34-37`），不创建 `GhosttySurfaceView`。Surface view 在 `terminalView(for:)` 首次调用时懒创建（`:45-51`），且 `ghostty_surface_t` 要等 `viewDidMoveToWindow()` 才初始化（`GhosttySurfaceView.swift:52-62`）。

调用链：`createTerminalTab()` → `activeTerminalID = id` → SwiftUI 异步 layout → `TerminalPanelView` 渲染 → `terminalView(for:)` → `viewDidMoveToWindow()` → `createSurface()`。但 `writeText` 在 `DispatchQueue.main.async` 中执行，可能在 SwiftUI 完成 layout 之前就到达——此时 `surfaceViews[id]` 为 nil 或 `surface` 为 nil，`insertText` 的 `guard let surface else { return }` 静默丢弃文本。

### 方案

在 `GhosttyTerminalEngine` 中引入 per-session pending text buffer，surface 就绪后 flush。

1. **`GhosttyTerminalEngine` 新增 `pendingTexts: [UUID: [String]]`**

2. **`writeText` 改为**：若 `surfaceViews[id]?.surface != nil`，直接 `insertText`；否则追加到 `pendingTexts[id]`

3. **`GhosttySurfaceView` 新增 `onSurfaceReady: (() -> Void)?` 回调**：在 `createSurface()` 成功后调用

4. **`terminalView(for:)` 创建 view 时设置 `onSurfaceReady`**：flush 该 session 的 pending texts

5. **超时保护**：pending text 最多保留 5 秒（`DispatchQueue.main.asyncAfter`），超时后丢弃并 `NSLog` 警告

**改动**：

| 文件 | 操作 | 改动摘要 |
|---|---|---|
| `PathDeck/Terminal/GhosttyTerminalEngine.swift` | 修改 | +`pendingTexts` 字典；`writeText` 增加 buffer 分支；`terminalView(for:)` 注册 `onSurfaceReady` flush |
| `PathDeck/Terminal/GhosttySurfaceView.swift` | 修改 | +`onSurfaceReady` 闭包；`createSurface()` 末尾调用 |

**测试**：

- 单测：创建 session → 立即 writeText → 模拟 surface ready → 验证 pending text 被 flush
- 单测：surface 已存在时 writeText 直接投递（不走 buffer）
- 单测：超时后 pending text 被清除
- 手动验证：Send Path to Terminal 在无 terminal 时触发 → 新建 tab 后路径出现在 terminal 中

---

## 子切片 B：窗口与工作区状态恢复

### 现状

当前持久化仅有：
- `UserDefaults["lastOpenedFolder"]`（`WorkspaceModel.swift:11,65-76`）
- `UserDefaults["recentFolders"]`（`RecentFolders`）
- `UserDefaults["pinnedFolderBookmarks"]`（`PinnedFolders`，S16 已升级 bookmark data）
- Terminal / Changes / Settings 偏好（`@AppStorage`）

未持久化：
- 窗口几何（位置/尺寸）
- 底部面板状态（展开/折叠/高度/activeTab）
- Preview Pane 状态（展开/折叠）
- 排序偏好（sortColumn/sortAscending）
- 显示隐藏文件状态
- Terminal tab 列表（tab 数/标题/cwd——不恢复进程）

### 方案

使用 `@SceneStorage` 持久化 SwiftUI scene 级状态，`@AppStorage` 持久化跨 scene 共享偏好。

**ContentView 新增 `@SceneStorage`**：

| Key | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `bottomPanelVisible` | Bool | false | 底部面板展开状态 |
| `bottomPanelHeight` | Double | 250 | 底部面板高度 |
| `activeBottomTabRaw` | String | "terminal" | 活跃 tab（terminal/changes） |
| `previewPaneVisible` | Bool | true | 预览面板展开状态 |

**WorkspaceModel 新增 `@AppStorage`**（跨 scene 共享，全局偏好性质）：

| Key | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `sortColumn` | String | "name" | 排序列 |
| `sortAscending` | Bool | true | 排序方向 |
| `showHidden` | Bool | false | 显示隐藏文件 |

**Terminal tab 恢复**（仅恢复占位，不恢复进程）：

App 退出时将 terminal tabs 序列化为 JSON 存入 `UserDefaults["terminalTabsState"]`：

```swift
struct TerminalTabState: Codable {
    let title: String
    let cwd: String  // 路径字符串
}
```

启动时读取 → 为每个条目重新 `createSession(cwd:)` + 创建 `TerminalSession`。用户看到之前的 tab 布局，每个 tab 是新 shell（与 iTerm2/Terminal.app 行为一致——恢复 tab 但不恢复进程）。若 cwd 路径已不存在，该 tab 降级为 home 目录。

**窗口几何**：SwiftUI `WindowGroup` 在 macOS 上默认会恢复窗口位置/尺寸（`NSWindow.isRestorable` 默认 true），无需额外代码。验证此行为即可，若不生效则在 `PathDeckApp` 中显式设置 `.defaultSize()` + `@SceneStorage` 手动存储。

**改动**：

| 文件 | 操作 | 改动摘要 |
|---|---|---|
| `PathDeck/ContentView.swift` | 修改 | `@State` → `@SceneStorage` 迁移（底部面板/预览面板状态）；启动时读取 terminal tabs 状态恢复 |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 修改 | sortColumn/sortAscending/showHidden 持久化为 `@AppStorage` |
| `PathDeck/Terminal/TerminalSession.swift` | 修改 | +`TerminalTabState` Codable 结构 |

**注意事项**：

- `@SceneStorage` 只支持基本类型（String/Int/Double/Bool/Data/URL），`BottomPanelTab` 需序列化为 String（`.diff` case 不恢复——diff 是临时状态）
- `@Observable` 的 `WorkspaceModel` 不能直接用 `@AppStorage`（属性包装器冲突）。改为在 `init()` 中从 `UserDefaults` 读取，在 `didSet` 中写回
- Terminal tabs 恢复在 `ContentView.onAppear` 中执行，保证 `terminalEngine` 已初始化

**测试**：

- 单测：`TerminalTabState` encode/decode round-trip
- 单测：cwd 路径不存在时降级为 home
- 手动验证：打开文件夹 → 展开底部面板 → 调整高度 → 新建 2 个 terminal tab → cd 到不同目录 → 退出 App → 重新打开 → 验证：路径/面板状态/预览面板/terminal tab 数量和 cwd 均恢复

---

## 子切片 C：文件目录性能自动基线

### 现状

`FileTableView` 使用 `NSTableView`，cell 复用正常（`makeView(withIdentifier:)`），但 `items` 数组一次性全量加载（`WorkspaceModel.reload()` 读取整个目录），`reloadData()` 全量刷新。NSTableView 自身的虚拟化机制（只渲染可见行 + cell 复用）理论上能撑万级规模，但未验证。

### 方案

**Phase 1：自动基线（本切片）**

1. 创建性能测试用例（`PathDeckTests/PerformanceTests.swift`），在临时目录中生成 1,000 个文件，自动验证 reload/sort/filter 耗时在阈值内（默认随套件跑）。万级目录性能需手动验证或后续补充独立测试路径。

2. 若 `reload()` > 500ms，引入增量加载：
   - `WorkspaceModel` 首次加载只读取前 500 个条目 + 一个 `hasMore` 标记
   - 后台线程加载剩余条目，完成后合并到 `items`
   - `FileTableView` 在 `reloadData()` 时仍全量展示已有 items（NSTableView 虚拟化处理可见行）

3. 若排序 > 100ms，将排序移到后台线程

4. `FSWatcher` 大批量事件验证：10,000 文件目录中批量创建 100 个文件 → 验证 debounce 聚合正常、UI 不卡顿

**优化方向（仅在基线测量超标时执行）**：

| 瓶颈 | 方案 |
|---|---|
| `FileManager.contentsOfDirectory` 慢 | 改用 `readdir` + `stat` 批量读取 |
| 排序慢 | 文件名排序用 `String.localizedStandardCompare`（已是如此）；万级下足够快 |
| `reloadData()` 卡顿 | 改为 `insertRows`/`removeRows` diff 更新（需引入 diff 算法，成本高，仅在全量刷新可测量卡顿时做）|
| 内存压力 | `FileItem` 当前只存 URL + 基础属性（name/size/date/kind/isDir），万级下约 10MB，可接受 |

**改动**：

| 文件 | 操作 | 改动摘要 |
|---|---|---|
| `PathDeckTests/PerformanceTests.swift` | **新增** | 1k 文件目录性能自动基线 |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 可能修改 | 若基线超标，引入增量加载 |

**测试**：

- 性能测试：`XCTestCase.measure {}` 验证 reload/sort 在 500ms/100ms 内
- 手动验证（未自动化）：打开 node_modules 或类似万级目录 → 滚动流畅、无明显卡顿

---

## 实施顺序

```
子切片 A（writeText 竞态修复）→ 子切片 B（窗口状态恢复）→ 子切片 C（性能基线）
```

理由：
- A 最小且修复已知 bug，先消除；后续 B 的 terminal tab 恢复依赖 writeText 可靠性
- B 是本切片核心价值（日用体验），需要充分手动验证
- C 可能不需要代码改动（仅测量），放最后，按结果决定是否追加优化

每个子切片独立提交，完成后 App 处于可用状态。

---

## 文件清单

| 文件 | 动作 | 子切片 |
|---|---|---|
| `PathDeck/Terminal/GhosttyTerminalEngine.swift` | 修改 | A |
| `PathDeck/Terminal/GhosttySurfaceView.swift` | 修改 | A |
| `PathDeck/ContentView.swift` | 修改 | B |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 修改 | B, C（可能）|
| `PathDeck/Terminal/TerminalSession.swift` | 修改 | B |
| `PathDeckTests/PerformanceTests.swift` | **新增** | C |
| `PathDeckTests/GhosttyTerminalEngineTests.swift` | **新增**或修改 | A |

共 7 个文件（1–2 新增，5 修改），约 200–300 行新增代码（不含性能优化分支）。

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| `@SceneStorage` 在 macOS 26.5 SwiftUI `WindowGroup` 下不可靠 | 子切片 B 状态丢失 | 降级为 `UserDefaults` 手动读写；`@SceneStorage` 只是语法糖 |
| `onSurfaceReady` 回调时机不确定（`createSurface` 可能异步延迟） | 子切片 A pending text 可能仍需等待 | 5 秒超时保护 + `NSLog` 警告，用户至少知道出了什么问题 |
| Terminal tab 恢复时 cwd 需要权限（security-scoped bookmark 范围外的路径） | 子切片 B tab 恢复失败 | cwd 不存在或无权限时降级为 home 目录，不 crash |
| `@Observable` + `@AppStorage` 属性包装器冲突 | 子切片 B 编译错误 | 不用 `@AppStorage`，改为 `UserDefaults` 手动 get/set |
| 万级目录性能基线超标 | 子切片 C 需额外优化 | 增量加载方案已设计，但作为可选分支，不阻塞本切片交付 |

---

## 验收标准

- [ ] `sendPathToTerminal` 在无 terminal 时触发 → 新建 tab 后路径完整出现在 terminal 中（不丢失）
- [ ] 退出 App → 重新打开 → 上次的文件夹路径、底部面板展开/高度、预览面板展开、排序偏好、隐藏文件状态全部恢复
- [ ] Terminal tab 数量和标题恢复（新 shell 进程，cwd 与退出前一致）
- [ ] 1k 文件目录 reload/sort/filter 自动基线通过；万级目录待手动验证
- [ ] 所有子切片独立可合并，每步 build + 单测通过
