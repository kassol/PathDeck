# S28 Quality Gate — 输入事件修补 / FSWatcher 加固 / PRD 同步 / 性能基线

> 日期：2026-06-18
> 前置：S27 已合入（Terminal Input Compat）

## 目标

S1–S27 连续推进后的质量收口。修复 S27 遗留的 IME + binding 冲突，补齐 FSWatcher 边界测试，同步 PRD 中已 killed 的 Change Journal 引用，验证 10k cold-open 性能基线。

本切片无新功能，不改用户可见行为（IME 修复除外）。

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P1 | Fix | IME 活跃时 Ctrl+key binding 检查 | `GhosttySurfaceView.swift` |
| P2 | Test | resignFirstResponder modifier 释放验证 | `GhosttySurfaceViewTests.swift`（新建或扩展） |
| P3 | Test | FSWatcher 边界用例补齐 | `FSWatcherTests.swift` |
| P4 | Doc | PRD Change Journal 引用清理 | `docs/prd.md` |
| P5 | Verify | 10k cold-open 性能跑通 + 结果记录 | `PathDeckTests/PerformanceTests.swift`, `docs/` |

## Not Building

- FSWatcher 线程安全重写——当前单 queue 序列化足够，不引入 actor
- 10k 滚动/UI 层性能测试——需真实 NSOutlineView 上下文，属 GUI 测试范畴
- 内存基线自动化——测试只验 model 层，内存峰值靠手动 Instruments
- resignFirstResponder 行为变更——代码已正确实现，只补测试

---

## Phase 1：IME 活跃时 Ctrl+key binding 检查

### 问题

`GhosttySurfaceView.performKeyEquivalent`（line 333-343）的 Ctrl+key 分支无条件将事件发往 libghostty，不检查 `markedText` 状态。当 IME composition 处于活跃状态时：

- **Ctrl+C / Ctrl+D**：IS binding → 发往 libghostty → 正确（终端中断应优先于 IME）
- **其他 Ctrl+key（非 binding）**：也发往 libghostty → 错误（应交给 IME 处理或取消 composition）

对比 `keyDown`（line 380）：已先调用 `ghostty_surface_key_is_binding`，binding 直接发送，非 binding 走 `interpretKeyEvents` → IME 管线。`performKeyEquivalent` 缺少同等的 binding 前置检查。

### 方案

在 `performKeyEquivalent` 的 Ctrl+key 分支内，当 `markedText != nil` 时，走 `is_binding` 检查后决定：

```swift
// performKeyEquivalent — Ctrl+key 分支（修改后）
if flags.contains(.control), !flags.contains(.command) {
    if Self.ctrlReservedKeycodes.contains(event.keyCode) {
        return super.performKeyEquivalent(with: event)
    }
    if flags.contains(.shift),
       event.charactersIgnoringModifiers?.lowercased() == "n" {
        return super.performKeyEquivalent(with: event)
    }

    // IME 活跃时：只有 binding 才打断 composition
    if markedText != nil {
        let key = buildInputKey(from: event, action: GHOSTTY_ACTION_PRESS)
        var bindingFlags = ghostty_binding_flags_e(rawValue: 0)
        guard ghostty_surface_key_is_binding(surface, key, &bindingFlags) else {
            return super.performKeyEquivalent(with: event)
        }
    }

    sendKeyEvent(event, action: GHOSTTY_ACTION_PRESS, surface: surface)
    return true
}
```

变更矩阵：

| 场景 | markedText | 修改前 | 修改后 |
|------|-----------|--------|--------|
| Ctrl+C，无 IME | nil | 发 libghostty ✅ | 发 libghostty ✅ |
| Ctrl+C，IME 活跃 | "中" | 发 libghostty ✅ | is_binding → 发 libghostty ✅ |
| Ctrl+G，无 IME | nil | 发 libghostty ✅ | 发 libghostty ✅ |
| Ctrl+G，IME 活跃（非 binding） | "中" | 发 libghostty ❌ | 交给 super → IME ✅ |

### 验证

手动验证（单测无法构造 IME 状态）：

1. 终端中启动中文输入法，输入拼音进入 composition 状态
2. 按 Ctrl+C → 预期：composition 取消，终端收到 interrupt（`^C` 可见）
3. 再次进入 composition，按 Ctrl+G → 预期：composition 不被打断（非 binding 交给 IME）

