# S18：系统入口（Finder 右键 + URL Scheme + Services）

> Sprint：S18
> 里程碑：M5（系统入口与 Beta）Phase 2
> 前置：S17 闭合（126 单测通过，M5 Phase 1 已交付：窗口状态恢复 + writeText 竞态修复 + 1k 性能基线）
> PRD 对应：FR-EXT-001（P1 Open/Reveal/Open Selection）、FR-EXT-002（P2 Open Terminal Here）、FR-EXT-003（P1 URL Scheme）、§20.1 命名规范、§14.4 原生体验（右键菜单）

> ⚠️ **签名以文末『实现修订（review 复核后）』为准**：下文设计段与代码片段中的 `Route.reveal(URL)` / `Route.terminal(URL)` / `reveal(_ fileURL:)` 为初稿，实现后经评审已改为 `Route.reveal([URL])`、`Route.terminal(URL, requireConfirmation:)`、`reveal(_ fileURLs: [URL])`；表格选择信号 `scrollToURL: URL?` 已升级为 `revealSelection: [URL]?`。后续 agent 请直接对照代码与修订表，勿照搬下文初稿签名。

---

## 目标

让 PathDeck 接入 macOS 系统工作流——用户能从 Finder 右键、`pathdeck://` URL、或其他 App/脚本唤起 PathDeck 并直达目标路径，且始终复用同一个运行实例（不开新进程、不开新窗口）。这是 M5「系统入口」的标志性价值，也是「App 可作为日常文件工作台试用」的入口前提。

三类外部入口（URL Scheme / Finder Services / 文件夹「打开方式」）收敛到同一条导航路由，复用现成的 `WorkspaceModel.navigate(to:)`、`selectedURLs + scrollToURL` 高亮范式与 `createTerminalTab()`，最大新增量集中在「Info.plist 独立化」与「外部入口 → model 的归一桥接」。

---

## 不做（边界，违反即偏离 M5 范围）

- **FIFinderSync Extension（顶级右键「Open in PathDeck」文案）**：唯一能在文件夹右键一级菜单直出自定义文案的方案，但强制独立 Extension target + Extension 自身被沙盒 + 需 App Group 容器与主 App 通信，与「非沙盒文件工作台」（决策 D1）整体形态相悖，且 macOS 26.x 有 FinderSync 失效/崩溃报障。留作 M6 按用户反馈评估，可在现有基础上叠加。
- **`pathdeck` CLI helper**：URL Scheme + Services 已覆盖「右键打开」与「协议唤起」两大入口，CLI 是 power-user 增量；PRD §3 亦标「后续如需」。留 M6。
- **Terminal 右侧布局**：底部面板已满足 Open Terminal Here；右侧是布局重构，非本切片范围。
- **多窗口独立 workspace**：当前单 `WindowGroup` 单 workspace，S17 已明确多窗口恢复留后续。本切片所有外部入口路由到既存单窗。

---

## 设计：外部入口归一（AppRouter 中介）

当前 `model` 是 `ContentView` 的 `@State`（`ContentView.swift:17`，每个 `ContentView` 自建、非单例、非注入）。而 URL Scheme 的 `application(_:openURLs:)` 与 NSServices 的 `servicesProvider` handler **都活在 `model` 之外**（AppDelegate / @objc 服务类），拿不到 `@State model`。这是真实的架构张力：无论用哪条系统入口，都需要一座「model 外 → model」的桥。

用一个轻量 `AppRouter`（`@Observable` 单例）把三类入口归一，消除「`onOpenURL` vs `application(_:openURLs:)` vs `servicesProvider` 各自为政 + 双触发」的边界情况：

```
Finder Services ─┐  @objc servicesProvider
文件夹 Open With ─┤  application(_:openURLs:)   ┐
pathdeck:// URL ─┤  application(_:openURLs:)   ├─→ AppRouter.request(.open|.reveal|.terminal, url)
（CLI 留 M6）    ─┘                              ┘            │
                                                            ▼
                              ContentView.onChange(of: router.pending)
                                                            │
              ┌──────────────────┬───────────────────────┬─┘
        .open │            .reveal│              .terminal│
   model.navigate(to:)  model.reveal(url:)   navigate + createTerminalTab()
                        （navigate 父目录 +    （cwd 写死 currentURL，
                         selectedURLs+scrollToURL）  须先 navigate）

   LSMultipleInstancesProhibited=YES → 第二次唤起路由到既存进程，永不开新进程
```

