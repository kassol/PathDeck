# S12：多 Terminal Tab

> 日期：2026-06-14　需求：multi-terminal-tab（MVP 闭合 Phase 1, S12）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见同日 `2026-06-14-s11-change-ignore-rules.md`。

## 背景定位（MVP 闭合 Phase 1, 切片 2）

S8 嵌入了单 Terminal 面板（⌃\` 切换 + 拖拽分割线），S9/S10 完成了 Context Bridge（发送路径 + 拖拽到终端）。当前只支持单个终端会话——CLI 重度用户需要在开发服务器、交互 shell、AI CLI agent 之间切换，单 tab 严重限制了 M2 验收标准「用户无需打开外部 Terminal 即可完成常见命令行任务」。

S12 添加多 Terminal Tab 基础能力：独立 PTY/cwd/scrollback 的多会话 + tab bar 切换。

| MVP 闭合切片 | 内容 | 覆盖 PRD |
|---|---|---|
| S11 | 变化忽略规则 | FR-CHANGE-007 |
| **S12** | **多 Terminal Tab** | **FR-TERM-003** |
| S13 | Terminal cwd 追踪与同步 | FR-BRIDGE-004 |
| S14 | 基础设置 | FR-SETTINGS-001/002 |

## 验证标准（4 个验证点）

### V1：新建 / 关闭 Tab

手动验证：
1. ⌃\` 首次打开终端 → 出现一个 tab「Terminal」+ tab bar 右侧「+」按钮
2. 点击「+」→ 新建「Terminal 2」，cwd 为当前文件夹，自动切换到新 tab
3. 新 tab 有独立 shell 会话（tab 1 运行 `export FOO=1`，切到 tab 2 运行 `echo $FOO` → 空）
4. 点击 tab 上的 × 按钮 → tab 关闭，shell 进程终止
5. 关闭最后一个 tab → 终端面板整体隐藏（`isTerminalVisible = false`）
6. 再次 ⌃\` → 创建新 tab，终端面板展开

单元测试：session 集合管理 — 4 个用例：
- 新建 → count+1 + activeID 为新 tab
- 关闭非 active → count-1 + activeID 不变
- 关闭 active → activeID 切到相邻 tab
- 关闭最后一个 → sessions 空

### V2：Tab 切换

手动验证：
1. 点击非 active tab → 切换，终端内容立即可见
2. 切回原 tab → scrollback 和进程状态完整保留
3. 两个 tab 各跑 `top` 和 `vim` → 切换无渲染错误、无黑屏
4. 切换后键盘输入进入正确的 shell（first responder 跟随 active surface）

### V3：Tab 重命名

手动验证：
1. 双击 tab 标题 → 进入行内编辑
2. 输入新名称按 Enter → 标题更新
3. 按 Esc → 取消编辑，保持原名
4. 空名称 → 不接受，保持原名

### V4：Context Bridge 对接

手动验证：
1. 打开两个 tab，tab 2 为 active
2. 文件列表右键「发送路径到终端」→ 路径出现在 tab 2（非 tab 1）
3. 拖拽文件到终端面板 → 路径出现在 active tab
4. ⌘⇧T → 路径发送到 active tab

## 最脆弱假设

**多个 GhosttySurfaceView 实例可同时存活且互不干扰。**

libghostty 的 `ghostty_app_t` 是进程级单例，设计上支持多个 `ghostty_surface_t`（cmux 项目在 split pane 模式下实证）。PathDeck 场景中只有 active tab 可见，其余 surface view 保持在 container 内但 `isHidden = true`——libghostty 内部 CVDisplayLink 是否对隐藏 surface 产生额外 CPU 开销需实测。

如果 >3 tab 出现明显卡顿，退路：对非 active surface 调用 `ghostty_surface_set_focus(false)` 降低内部刷新频率。极端退路：切换时销毁/重建 surface（代价是丢失 scrollback，可接受性低）。

## 技术方案

### Part 1：TerminalSession 值类型

新增 `Terminal/TerminalSession.swift`：

```swift
struct TerminalSession: Identifiable {
    let id: UUID
    var title: String
    let cwd: URL
}
```

轻量值类型，SwiftUI 可直接 `ForEach`。不持有 surface view 或 engine 引用——纯数据。

### Part 2：TerminalEngine 协议重设计

当前协议（单 session）：

```swift
protocol TerminalEngine {
    func makeTerminalView(cwd: URL) -> NSView
    func writeText(_ text: String)
}
```

改为多 session API：

```swift
protocol TerminalEngine: AnyObject {
    func createSession(cwd: URL) -> UUID
    func closeSession(_ id: UUID)
    func terminalView(for id: UUID) -> NSView
    func writeText(_ text: String, to id: UUID)
}
```

- `createSession`：返回 session ID。Surface view **延迟到 `terminalView(for:)` 首次调用时创建**，避免不可见 tab 提前消耗 Metal 资源。
- `closeSession`：释放对应 `GhosttySurfaceView`（deinit 中 `ghostty_surface_free` 自动清理 PTY）。
- `terminalView(for:)`：返回指定 session 的 NSView，首次调用时创建。
- `writeText(_:to:)`：向指定 session 注入文本。

### Part 3：GhosttyTerminalEngine 多 session 实现

```swift
final class GhosttyTerminalEngine: TerminalEngine {
    private var surfaceViews: [UUID: GhosttySurfaceView] = [:]
    private var sessionCwds: [UUID: URL] = [:]

