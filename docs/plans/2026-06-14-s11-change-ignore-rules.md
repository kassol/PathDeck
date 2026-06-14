# S11：变化忽略规则

> 日期：2026-06-14　需求：change-ignore-rules（MVP 闭合 Phase 1, S11）
> 计划文件命名约定：`docs/plans/YYYY-MM-DD-<需求名>.md`，每个需求/切片一份，不复用、不覆盖。
> 权威产品定义见 `../prd.md`；工作约束见根 `AGENTS.md`；上一切片见 `2026-06-14-s10-drag-to-terminal-change-journal-upgrade.md`。

## 背景定位（MVP 闭合 Phase 1, 切片 1）

S10 将 Change Journal 从原始事件列表升级为可操作面板（时间分组 + 类型过滤 + 点击定位 + 文件标记）。但打开任何真实项目目录（含 `.git`、`node_modules`、`.DS_Store`、build 产物），变化面板立刻被噪音淹没——这是日常可用的硬性前提。

S11 添加默认忽略规则 + 用户自定义 glob 模式，使 Change Journal 只展示有意义的文件变化。

| MVP 闭合切片 | 内容 | 覆盖 PRD |
|---|---|---|
| **S11** | **变化忽略规则** | **FR-CHANGE-007** |
| S12 | 多 Terminal Tab | FR-TERM-003 |
| S13 | Terminal cwd 追踪与同步 | FR-BRIDGE-004 |
| S14 | 基础设置 | FR-SETTINGS-001/002 |

## 验证标准（4 个验证点）

### V1：默认模式过滤已知噪音

手动验证：
1. 打开含 `.git`、`node_modules`、`.DS_Store` 的项目目录
2. 终端 `touch .DS_Store` → 变化面板无新事件
3. 终端 `mkdir -p node_modules && touch node_modules/foo.js` → 变化面板不显示 `node_modules` 目录事件（`foo.js` 因 parent 非当前目录已被 FSWatcher 过滤）
4. 终端 `touch real_file.txt` → 变化面板正常显示

单元测试：`IgnoreRulesTests` — 6 个用例：
- 精确匹配（`.DS_Store` → ignored）
- 通配符匹配（`*.swp` → `session.swp` ignored）
- 正常文件不匹配（`main.swift` → not ignored）
- 用户自定义模式生效（`*.log` added → `app.log` ignored）
- 空模式列表不过滤
- 大小写不敏感（`.ds_store` → ignored，macOS 文件系统默认不区分大小写）

### V2：用户可添加/删除自定义 glob 模式

手动验证：
1. 变化面板齿轮按钮 → 弹出忽略规则 popover
2. 默认规则灰色显示（不可删除），用户规则正常显示（每行右侧 × 按钮）
3. 输入 `*.log` 并确认 → 后续 `.log` 文件事件不出现
4. 删除 `*.log` 规则 → 后续 `.log` 文件事件恢复显示
5. 自定义规则跨 App 重启持久化（UserDefaults）

单元测试：UserDefaults 读写 — 2 个用例（存入 → 读出一致；空数组 → 只有默认规则生效）

### V3：历史事件也受忽略规则影响

手动验证：
1. 已有 `.DS_Store` 事件在数据库中（S11 之前产生的历史数据）
2. S11 上线后 → 变化面板中 `.DS_Store` 历史事件消失
3. 修改忽略规则后 → 立即反映在显示中

单元测试：WorkspaceModel 显示过滤 — 1 个用例（含 `.DS_Store` 的事件列表经 IgnoreRules 过滤后不含该条目）

### V4：隐藏计数指示器

手动验证：
1. 有被忽略的事件时 → 变化面板底部显示「已隐藏 N 项」灰色文字
2. 无被忽略事件时 → 不显示
3. 修改规则后计数实时更新

## 最脆弱假设

**C 标准库 `fnmatch()` 在 macOS 上对中文文件名和 glob 通配符的组合行为正确。**

macOS 的 `fnmatch` 处理 UTF-8 字符串应无问题（POSIX 规范保证），但未在中文文件名 + 通配符组合上实测。如有问题，退路是 `NSPredicate(format: "SELF LIKE %@")`，后者明确支持 Unicode。

## 技术方案

### Part 1：IgnoreRules 工具

新增 `ChangeJournal/IgnoreRules.swift`：

```swift
import Darwin

struct IgnoreRules {
    static let defaultPatterns: [String] = [
        ".DS_Store", ".git", "node_modules",
        "build", "dist", ".cache",
        "venv", "__pycache__",
        "*.swp", "*.swo",
        ".Spotlight-V100", ".Trashes", ".fseventsd",
    ]

    private static let userDefaultsKey = "ChangeJournalIgnorePatterns"

    static var userPatterns: [String] {
        get { UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    static var allPatterns: [String] {
        defaultPatterns + userPatterns
    }

    static func shouldIgnore(fileName: String) -> Bool {
        allPatterns.contains { pattern in
            fnmatch(pattern, fileName, FNM_CASEFOLD) == 0
        }
    }
}
```

`FNM_CASEFOLD` 使匹配不区分大小写（对齐 macOS 默认文件系统行为）。匹配粒度为文件名（`lastPathComponent`），不是全路径——因为 FSWatcher 的 `handleRawEvents` 已过滤为当前目录的直接子项。

### Part 2：WorkspaceModel 过滤（两处注入）

#### 2a：`handleFSEvents` — 新事件过滤（不入库）

在调用 `recordBatch` 之前过滤：

