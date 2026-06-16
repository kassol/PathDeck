# Pre-S22: Stabilization & Beta Gate

> 日期：2026-06-16
> 前置：S1–S21 全部闭合，M0–M5 主体交付，171 单测，build green
> 目标：修复 CI 测试 runner、补齐 10k 性能基线、清理杂项，为 S22（CLI helper）扫清前置

---

## 背景

S21 质量加固后项目处于自然拐点。两个遗留问题阻塞 Beta gate：

1. **xcodebuild CLI 测试 runner 无法启动**——LaunchServices 报错，非代码问题
2. **10k 文件性能未验证**——PRD FR-FILE-002 / §14.1 硬要求，当前自动基线仅 1k

另有一个 gitignore 拼写错误导致 `design/shots/` 意外 untracked。

---

## Slice 1：修复 xcodebuild 测试 runner

### 问题

```
Testing failed:
  Could not launch "PathDeckTests"
  Failed to install or launch the test runner.
  The LaunchServices launcher has returned an error.
```

Build 正常通过。测试 target 配置为 hosted（`TEST_HOST = $(BUILT_PRODUCTS_DIR)/PathDeck.app/.../PathDeck`），需要先启动宿主 app。

### 根因

Developer Mode 未启用（`DevToolsSecurity -status` → disabled）。macOS Ventura 起 LaunchServices 拒绝启动 debug 签名的 app bundle。

### 解法

**临时绕过**：显式指定 destination 即可跑通：

```bash
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck \
  -only-testing:PathDeckTests \
  -destination 'platform=macOS,arch=arm64' \
  test
```

**永久修复**：`sudo DevToolsSecurity -enable`（需管理员密码，一次性）。

### 附带修复：reveal 测试 /var vs /private/var firmlink 不一致

3 个 reveal 测试（revealSingle / revealMultiple / revealMixed）因 URL 全路径相等断言失败。根因：macOS `/var` → `/private/var` 是 firmlink（非 symlink），`standardizedFileURL` 将 `/private/var` 反规范化为 `/var`，但 `FileManager.contentsOfDirectory` 返回的子项 URL 保持 `/private/var`。`URL.resolvingSymlinksInPath()` 也不解析 firmlink。此问题仅影响临时目录路径，正常用户路径 `/Users/...` 不受影响。

修复：reveal 测试改为语义断言（`lastPathComponent` + count），不做 URL 全路径相等比较。

### 交付标准

- `xcodebuild ... -only-testing:PathDeckTests test` 或 Xcode ⌘U 输出 **171 tests passed**

---

## Slice 2：10k 文件性能基线

### 现状

`PathDeckTests/PerformanceTests.swift` 4 个测试（reload / name sort / date sort / filter），全部 1k 文件，model 层纯函数，不涉及 NSTableView。

阈值：reload < 1.0s / sort < 0.2s / filter < 0.1s。

### 方案

在同文件新增 4 个 10k 变体，复用 `createTempDirectory(fileCount:)`：

| 测试 | fileCount | 阈值 | 理由 |
|---|---|---|---|
| `reloadTenThousandFiles` | 10_000 | < 5.0s | 线性外推 1k→10k 约 ×5–8（文件创建 I/O 主导） |
| `sortTenThousandFiles` | 10_000 | < 1.0s | O(n log n)，10k 增长约 ×6.6 |
| `sortByDateTenThousandFiles` | 10_000 | < 1.0s | 同上 |
| `filterTenThousandFiles` | 10_000 | < 0.5s | O(n) 线性 |

阈值先设保守值，首次跑通后根据实测收紧。

### 视图层验证

model 层 10k 不代表 NSTableView 滚动流畅。补一条手动验证步骤：

> 在 Xcode 运行 PathDeck → 打开 `/usr/share/doc` 或任意含 10k+ 文件的目录 → 快速滚动列表 → 预期：无明显卡顿、内存不超 200MB。

若 NSTableView 已用 lazy loading / row recycling（AppKit 默认行为），10k 应无问题。卡顿则开独立优化 slice。

### 涉及文件

- `PathDeckTests/PerformanceTests.swift`：新增 4 个 `@Test` 方法

---

## Slice 3：杂项清理

### 3a. 修复 gitignore

`.gitignore:17` 写的 `design/.shots/`，实际目录是 `design/shots/`（无前导点）。

修复：`design/.shots/` → `design/shots/`

### 3b. PRD FinderSync Kill 标注

`docs/prd.md` M5 scope 中 "Finder 右键 Open in PathDeck" 加注释标记为 Kill：

```
Finder 右键 Open in PathDeck  ← [Kill] PathDeck 是 Finder 替代，不做 FinderSync Extension
```

同步 AGENTS.md M5 变更日志（一行即可）。

### 涉及文件

- `.gitignore`：1 行修改
- `docs/prd.md`：M5 scope 标注
- `AGENTS.md`：变更日志追加

---

## 执行顺序

1. Slice 3（杂项清理）—— 最小改动，先收
2. Slice 2（10k 性能基线）—— 新增测试
3. Slice 1（测试 runner 修复）—— 环境排查，可能需多轮尝试

单 commit per slice。全部通过后 Pre-S22 闭合，进入 S22（CLI helper）。

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| LaunchServices CLI 问题无法修复 | CI 不能跑单测 | Xcode GUI ⌘U 作为 fallback，CLI runner 问题记录为已知限制 |
| 10k reload 超 5s | 阈值需调整或优化 | 先跑一次看实测数据，再决定是否开优化 slice |
| 10k 视图层卡顿 | 需独立优化 slice | NSTableView 默认 row recycling，大概率无问题；卡顿则开 S22.5 |
