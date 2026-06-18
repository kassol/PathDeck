# S30 Sidebar — Favorites 合入 Pinned 单一区块

> 日期：2026-06-18
> 前置：S29 已合入（OutlineDataSource crash 防御 / IME 对齐 / FSWatcher deadlock fix）
> 触发：评审复核指出 Favorites（静态五项）的语义已被 Pinned（bookmark 持久化、拖拽添加、右键移除）完全覆盖

## 目标

把 Sidebar 两个 section（Favorites + Pinned）合并为单一 "Favorites" section。新用户首次启动 seed 五项默认入口（保持 Finder-like 初体验），其余路径都走 Pinned 现有数据通道。无新功能，是一次去重收敛。

## 已确认的子决策

| # | 决策 | 行为 |
|---|------|------|
| 1B | 老用户不补 seed | UserDefaults 已存在 `pinnedFolderBookmarks` key（无论空非空）→ 不 seed |
| 2A | 删空后不自动恢复 | 用户手动删到空 → 永久空，不再回填默认 |
| 3B | Section 标题用 "Favorites" | 复用 S25 已翻译的 `Favorites` / `收藏` String Catalog key，省一次 i18n 改动 |

判定路径汇总：

| UserDefaults 状态 | 行为 |
|---|---|
| 无 `pinnedFolderBookmarks` 且无 `pinnedFolders` legacy | 首次启动 → seed 五项 |
| 无 `pinnedFolderBookmarks` 但有 `pinnedFolders` legacy | 老 legacy 用户 → 走现有 `migrateLegacy`，不额外 seed |
| 有 `pinnedFolderBookmarks`（空数组或非空均算） | 按存量加载，不 seed |

关键：1B + 2A 的区分点 = "key 是否曾经写过"，而不是"数组是否空"。`UserDefaults.object(forKey:) != nil` 是判据。

## Scope

| Phase | 类型 | 需求 | 涉及文件 |
|-------|------|------|----------|
| P1 | Feat | `PinnedFolders` 增加 seed default + 可注入 UserDefaults | `PathDeck/SidebarView.swift` |
| P2 | Refactor | `SidebarView` 删除静态 `favorites` 数组与 "Favorites" Section，"Pinned" Section 改名 "Favorites" | `PathDeck/SidebarView.swift` |
| P3 | i18n | 删除未使用的 `"Pinned"` / `"固定"` String Catalog 条目 | `PathDeck/Localizable.xcstrings` |
| P4 | Test | seed/migrate 三分支单测 | `PathDeckTests/PinnedFoldersSeedTests.swift`（新增） |
| P5 | Docs | AGENTS.md 两处 Sidebar 描述同步 | `AGENTS.md` |

## Not Building

- **不引入"恢复默认 Favorites"菜单** — 跟 2A 矛盾，且需求未提
- **不修改 `NSWorkspace.shared.icon` 取图标的视觉路径** — 系统目录（Desktop/Documents/Downloads/Home/Applications）经 NSWorkspace 会得到 Finder 一致的彩色文件夹图标，无需 SF Symbols 回退
- **不动 `SidebarDropDelegate` 与 `Remove from Sidebar` 右键** — 五项 seed 默认值与拖拽添加的项完全同质，用户可以右键移除任意默认项（这是 1B+2A 的隐含语义：默认项不享有特殊地位）
- **不动 P1 路线图（iCloud Drive / Volumes / Recents）** — 是后续 sprint 的事，S30 只做去重
- **不改 `lastPathComponent` 显示** — Home 目录会显示真实用户名（如 `kassol`），与原 Favorites 用 `NSUserName()` 一致；其它四项（Desktop/Documents/Downloads/Applications）`lastPathComponent` 直接命中英文名，与原 Favorites label 一致

---

## Phase 1：PinnedFolders seed default + UserDefaults 注入

### 当前结构（SidebarView.swift:6-91）

```swift
@Observable
final class PinnedFolders {
    static let shared = PinnedFolders()

    private let bookmarkKey = "pinnedFolderBookmarks"
    private let legacyKey = "pinnedFolders"
    // ...
    private init() {
        if let stored = UserDefaults.standard.array(forKey: bookmarkKey) as? [Data] {
            loadFromBookmarks(stored)
        } else if let paths = UserDefaults.standard.stringArray(forKey: legacyKey) {
            migrateLegacy(paths)
        }
    }
}
```

### 改造