**为什么用 AppRouter 而非直接 `.onOpenURL` 闭包捕获 `model`**：
1. `.onOpenURL` 挂 `WindowGroup` 上有已知 quirk——每个 URL 可能复制出新窗口（社区实证，见风险表）；AppRouter + `application(_:openURLs:)` 路由可控。
2. NSServices handler 本就在 `model` 之外，无论如何要桥接；AppRouter 让 URL Scheme 与 Services 共用同一座桥，而非两套。
3. 单一汇聚点便于安全校验、便于未来接 CLI，符合「通过设计消除边界情况」。

`AppRouter.pending` 设计为「一次性令牌」（消费后置 nil），避免窗口重建时重放。

---

## 子切片 A：Info.plist 独立化 + URL Scheme（FR-EXT-003 + 单实例）

含本 Sprint 全部基础设施（plist 独立化 + AppRouter + 单实例），是 B/C 的前置。

### 问题

- `GENERATE_INFOPLIST_FILE = YES`（`project.pbxproj:444,492`），无独立 Info.plist。`CFBundleURLTypes`/`CFBundleDocumentTypes`/`NSServices` 都是「数组套字典」结构，`INFOPLIST_KEY_*` build setting 只能注入标量，**无法表达**——必须切独立 plist 文件。当前 app target 仅有一个 `INFOPLIST_KEY_NSHumanReadableCopyright = ""`（`:445,493`）。
- 全工程零 URL 处理：无 `.onOpenURL`、无 `application(_:openURLs:)`、无 `NSApplicationDelegate`（grep 证实，`PathDeckApp.swift` 仅 `init` 调 `ShellIntegration.prepare()`）。
- `WorkspaceModel.navigate(to:)`（`:132-140`）不校验路径存在性/isDirectory（`openFolder()` 经 `NSOpenPanel` 间接保证），外部 URL 入口必须自行校验。
- `LSMultipleInstancesProhibited` 缺失，多开会启多进程，URL/Service 落到不同实例。

### 方案

**1. Info.plist 独立化（pbxproj 最小 4 处改动）**

| 改动 | 落点 | 说明 |
|---|---|---|
| 新建 `PathDeck/Info.plist` | target 根目录 | 承载 `CFBundleURLTypes` + `LSMultipleInstancesProhibited`（A）、`NSServices`（B）、`CFBundleDocumentTypes`（C） |
| 加 `INFOPLIST_FILE = PathDeck/Info.plist` | Debug config `BDA2E8911`（`:444` 附近）+ Release config `BDA2E8912`（`:492` 附近） | 两个 buildSettings 块各一行 |
| 保留 `GENERATE_INFOPLIST_FILE = YES` | `:444,492` | 片段 + 自动生成合并：`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`/`CFBundleExecutable` 等仍由 pbxproj 提供，无需手抄 |
| `membershipExceptions` 追加 `Info.plist` | `BDA2E8A3`（`:41-45`，当前仅排除三个子目录 AGENTS.md） | **关键陷阱**：objectVersion=77 synchronized root group（`BDA2E871`，`:51-58`）会把 `PathDeck/Info.plist` 当 resource 自动拷入 bundle 的 `Contents/Resources/`，与 `INFOPLIST_FILE` 指向冲突致 build 失败（与既有 AGENTS.md 同名冲突同类，见根 AGENTS.md「编码与协作」） |

**实现首步（30 分钟可证伪）**：切换后 `xcodebuild` clean build，`plutil -p $(...).app/Contents/Info.plist` 验证产物同时含 `CFBundleURLTypes` **与** 自动生成键（`CFBundleExecutable`/`MARKETING_VERSION`）。若 Xcode 不合并（以片段为准丢自动键导致启动失败），回退 `GENERATE_INFOPLIST_FILE = NO` + 完整 plist（更重，把所有自动键搬进文件）。

`Info.plist` 的 `CFBundleURLTypes`：
```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLName</key><string>in.riverflows.PathDeck</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>CFBundleURLSchemes</key><array><string>pathdeck</string></array>
</dict></array>
<key>LSMultipleInstancesProhibited</key><true/>
```