```swift
private func handleFSEvents(_ events: [(path: String, type: ChangeEventType)]) {
    let accepted = events.filter { event in
        let fileName = URL(fileURLWithPath: event.path).lastPathComponent
        return !IgnoreRules.shouldIgnore(fileName: fileName)
    }

    let dir = currentURL.path(percentEncoded: false)
    let batch = accepted.map { (path: $0.path, type: $0.type, directory: dir) }
    try? changeStore?.recordBatch(batch)

    for event in accepted {
        guard event.type != .deleted else { continue }
        changeIndicators[event.path] = event.type
        // ... timer 逻辑不变
    }
    reload()
}
```

被忽略的事件不进 ChangeStore、不设 changeIndicator。

#### 2b：`refreshChanges` — 历史事件显示过滤

从 ChangeStore 取回后过滤（处理 S11 之前已入库的噪音）：

```swift
func refreshChanges() {
    guard let store = changeStore else { return }
    let dir = currentURL.path(percentEncoded: false)
    let raw = (try? store.recentEvents(in: dir)) ?? []
    let filtered = raw.filter { !IgnoreRules.shouldIgnore(fileName: $0.fileName) }
    changes = filtered
    hiddenCount = raw.count - filtered.count
}
```

新增属性 `private(set) var hiddenCount: Int = 0`。

### Part 3：ChangeListView 齿轮按钮 + popover

FilterBar 右侧新增齿轮按钮，点击弹出 `IgnoreRulesPopover`：

```swift
struct IgnoreRulesPopover: View {
    @State private var newPattern: String = ""
    @State private var userPatterns: [String] = IgnoreRules.userPatterns
    var onRulesChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("忽略规则").font(.headline)

            // 默认规则（灰色，不可删除）
            ForEach(IgnoreRules.defaultPatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // 用户规则（可删除）
            ForEach(userPatterns, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                    Spacer()
                    Button { removePattern(pattern) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain)
                }
            }

            // 添加
            HStack {
                TextField("glob 模式，如 *.log", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                Button("添加") { addPattern() }
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
```

每次增删后写入 `IgnoreRules.userPatterns` 并调用 `onRulesChanged()`。

底部隐藏计数：

```swift
if hiddenCount > 0 {
    Text("已隐藏 \(hiddenCount) 项")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
}
```

### Part 4：ContentView 接线

将 `hiddenCount` 和 `onRulesChanged` 传递给 ChangeListView：

```swift
ChangeListView(
    events: model.changes,
    hiddenCount: model.hiddenCount,
    onRulesChanged: { model.refreshChanges() }
) { event in
    // onNavigate 逻辑不变
}
```

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `ChangeJournal/IgnoreRules.swift` | **新增**：忽略规则工具（默认模式 + 用户模式 + fnmatch 匹配） |
| `FileWorkspace/WorkspaceModel.swift` | ① `handleFSEvents` 新事件过滤（不入库）；② `refreshChanges` 历史过滤 + `hiddenCount` 属性 |
| `ChangeJournal/ChangeListView.swift` | ① 齿轮按钮 + `IgnoreRulesPopover`；② 底部隐藏计数；③ 新增 `hiddenCount` + `onRulesChanged` 参数 |
| `ContentView.swift` | 传递 `hiddenCount` 和 `onRulesChanged` |

## 不改动

| 文件 | 理由 |
|---|---|
| `ChangeJournal/ChangeStore.swift` | 查询接口不变，过滤在 WorkspaceModel 层 |
| `ChangeJournal/ChangeEvent.swift` | 模型不变 |
| `ChangeJournal/FSWatcher.swift` | 保持通用，不注入业务规则 |
| `FileWorkspace/FileTableView.swift` | 无关 |
| `Terminal/*` | 无关 |
| `PathDeckApp.swift` | 无新菜单命令 |

## Scope

- 默认忽略模式（`.DS_Store`、`.git`、`node_modules`、`build`、`dist`、`.cache`、`venv`、`__pycache__`、`*.swp`、`*.swo`、`.Spotlight-V100`、`.Trashes`、`.fseventsd`）
- 用户可添加/删除自定义 glob 模式（UserDefaults 持久化）
- 新事件过滤（不入库）+ 历史事件显示过滤
- 齿轮按钮 + popover 查看/编辑规则
- 「已隐藏 N 项」底部指示

## Non-scope

- 临时「显示已忽略事件」切换（PRD FR-CHANGE-007 提及，后续增量）
- `.gitignore` 集成（读取项目 `.gitignore` 自动合并——增加复杂度，收益不大）
- 按目录自定义忽略规则
- Settings 面板集成（S14 统一管理）
- 正则表达式支持（fnmatch glob 覆盖主流需求）

## 实现顺序

1. `IgnoreRules.swift` — 新增工具 + 单测（6 个）
2. `WorkspaceModel.swift` — `handleFSEvents` 过滤 + `refreshChanges` 过滤 + `hiddenCount` + 单测（1+2 个）
3. `ChangeListView.swift` — 齿轮按钮 + `IgnoreRulesPopover` + 底部隐藏计数
4. `ContentView.swift` — 接线 `hiddenCount` + `onRulesChanged`
5. build + 全量单测 + 新增单测
6. GUI 走查（4 组验证标准）
7. 更新 `ChangeJournal/AGENTS.md` + 根 `AGENTS.md` 变更日志

## 工作量

1 个新文件 + 3 个改动文件 + 2 个文档更新，~150 行新代码 + ~9 个新增单测。