```swift
@Observable
final class PinnedFolders {
    static let shared = PinnedFolders(userDefaults: .standard)

    private let bookmarkKey = "pinnedFolderBookmarks"
    private let legacyKey = "pinnedFolders"
    private let defaults: UserDefaults
    private(set) var items: [URL] = []
    private var bookmarks: [Data] = []

    init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
        if defaults.object(forKey: bookmarkKey) != nil {
            if let stored = defaults.array(forKey: bookmarkKey) as? [Data] {
                loadFromBookmarks(stored)
            }
        } else if let paths = defaults.stringArray(forKey: legacyKey) {
            migrateLegacy(paths)
        } else {
            seedDefaults()
        }
    }

    private func seedDefaults() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            home.appending(path: "Desktop"),
            home.appending(path: "Documents"),
            home.appending(path: "Downloads"),
            home,
            URL(fileURLWithPath: "/Applications"),
        ]
        for url in candidates {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path(percentEncoded: false)),
                  let data = createBookmark(for: standardized) else { continue }
            items.append(standardized)
            bookmarks.append(data)
        }
        persist()  // 立即 persist → bookmarkKey 写入，下次启动走"已存在"分支，不再 seed
    }
}
```

### 关键点

- `seedDefaults()` 末尾 `persist()` 必须执行 —— 否则下次启动仍会 seed，破坏 2A
- 默认项 fileExists 校验：开发机或 CI 环境可能没有 `~/Desktop`（如 sandbox 限制），跳过缺失项不报错
- `Applications` 用绝对路径 `/Applications`，不要拼 `home.appending(path:"Applications")`
- 所有其它方法（`add`/`remove`/`persist`/`loadFromBookmarks`/`migrateLegacy`/`createBookmark`/`resolveBookmark`）的 `UserDefaults.standard` 直接引用，全部换成 `defaults` 实例

### 风险

- 注入式 init 对 `shared` 单例无破坏（外部仍调 `PinnedFolders.shared`），但 `private init()` 变 `init(userDefaults:)` 暴露后理论上有人能 `PinnedFolders(userDefaults: .standard)` 拿到第二个实例。当前代码仅 `SidebarView` 和测试访问，**保留 `internal init` 不加 `private`** 是为了测试可注入；通过命名约定（注释一句 "测试入口，业务侧请用 shared"）即可。不引入 protocol/factory 抽象。

---

## Phase 2：SidebarView 合并

### 当前（SidebarView.swift:93-144）

- `static let favorites: [...]` 五项静态数组
- `Section("Favorites")` 渲染静态数组（Label + SF Symbol）
- `if !pinnedFolders.items.isEmpty { Section("Pinned") { ... } }` 渲染用户 pinned

### 改造

- 删除 `static let favorites` 整段
- 删除 `Section("Favorites")` 静态分支
- "Pinned" Section 改名 `Section("Favorites")`
- 移除 `if !pinnedFolders.items.isEmpty` 守卫 —— seed 后默认不为空，用户故意删空时空 section 标题也无伤大雅，与 Finder 行为一致；保留守卫的话用户删空后 section 完全消失会让人困惑（"我侧栏的 Favorites 哪去了"）

### 改完后的 body（示意）

```swift
var body: some View {
    List(selection: Binding(
        get: { currentURL.standardizedFileURL },
        set: { if let url = $0 { onNavigate(url) } }
    )) {
        Section("Favorites") {
            ForEach(pinnedFolders.items, id: \.self) { url in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                }
                .tag(url.standardizedFileURL)
                .contextMenu {
                    Button("Remove from Sidebar") {
                        pinnedFolders.remove(url)
                    }
                }
            }
        }
    }
    .listStyle(.sidebar)
    .onDrop(of: [UTType.fileURL], delegate: SidebarDropDelegate(pinnedFolders: pinnedFolders))
}
```

### 风险

- Home 目录显示问题：`url.lastPathComponent` 对 `/Users/kassol` 返回 `"kassol"`，原 Favorites 是 `NSUserName()` 也返回 `"kassol"` —— 行为对齐。
- Applications 显示 `"Applications"`（英文），原 Favorites 也是英文，无回归。
- 中文环境下系统目录显示：macOS Finder 走 `localizedName`，这里仍是 `lastPathComponent`（英文）。**这是 S25 i18n 未覆盖的现存问题**，不在 S30 scope 内修，留作后续 issue。

---

## Phase 3：i18n cleanup

`Localizable.xcstrings:504-512` 中 `"Pinned"` → `"固定"` 条目不再被引用。

- 删除条目
- `Favorites` / `收藏`（行 200-208）保留
- `Remove from Sidebar` / `从侧栏移除`（行 534-542）保留

### 风险

无运行时风险，仅为 hygiene。S25 是 73 条全量本地化，删 1 条降为 72。

---

## Phase 4：测试

新文件 `PathDeckTests/PinnedFoldersSeedTests.swift`：

### Test 1：首次启动 seed 五项

```swift
@Test
func seedsDefaultsOnFreshInstall() {
    let suiteName = "PathDeckTests-seed-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let folders = PinnedFolders(userDefaults: defaults)

    // 不强校验五项全部存在（CI 环境可能缺 ~/Desktop），只校验至少 seed 了 Home 和 /Applications
    #expect(folders.items.contains { $0.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL })
    #expect(folders.items.contains { $0.standardizedFileURL == URL(fileURLWithPath: "/Applications").standardizedFileURL })
    #expect(defaults.object(forKey: "pinnedFolderBookmarks") != nil)  // persist 已写入
}
```