**2. `AppRouter`（新增 `PathDeck/AppRouter.swift`）**

```swift
@Observable final class AppRouter {
    static let shared = AppRouter()
    enum Route { case open(URL), reveal(URL), terminal(URL) }
    private(set) var pending: Route?
    func request(_ route: Route)      // 由 AppDelegate / servicesProvider 调
    func consume() -> Route?          // ContentView 消费后置 nil（一次性令牌）
}
```

**3. URL 解析 + 安全校验（新增 `PathDeck/URLSchemeHandler.swift`）**

解析 `pathdeck://open?path=/abs` 与 `pathdeck://terminal?path=/abs`（查询参数式，非 `pathdeck:///abs`——避免空 host + 路径含空格/中文/`#`/`?` 的 percent-encoding 坑）。校验链：
- `URLComponents` 取 `path` 查询项 → percent-decode → `URL(fileURLWithPath:).standardizedFileURL`
- `FileManager.fileExists(atPath:isDirectory:)`：`open`/`terminal` 要求 isDirectory=true；`reveal`（B 用）要求存在即可
- 拒绝相对路径、非 file 路径、不存在路径 → 静默丢弃 + `NSLog`（复用 `ContentView.swift:99-101` onDrop 的 isDirectory 判定范式）

**4. `NSApplicationDelegate`（`PathDeckApp.swift` 加 `@NSApplicationDelegateAdaptor`）**

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { /* pathdeck:// → URLSchemeHandler 解析 → AppRouter.shared.request */ }
    }
}
```
> 统一用 `application(_:openURLs:)` 作 URL 入口，**不挂 `.onOpenURL`**（规避 WindowGroup 复制窗口 quirk + 杜绝双触发）。`open?path` Open With（C）的 file URL 也走这里。

**5. `WorkspaceModel.reveal(_ fileURL:)`（新增，封装跨目录 reveal）**

已确认 reveal 机制现成但**散落且不完整**：`ChangeListView.onNavigate`（`ContentView.swift:245-250`）设 `selectedURLs=[url]+scrollToURL=url` 但**未 navigate 父目录**（同目录场景）。关键约束——`FileTableView`（`:264-275`）只有「表格→model」单向；**单设 `selectedURLs` 不会让表格高亮**，必须配 `scrollToURL`（`FileTableView:104-114` 消费它做 `selectRowIndexes`+`scrollRowToVisible`+`onClearScrollToURL`）。封装：
```swift
func reveal(_ fileURL: URL) {
    navigate(to: fileURL.deletingLastPathComponent())
    selectedURLs = [fileURL]
    scrollToURL = fileURL   // 触发 FileTableView 选中+滚动，消费后自动清空
}
```

**6. `ContentView` 消费 AppRouter**

在 body 顶层修饰链（`ContentView.swift:95-112` 的 `.onChange/.onDrop/.onAppear` 段）加 `.onChange(of: router.pending)`：
- `.open(url)` → `model.navigate(to: url)`
- `.reveal(url)` → `model.reveal(url)`
- `.terminal(url)` → `model.navigate(to: url)` 后 `createTerminalTab()`（cwd 写死 `model.currentURL`（`:282`），navigate 同步设 `currentURL`（`:132-140` 先设后 reload），故先 navigate 再建 tab 即得正确 cwd；并 `model.isBottomPanelVisible=true`、`activeBottomTab=.terminal`）

**改动**

| 文件 | 操作 | 摘要 |
|---|---|---|
| `PathDeck/Info.plist` | **新增** | `CFBundleURLTypes` + `LSMultipleInstancesProhibited` |
| `PathDeck.xcodeproj/project.pbxproj` | 修改 | `INFOPLIST_FILE`×2 + `membershipExceptions` 加 `Info.plist` |
| `PathDeck/AppRouter.swift` | **新增** | 三入口归一令牌 |
| `PathDeck/URLSchemeHandler.swift` | **新增** | 解析 + 安全校验 |
| `PathDeck/PathDeckApp.swift` | 修改 | `@NSApplicationDelegateAdaptor` + `AppDelegate.application(_:open:)` |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 修改 | `+reveal(_:)`（`navigate(to:)`/`selectedURLs`/`scrollToURL` 已在 `:33,35,132`） |
| `PathDeck/ContentView.swift` | 修改 | `.onChange(of: router.pending)` 消费路由 |

**测试**

- 单测 `URLSchemeHandler`：合法 `open?path=` / `terminal?path=` 解析；非法（相对路径 / 非 file / 不存在 / 文件而非目录 / 含空格+中文 percent-encoding）一律拒绝（临时目录隔离）
- 单测 `AppRouter`：request→pending→consume 置 nil 的一次性语义
- 单测 `WorkspaceModel.reveal(_:)`：临时目录建文件 → reveal → 断言 `currentURL==父目录` + `selectedURLs==[file]` + `scrollToURL==file`
- 手动走查（系统集成程序测不到）：`open "pathdeck://open?path=/tmp"` 唤起且导航；App 已运行时复用窗口不开新进程；`pathdeck://terminal?path=<dir>` 导航 + 底部终端 cwd 为该目录