    func createSession(cwd: URL) -> UUID {
        let id = UUID()
        sessionCwds[id] = cwd
        return id
    }

    func closeSession(_ id: UUID) {
        surfaceViews.removeValue(forKey: id)
        sessionCwds.removeValue(forKey: id)
    }

    func terminalView(for id: UUID) -> NSView {
        if let existing = surfaceViews[id] { return existing }
        let view = GhosttySurfaceView(frame: .zero)
        view.initialCwd = sessionCwds[id]
        surfaceViews[id] = view
        return view
    }

    func writeText(_ text: String, to id: UUID) {
        surfaceViews[id]?.insertText(text)
    }
}
```

`surfaceViews` 字典持有强引用，`closeSession` 时 remove 触发 deinit → `ghostty_surface_free`。

### Part 4：TerminalPanelView 重写为多 session 容器

当前 TerminalPanelView 是单 session 的简单 NSViewRepresentable。重写为管理多 surface 的容器：

```swift
struct TerminalPanelView: NSViewRepresentable {
    let activeSessionID: UUID?
    let engine: any TerminalEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        for subview in container.subviews {
            subview.isHidden = true
        }

        guard let id = activeSessionID else { return }
        let termView = engine.terminalView(for: id)
        if termView.superview !== container {
            container.addSubview(termView)
            termView.frame = container.bounds
            termView.autoresizingMask = [.width, .height]
        }
        termView.isHidden = false
        container.window?.makeFirstResponder(termView)
    }
}
```

所有 session 的 surface view 作为 container 子 view 保留（PTY 存活），切换时只改 `isHidden` + 焦点转移。这复用了 S8 建立的「frame:0+clipped 保活」模式——surface 不销毁，shell 会话完整保留。

`updateNSView` 触发频率：因 `activeSessionID` 是值类型（UUID?），SwiftUI 只在 ID 变化时调用——满足 `updateNSView 加 changed 守卫` 的约束（`activeSessionID` 变化即为有意义的变化）。

### Part 5：TerminalTabBar

新增 `Terminal/TerminalTabBar.swift`：

```swift
struct TerminalTabBar: View {
    @Binding var sessions: [TerminalSession]
    @Binding var activeID: UUID?
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach($sessions) { $session in
                TabItem(
                    session: $session,
                    isActive: session.id == activeID,
                    onSelect: { activeID = session.id },
                    onClose: { onCloseTab(session.id) }
                )
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 28)
        .background(.bar)
    }
}
```

`TabItem` 子视图（`TerminalTabBar` 内部 private struct）：

- 标题文本（单击切换，双击进入编辑）
- × 关闭按钮（hover 时显示）
- Active 态底部 2pt accent 色条
- 紧凑高度 28pt，对齐 macOS 原生 tab 风格

重命名交互：
- 双击 → `@State isEditing = true` → `TextField` 替换 `Text`
- Enter → 提交，写回 `$session.title`
- Esc → 取消，恢复原名
- 空名称 → 不提交

### Part 6：ContentView 集成

#### 状态变量迁移

```swift
// 移除
@State private var terminalCreated = false

// 新增 / 替换
@State private var terminalSessions: [TerminalSession] = []
@State private var activeTerminalID: UUID?
```

`terminalCreated` 的判断改为 `!terminalSessions.isEmpty`。

#### 终端首次显示

```swift
.onChange(of: model.isTerminalVisible) { _, visible in
    if visible && terminalSessions.isEmpty {
        createTerminalTab()
    }
}

private func createTerminalTab() {
    let id = terminalEngine.createSession(cwd: model.currentURL)
    let index = terminalSessions.count + 1
    let title = index == 1 ? "Terminal" : "Terminal \(index)"
    terminalSessions.append(TerminalSession(id: id, title: title, cwd: model.currentURL))
    activeTerminalID = id
}
```

#### 终端面板区域

```swift
// Tab bar（终端可见时始终显示）
if model.isTerminalVisible {
    TerminalDividerView(...)
    TerminalTabBar(
        sessions: $terminalSessions,
        activeID: $activeTerminalID,
        onNewTab: { createTerminalTab() },
        onCloseTab: { closeTerminalTab($0) }
    )
}