### Test 2：老用户（key 已存在空数组）不 seed

```swift
@Test
func skipsSeedWhenKeyExistsEmpty() {
    let suiteName = "PathDeckTests-empty-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set([Data](), forKey: "pinnedFolderBookmarks")

    let folders = PinnedFolders(userDefaults: defaults)
    #expect(folders.items.isEmpty)
}
```

### Test 3：legacy 用户走 migrate 不 seed

```swift
@Test
func migratesLegacyAndSkipsSeed() throws {
    let suiteName = "PathDeckTests-legacy-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("PathDeckTests-legacy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    defaults.set([tmp.path], forKey: "pinnedFolders")

    let folders = PinnedFolders(userDefaults: defaults)
    #expect(folders.items.count == 1)
    #expect(folders.items.first?.standardizedFileURL == tmp.standardizedFileURL)
    // 不应混入 Desktop/Documents 等默认值
    #expect(!folders.items.contains { $0.lastPathComponent == "Desktop" })
}
```

### Test 4：seed 后再次启动幂等

```swift
@Test
func seedIsIdempotentAcrossLaunches() {
    let suiteName = "PathDeckTests-idempotent-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = PinnedFolders(userDefaults: defaults)
    let firstCount = first.items.count
    _ = first  // 防 ARC 提前回收

    let second = PinnedFolders(userDefaults: defaults)
    #expect(second.items.count == firstCount)  // 不会重复 seed 翻倍
}
```

### 现有测试

`PathDeckTests/PinnedFoldersBookmarkTests.swift` 中 bookmark round-trip 测试不受影响，保持不动。

---

## Phase 5：文档同步

`AGENTS.md` 两处需要改：

1. **行 56**（目录索引）：
   - 旧：`PathDeck/SidebarView.swift Sidebar（Favorites + Pinned）+ PinnedFolders bookmark 持久化`
   - 新：`PathDeck/SidebarView.swift Sidebar（统一 Favorites 区块）+ PinnedFolders bookmark 持久化（首次启动 seed 默认五项）`

2. **行 82**（Sidebar 扩展路线段）：
   - 旧：`当前 Sidebar 含两个 section：Favorites（Desktop/Documents/Downloads/Home/Applications，静态）+ Pinned（用户拖拽文件夹固定…）`
   - 新：`当前 Sidebar 单一 Favorites section：默认 seed Desktop/Documents/Downloads/Home/Applications（首次启动），其余拖拽添加 / 右键移除，`PinnedFolders` + bookmark data 持久化（S16 升级，S30 合并），`DropDelegate` 仅接受 `UTType.folder``

3. **行 47**（S29 后的 sprint 累计描述末尾）：追加一句
   - `S30 Sidebar Merge：Favorites 静态块合入 Pinned，首次启动 seed 五项默认入口，统一为单一 Favorites section。`

---

## 验证

### 自动（必须）

```bash
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck build
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck \
  -destination 'platform=macOS' \
  -only-testing:PathDeckTests/PinnedFoldersSeedTests \
  -only-testing:PathDeckTests/PinnedFoldersBookmarkTests \
  test
```

### 手动（Xcode 内跑）

| 场景 | 操作 | 预期 |
|---|---|---|
| 1 | 删 `~/Library/Preferences/in.riverflows.PathDeck.plist`（清干净 UserDefaults）→ 启动 App | sidebar 显示 5 项：Desktop / Documents / Downloads / kassol / Applications，section 标题 "Favorites" |
| 2 | 场景 1 后 → 拖一个新文件夹进 sidebar | 第 6 项追加在末尾 |
| 3 | 场景 2 后 → 右键 Desktop "Remove from Sidebar" → 重启 App | Desktop 不会重新出现（验证 2A）|
| 4 | 场景 3 后 → 右键剩余每一项删完 → 重启 App | section "Favorites" 标题仍在，列表为空（验证 2A 永久空）|
| 5 | 启动一个有老 Pinned 列表的存量用户（直接跑当前 main 装的 App，然后切到 S30 build）| 已有 pinned 列表保持原样，不被注入默认五项（验证 1B）|
| 6 | 切换系统语言到简体中文 → 重启 | section 标题显示 "收藏" |

---

## 回滚

- 改动隔离在 `SidebarView.swift` + `Localizable.xcstrings` + 一个新测试文件 + AGENTS.md
- 回滚命令：`git revert <s30 commit>` 即可恢复双 section
- 用户侧数据影响：seed 写入的 5 个默认 bookmark 留在 UserDefaults 中。回滚后这 5 项会出现在旧版 "Pinned" section 里（视为用户主动 pinned），不算 data corruption。

---

## Open Questions

无。三个子决策已拍板，技术路径无歧义。

## Acceptance

- Phase 1–5 全部交付
- 4 个新单测 + 现有 bookmark 单测全绿
- 手动验证 6 个场景通过
- AGENTS.md 三处描述同步
- commit message 遵循仓库规范（中性指代，无个人称谓）