---

## 子切片 B：NSServices 三项（FR-EXT-001 + FR-EXT-002 service item）

### 方案

`Info.plist` 加 `NSServices` 数组，三个 item 精确匹配 FR-EXT-001 验收文案：

| NSMenuItem | NSSendFileTypes | NSRequiredContext | 动作 |
|---|---|---|---|
| Open in PathDeck | `public.folder` | `{NSApplicationIdentifier: com.apple.finder}` | `AppRouter.request(.open)` |
| Reveal in PathDeck | `public.item` | 同上 | `AppRouter.request(.reveal)` |
| Open Selection in PathDeck | `public.item`（多选） | 同上 | 首项 reveal / 同父目录多选高亮 |
| Open Terminal Here in PathDeck（FR-EXT-002 P2） | `public.folder` | 同上 | `AppRouter.request(.terminal)` |

新增 `PathDeck/ServicesProvider.swift`：`@objc` handler 类，从 `NSPasteboard` 读 `readObjects(forClasses:[NSURL])`，转 `AppRouter.request`。`AppDelegate.applicationDidFinishLaunching` 注册 `NSApp.servicesProvider = ServicesProvider()`。

**改动**

| 文件 | 操作 | 摘要 |
|---|---|---|
| `PathDeck/Info.plist` | 修改 | `+NSServices` 四 item |
| `PathDeck/ServicesProvider.swift` | **新增** | `@objc` handler ×3（Open/Reveal/Terminal）+ NSPasteboard 读 URL |
| `PathDeck/PathDeckApp.swift` | 修改 | `applicationDidFinishLaunching` 注册 `servicesProvider` |

**测试**

- 单测 `ServicesProvider`：注入构造的 `NSPasteboard`（含临时目录 file URL）→ 断言转出正确 `AppRouter.Route`（pasteboard 读取与路由分发可单测；菜单呈现不可）
- 手动走查：Finder 选中文件夹右键 → Services → 见「Open in PathDeck / Open Terminal Here」；选中文件 → 「Reveal in PathDeck」导航父目录并高亮；多选 → 「Open Selection」。注：现代 Finder 文件夹右键 Services 在二级菜单，发现性弱（平台统一约束，C 的 Open With 与未来 FinderSync 弥补）

---

## 子切片 C：CFBundleDocumentTypes（文件夹「打开方式」+ 设为默认）

### 方案

`Info.plist` 加 `CFBundleDocumentTypes` 声明可打开 `public.folder`，`LSHandlerRank = Alternate`（**不抢占 Finder 默认 handler**）：
```xml
<key>CFBundleDocumentTypes</key>
<array><dict>
  <key>CFBundleTypeName</key><string>Folder</string>
  <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Alternate</string>
</dict></array>
```
文件夹的 file URL 经「右键 → 打开方式 → PathDeck」投递，复用 A 的 `application(_:openURLs:)`（无新代码，file URL 直接 `.open` 路由）。提供「设为默认打开方式」能力——这是 Services 做不到的、最接近「替代 Finder 入口」的强路径。

**改动**

| 文件 | 操作 | 摘要 |
|---|---|---|
| `PathDeck/Info.plist` | 修改 | `+CFBundleDocumentTypes`（public.folder, Alternate） |

**测试**