// Terminal view
if !terminalSessions.isEmpty {
    TerminalPanelView(activeSessionID: activeTerminalID, engine: terminalEngine)
        .frame(height: model.isTerminalVisible ? terminalHeight : 0)
        .clipped()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleTerminalDrop(providers)
        }
}
```

#### 关闭 tab

```swift
private func closeTerminalTab(_ id: UUID) {
    terminalEngine.closeSession(id)
    terminalSessions.removeAll { $0.id == id }
    if activeTerminalID == id {
        activeTerminalID = terminalSessions.last?.id
    }
    if terminalSessions.isEmpty {
        model.isTerminalVisible = false
    }
}
```

#### sendPathToTerminal / handleTerminalDrop 路由到 active tab

```swift
private func sendPathToTerminal(_ urls: [URL]) {
    if !model.isTerminalVisible {
        model.isTerminalVisible = true
        if terminalSessions.isEmpty { createTerminalTab() }
    }
    guard let activeID = activeTerminalID else { return }
    let escaped = ShellEscape.escapeMultiple(urls)
    DispatchQueue.main.async {
        self.terminalEngine.writeText(escaped, to: activeID)
    }
}
```

`handleTerminalDrop` 同理。

### Part 7：保留 TerminalSmokeView

`TerminalSmokeView`（⌃⌥⌘T 独立窗口）仍直接使用 `GhosttySurfaceView`，不走多 tab 逻辑。它是调试工具，独立于产品功能。

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `Terminal/TerminalSession.swift` | **新增**：session 值类型（id, title, cwd） |
| `Terminal/TerminalTabBar.swift` | **新增**：Tab bar SwiftUI 视图 + TabItem 子视图（切换 / 关闭 / 重命名） |
| `Terminal/TerminalEngine.swift` | 协议从单 session 改为多 session API（createSession / closeSession / terminalView / writeText） |
| `Terminal/GhosttyTerminalEngine.swift` | 实现多 session 管理（`surfaceViews` 字典 + 延迟创建 + 关闭释放） |
| `Terminal/TerminalPanelView.swift` | 重写为多 session container（container NSView + isHidden 切换 + 焦点转移） |
| `ContentView.swift` | ① 状态迁移（`terminalCreated` → `terminalSessions` + `activeTerminalID`）；② 集成 TerminalTabBar；③ `sendPathToTerminal` / `handleTerminalDrop` 目标 active session；④ `createTerminalTab` / `closeTerminalTab` 方法 |

## 不改动

| 文件 | 理由 |
|---|---|
| `Terminal/GhosttySurfaceView.swift` | 单 surface 实现不变，多实例由 engine 管理 |
| `Terminal/GhosttyApp.swift` | 进程级单例不变，天然支持多 surface |
| `Terminal/TerminalSmokeView.swift` | 调试工具，不走多 tab |
| `FileWorkspace/*` | 无关 |
| `ChangeJournal/*` | 无关 |
| `PathDeckApp.swift` | 无新菜单命令 |

## Scope

- `TerminalEngine` 协议扩展为多 session API
- `GhosttyTerminalEngine` 管理多个 GhosttySurfaceView（字典 + 延迟创建 + 关闭销毁）
- Tab bar UI：新建（+按钮）、切换（点击）、关闭（×按钮）、重命名（双击编辑）
- Tab bar 终端展开时始终可见
- 每个 tab 独立 PTY / cwd / scrollback
- 关闭最后一个 tab → 隐藏终端面板
- Send Path / 拖拽 / ⌘⇧T 路由到 active tab
- Surface view 在 container 内保活（`isHidden` 切换，不销毁）

## Non-scope

- 关闭含活跃进程的 tab 确认对话框（需 PTY 进程状态查询，libghostty C API 未暴露，后续探索）
- Tab 拖拽重排序
- Tab 持久化 / 重启恢复会话
- Tab 分屏（split pane）
- New Tab 菜单快捷键（避免与系统 ⌘T 冲突，后续可加 ⌃⇧\` 或在 Settings 中可配置）
- 非 active tab 的 CVDisplayLink 节流（实测无性能问题则不做）
- Tab 数量上限（libghostty 多 surface 无硬限制，依赖系统资源自然约束）

## 实现顺序

1. `TerminalSession.swift` — 新增值类型
2. `TerminalEngine.swift` — 协议改为多 session API
3. `GhosttyTerminalEngine.swift` — 实现多 session（字典 + 延迟创建 + 关闭释放）
4. `TerminalPanelView.swift` — 重写为 container NSView + isHidden 切换
5. `TerminalTabBar.swift` — 新增 tab bar 视图 + TabItem + 重命名交互
6. `ContentView.swift` — 状态迁移 + 集成 tab bar + 路由 active session
7. build + 全量单测 + 新增单测（session 管理 ×4）
8. GUI 走查（4 组验证标准）
9. 更新 `Terminal/AGENTS.md` + 根 `AGENTS.md` 变更日志

## 工作量

2 个新文件 + 4 个改动文件 + 2 个文档更新，~300 行新代码 + ~4 个新增单测。