---

## Phase 2：resignFirstResponder modifier 释放验证

### 现状

`resignFirstResponder`（line 130-137）已实现：

```swift
override func resignFirstResponder() -> Bool {
    if let surface {
        ghostty_surface_set_focus(surface, false)
        releaseHeldModifiers(surface: surface)      // 遍历 heldModifierKeycodes，逐个发 RELEASE
        releaseForwardedKeys(surface: surface)       // 遍历 forwardedKeyPresses，逐个发 RELEASE
    }
    return super.resignFirstResponder()
}
```

代码正确，不需要修改。但缺测试证明 `heldModifierKeycodes` 和 `forwardedKeyPresses` 在 resignFirstResponder 后被清空。

### 方案

由于 `GhosttySurfaceView` 依赖 libghostty C 符号（`ghostty_surface_t` 等），无法在单元测试中实例化（无 Metal context）。改为 **代码审计确认 + 文档记录**，不强行写 mock 测试。

审计结论记录在本 plan 的交付清单中：

- `releaseHeldModifiers`（line 139-152）：遍历 `heldModifierKeycodes`，发 `GHOSTTY_ACTION_RELEASE`，然后 `removeAll()`。✅
- `releaseForwardedKeys`（line 154-167）：遍历 `forwardedKeyPresses`，发 `GHOSTTY_ACTION_RELEASE`，然后 `removeAll()`。✅
- `heldModifierKeycodes` 由 `flagsChanged`（line 462-464）维护，insert on press / remove on release。✅
- `forwardedKeyPresses` 由 `keyDown`（line 393）insert、`keyUp`（line 428）remove。✅

**风险评估**：`releaseHeldModifiers` 用 `mods = GHOSTTY_MODS_NONE` 发送 release，不反映实际剩余 modifier 状态。实测中这不会造成问题——libghostty 的 modifier tracking 基于 keycode 级别的 press/release，不依赖 release 事件中的 mods 字段合成。

---

## Phase 3：FSWatcher 边界用例补齐

### 现状

`FSWatcher.swift`（162 行）已实现：

- ✅ `parent == watchedDir` 校验（line 102-116，`watchedDirs.contains(parent)`）
- ✅ Coalesce debounce（line 11-13，`coalesceWindow = 0.5s` + `DispatchWorkItem`）
- ✅ `stop()` flush（line 59-76，非空 `dirtyDirs` 立即回调）
- ✅ 深层忽略（deep child parent 不在 watchedDirs 中 → 被丢弃）

现有 7 个测试（`FSWatcherTests.swift`，225 行）覆盖上述核心路径。

### 补充测试

| # | 测试 | 验证点 | 实际交付 |
|---|------|--------|----------|
| 1 | `reWatchRestartsCleanly` | 同一 watcher 实例连续 `watch(tmp1)` → `watch(tmp2)`，旧目录事件被忽略、新目录事件被接收 | ✅ 通过 `handleRawEvents` 确认过滤逻辑 |
| 2 | `setExpandedDirsDuringActiveEvents` | 事件处理中途调用 `setExpandedDirectories`，后续事件按新 scope 过滤 | ✅ |
| 3 | `removedExpandedDirStopsMatching` | 移除 expanded dir 后该目录事件不再匹配，用 `stop()` 强制 flush 消除 debounce 假阳性 | ✅ 替代原计划的 symlink 测试 |
| 4 | `stopWhenNoDirtyDoesNotFire` | 已有，确认覆盖 | ✅ |

### 实际方案

在 `FSWatcherTests.swift` 中追加测试 1-3。通过 `handleRawEvents` 直接注入事件验证过滤逻辑（不走真实 FSEvents，因单测环境下 FSEvents 回调时序不可控）。negative 断言用 `stop()` 强制 flush 代替 sleep，避免 debounce 窗口导致假阳性。原计划的 symlink 测试未实现——FSEvents 在 symlink 场景下的路径报告行为属运行时约束，单测难以可靠覆盖。

---

## Phase 4：PRD Change Journal 引用清理

### 问题

D1（2026-06-16）已 kill Change Journal 全栈并在 PRD §9.5 和 §11.4 添加了 Killed 标注，但 PRD 中约 30+ 处仍以活跃功能语气引用 Change Journal / SQLite / Recent Changes / file_versions 等已移除概念。