- 手动走查：文件夹右键「打开方式」见 PathDeck → 打开导航到该文件夹；右键「打开方式 → 始终用 PathDeck 打开此类」后双击文件夹由 PathDeck 接管；验证 PathDeck **不**成为默认 handler（`LSHandlerRank=Alternate`），普通双击仍走 Finder

---

## 实施顺序

```
A（Info.plist 独立化 + URL Scheme + AppRouter + 单实例 + reveal）→ B（NSServices）→ C（Open With）
```

理由：
- A 含全部基础设施（plist 独立化 + AppRouter 桥 + 单实例 + 安全校验 + reveal），是 B/C 的前置；自身交付 URL Scheme（FR-EXT-003）即可独立验证
- B 复用 A 的 AppRouter，仅增 plist NSServices 键 + provider；交付 FR-EXT-001 + FR-EXT-002 service item
- C 复用 A 的 `application(_:openURLs:)`，仅增 plist 一个键；交付「打开方式 / 设为默认」

每个子切片独立提交、独立可合并，完成后 App 处于可用状态。涉及 synchronized group 资源变动（新增 Info.plist），按根 AGENTS.md 用 **clean build**。

---

## 文件清单

| 文件 | 动作 | 子切片 |
|---|---|---|
| `PathDeck/Info.plist` | **新增** | A（建）/ B / C（增键） |
| `PathDeck.xcodeproj/project.pbxproj` | 修改 | A（`INFOPLIST_FILE`×2 + membershipException） |
| `PathDeck/AppRouter.swift` | **新增** | A |
| `PathDeck/URLSchemeHandler.swift` | **新增** | A |
| `PathDeck/ServicesProvider.swift` | **新增** | B |
| `PathDeck/PathDeckApp.swift` | 修改 | A（delegate adaptor）/ B（注册 servicesProvider） |
| `PathDeck/FileWorkspace/WorkspaceModel.swift` | 修改 | A（`+reveal(_:)`） |
| `PathDeck/ContentView.swift` | 修改 | A（消费 `router.pending`） |
| `PathDeckTests/URLSchemeHandlerTests.swift` | **新增** | A |
| `PathDeckTests/AppRouterTests.swift` | **新增** | A |
| `PathDeckTests/ServicesProviderTests.swift` | **新增** | B |
| `PathDeckTests/WorkspaceModelTests.swift` | 修改 | A（`reveal` 用例） |

共约 12 文件（6 新增 / 6 修改），估 ~350–450 行（含测试）。

---

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| `GENERATE_INFOPLIST_FILE=YES` + `INFOPLIST_FILE` 合并语义官方未逐字背书（社区实践） | A 启动失败（丢自动键） | **实现首步** clean build + `plutil -p` 验证产物含 `CFBundleURLTypes` 与自动键；不合并则回退 `GENERATE=NO` + 完整 plist（30 分钟可证伪） |
| `Info.plist` 未列入 membershipExceptions | build 失败（resource 冲突，与 AGENTS.md 同类） | A 必改 `BDA2E8A3`（`:41-45`）追加 `Info.plist` |
| `.onOpenURL` 挂 WindowGroup 复制窗口 quirk | 多窗口/重放 | 不用 `.onOpenURL`，统一走 `application(_:openURLs:)` + AppRouter 一次性令牌 |
| LaunchServices 缓存 URL scheme / document type | 开发期改 scheme/类型不生效，误判失败 | 调试用 `lsregister -f <app>` 或重装；**Sequoia 禁用 `lsregister -kill`**（破坏性）；正式靠拷入 /Applications 正常扫描 |
| `createTerminalTab()` cwd 写死 `currentURL`（`:282`） | terminal 路由 cwd 错位 | 先 `navigate`（同步设 `currentURL`）再 `createTerminalTab()`；不改其签名（外科手术最小面） |
| 设 `selectedURLs` 不触发表格高亮（`FileTableView:264-275` 单向） | Reveal 不高亮 | `reveal(_:)` 必须配 `scrollToURL`（驱动 `selectRowIndexes`+`scrollRowToVisible`） |
| NSServices 文件夹右键藏二级菜单，发现性弱 | FR-EXT-001 体验短板 | C 的 Open With + URL Scheme 多入口弥补；顶级右键留 M6 FinderSync |
| `LSMultipleInstancesProhibited` 与 S17 `@SceneStorage`/窗口恢复交互 | 外部唤起触发新场景而非导航现窗 | 手动走查「已运行时唤起复用现窗」；AppRouter 经既存 `model` 改 state |