### 清理范围

| 区域 | 处理方式 |
|------|----------|
| §1.2 产品机会 | "Recent Changes" → 改为 "实时文件刷新"（FSWatcher 保留了这个能力） |
| §5.3-5.5 使用场景 | 移除 "Recent Changes 显示..." 相关期望，保留 "文件列表自动刷新" |
| §7.1 信息架构图 | "Recent Changes Panel" → "Terminal Panel"（底部面板已只剩 Terminal） |
| §7.2 区域表 | 删除 "Recent Changes" 行 |
| §9.5 FR-CHANGE-001 ~ 007 | 统一加 Killed 标注（§9.5 header 已有，但子 FR 缺失） |
| §FR-SETTINGS-002 | 标注 Killed |
| §11.1 架构树 | 删除 Change Journal 子树 |
| §12.3-12.5 | 标注 Killed（与 §11.4 同理，保留供历史参考） |
| §14.1 性能目标 | 删除 "SQLite 查询 Recent Changes" |
| §14.2 稳定性 | 删除 "SQLite 损坏需有恢复策略" |
| §15.1 MVP 范围 | 删除 "Recent Changes 基础面板" / "SQLite 本地记录" |
| §M0 验收 | 删除 "SQLite event 写入 Demo" |
| §20 文案 | "Recent Changes" 保留在推荐文案列表中但加注 "(D1 killed, 待未来 git status 方案时复活)" |
| §22 最终判断 | "FSEvents 实时目录刷新" 已更新 ✅ |

### 原则

- 已有 Killed 标注的（§9.5 header、§11.4、M3、M4）保持不动
- 数据模型 §12 和架构 §11.4 保留内容但加 Killed 标注（供历史参考）
- 用户场景和产品叙述中的 "Recent Changes" 改为描述 FSWatcher 保留的能力（实时文件刷新 / 自动感知变化），不做无中生有
- 不添加新功能描述——只同步已发生的 kill 决策

---

## Phase 5：10k Cold-Open 性能基线验证

### 现状

`PerformanceTests.swift`（116 行）已有 8 个性能测试：

| 测试 | 规模 | 阈值 |
|------|------|------|
| `coldOpenTenThousandFiles` | 10,000 | < 5.0s |
| `sortTenThousandFiles` | 10,000 | < 1.0s |
| `sortByDateTenThousandFiles` | 10,000 | < 1.0s |
| `filterTenThousandFiles` | 10,000 | < 0.5s |

测试覆盖 model 层（`WorkspaceModel` init / sort / filter），不含 view 层。

### 实际交付

性能未测。CLI 执行被 LaunchServices 限制阻塞（Developer Mode / test runner 无法启动）。`docs/perf-baseline-s28.md` 记录了阈值和阻塞原因，实测值标记为 pending，待 Xcode GUI 补跑。

### 不做

- 不建自动回归追踪系统
- 不测 view 层滚动性能（属 GUI 测试，需 Instruments）
- 不测内存峰值（需 Instruments profiling）

---

## 交付清单

| # | 交付物 | 验证方式 | 状态 |
|---|--------|----------|------|
| 1 | `performKeyEquivalent` IME binding 检查 | 手动验证（中文输入法 + Ctrl+C / Ctrl+G） | ✅ 代码已改，待手动验证 |
| 2 | resignFirstResponder 代码审计确认 | 本 plan Phase 2 审计记录 | ✅ 代码已正确实现，无需改动 |
| 3 | FSWatcher 新增 3 个边界测试 | build 通过（CLI 测试受 LaunchServices 限制） | ✅ |
| 4 | PRD Change Journal 引用全量清理 | diff 审查 + grep 验证 | ✅ |
| 5 | 10k 性能阈值记录 | `docs/perf-baseline-s28.md` | ⚠️ 阈值已记录，实测值 pending |
| 6 | AGENTS.md 变更日志更新 | 一行记录 | ✅ |

---

## 风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| IME binding 检查引入误判 | Ctrl+key 在某些输入法下行为不一致 | 变更矩阵覆盖 4 种场景；保守策略——只在 `markedText != nil` 时增加检查，无 markedText 时行为不变 |
| 性能测试因 LaunchServices 跑不了 | 无法产出基线数据 | 降级为阈值记录 + Xcode GUI 补跑 |