---

## 验收标准

- [ ] `xcodebuild` clean build 通过；`plutil -p` 产物 Info.plist 含 `CFBundleURLTypes`/`NSServices`/`CFBundleDocumentTypes` 与自动生成键
- [ ] `open "pathdeck://open?path=<dir>"` 唤起并导航；`pathdeck://terminal?path=<dir>` 导航 + 底部终端 cwd 为该目录
- [ ] 非法/不存在/非目录路径被安全拒绝（单测覆盖）
- [ ] App 已运行时，任一外部入口复用同一窗口与进程（不开新窗、不开新进程）
- [ ] Finder 文件夹右键 Services 见「Open in PathDeck / Open Terminal Here」；文件 →「Reveal in PathDeck」导航父目录并高亮；多选 →「Open Selection」
- [ ] 文件夹「打开方式」见 PathDeck，可「设为默认」；`LSHandlerRank=Alternate` 不抢普通双击
- [ ] 全部子切片独立可合并，每步 clean build + 单测通过（新增 `URLSchemeHandler`/`AppRouter`/`ServicesProvider`/`reveal` 单测，临时目录隔离）

---

## 决策（已拍板，定稿）

| # | 决策 | 结论 |
|---|---|---|
| 1 | 外部入口路由机制 | ✅ **AppRouter 中介**——URL Scheme 与 NSServices 归一到同一座桥，不挂 `.onOpenURL`，规避 WindowGroup 复制窗口 + 杜绝双触发 |
| 2 | Info.plist 独立化方式 | ✅ **保留 `GENERATE=YES` + `INFOPLIST_FILE` 片段合并**（改动最小）；实现首步 `plutil` 证伪，不合并则回退 `GENERATE=NO` 完整 plist |
| 3 | FinderSync / CLI | ✅ **留 M6**——S18 仅 Services + Open With + URL Scheme |

---

## 实现修订（review 复核后）

实现完成后经评审复核，两处对齐：

| # | 发现 | 定性 | 处理 |
|---|---|---|---|
| F2 | Open Selection 仅 reveal 首项，低于子切片 B 表格写明的「同父目录多选高亮」 | 实现低于本 plan 规格 | `AppRouter.Route.reveal` 改携带 `[URL]`（单项即长度 1）；`WorkspaceModel.reveal(_ fileURLs:)` 导航首项父目录 + 高亮所有同父目录项、跨父目录项忽略；Services Open Selection 传全部选中 URL。 |
| F2b | F2 首轮只改到 model 层，多选未落到 `NSTableView`：`scrollToURL: URL?` 仅选单行，selection delegate 又把 model 写回单选 | 修复未触达 UI 层 | 表格选择信号 `scrollToURL: URL?` → `revealSelection: [URL]?`；`FileTableView` 用 `IndexSet` 一次性 `selectRowIndexes`（全部行）+ `scrollRowToVisible`（首项）；单 URL 调用点（变化列表点击定位）退化为长度 1。 |
| F1 | URL Scheme 未实现 PRD 1214「无权限路径需要用户确认」（本 plan 子切片 A 安全校验段遗漏此验收项，仅覆盖 1213「路径解析安全」） | plan↔PRD 覆盖 gap，范围扩展 | 经 Sir 拍板「仅终端入口确认」：`Route.terminal` 携带 `requireConfirmation`，URL Scheme（外部不可信 deep-link）置 true → 开 shell 前 `NSAlert` 确认；Finder Services「Open Terminal Here」（用户主动）置 false。open/reveal 只读列目录，靠非沙盒 TCC 兜底，不额外确认。 |

> F1 严重性说明：finding 初判 HIGH，复核校准为中等——非沙盒（D1）下系统 TCC 对受保护目录访问自动弹授权已有兜底，PathDeck 外部入口只读导航；最敏感的是 terminal route 在任意目录开 shell，故确认精准作用于该条。统一信任模型（recent/pinned/bookmark 合集对 open/reveal 的信任集外确认）留 S21 Beta 打磨评估。
