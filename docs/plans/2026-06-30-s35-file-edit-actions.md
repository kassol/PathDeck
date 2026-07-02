# S35 File Edit Actions — 文件列表标准编辑快捷键

> 日期：2026-06-30
> 前置：S34 已合入
> 触发：⌘C / ⌘V / ⌘A 等标准 Edit 快捷键在文件列表无响应

## 一句话

让 `FileNSOutlineView` 作为 Cocoa first responder 完整支持标准 Edit 语义（Copy / Paste / Move / Duplicate / Select All），通过实现标准 action selector 使 Edit 菜单、快捷键、右键菜单自动联动。

## 根因

`FileNSOutlineView` 没有实现 `copy:` / `paste:` 等 Cocoa 标准 action selector。macOS Edit 菜单通过 responder chain 找实现者——找不到则灰色禁用，快捷键静默失效。终端（Ghostty keybinding）和文本框（NSTextField field editor）不受影响。

## Action 完整集

| Selector | 快捷键 | 行为 | 现状 |
|----------|--------|------|------|
| `copy:` | ⌘C | 选中文件 URL → NSPasteboard（.fileURL + .string） | **需实现** |
| `paste:` | ⌘V | pasteboard file URLs → copyItem 到当前目录 | **需实现** |
| move action | ⌘⌥V | pasteboard file URLs → moveItem 到当前目录 | **需实现** |
| `duplicate:` | ⌘D | 选中文件就地复制 | **需实现** |
| `selectAll:` | ⌘A | 全选可见行 | NSOutlineView 内置，**验证** |
| `delete:` | ⌘⌫ | Move to Trash | **已有**（FileCommands） |

## 不做

- ⌘X 剪切文件（macOS 标准是 ⌘C + ⌘⌥V 移动，Finder 也不支持 ⌘X 剪切文件）
- ⌘Z 撤销文件操作（需 NSUndoManager 集成，复杂度高，独立 story）
- 终端侧改动（⌘C/⌘V 已通过 Ghostty keybinding 工作）

## 技术决策

| # | 决策 | 理由 |
|---|------|------|
| D1 | 标准 Cocoa selector 而非 NSEvent monitor / performKeyEquivalent | selector 是 Cocoa 通用机制——一次实现，Edit 菜单项启用/禁用、快捷键、右键菜单、Services 全部自动联动。monitor 方案需逐个注册快捷键且绕过菜单系统 |
| D2 | 文件操作方法加在 `WorkspaceModel`（与 `trashItems()` / `newFolder()` 同级） | 保持现有模式：View 层 thin wrapper → Coordinator callback → WorkspaceModel 执行文件系统操作 + `reload()` |
| D3 | ⌘⌥V 通过 `CommandGroup(replacing: .pasteboard)` 手动构建 Edit 菜单 pasteboard section，用 NSMenuItem `.isAlternate` 实现 | Finder 的 ⌘⌥V 是 Paste 菜单项的 alternate 变体——按住 Option 时 "Paste" 变为 "Move Item Here"。SwiftUI Commands 不支持 alternate，必须降到 NSMenuItem |
| D4 | NSPasteboard 双类型写入：`.fileURL`（跨 app 文件操作）+ `.string`（路径文本） | ⌘C 后既能在 Finder/文件对话框粘贴文件，也能在终端/编辑器粘贴路径文本 |
| D5 | 重名策略：追加 " copy" / " copy 2" / " copy 3"... | 对齐 Finder 行为。`WorkspaceModel.newFolderName` 已有类似递增逻辑可复用 |

## 数据流

```
FileNSOutlineView                 Coordinator              WorkspaceModel
  copy:   → coord.copyFiles()     → selectedURLs → NSPasteboard
  paste:  → coord.onPaste(.copy)  → callback      → pasteFiles(urls, .copy)  → FileManager.copyItem → reload()
  move    → coord.onPaste(.move)  → callback      → pasteFiles(urls, .move)  → FileManager.moveItem → reload()
  duplicate: → coord.onDuplicate  → callback      → duplicateItems()         → FileManager.copyItem → reload()
  validateUserInterfaceItem       → 统一启用/禁用
```

## 实现步骤

### Step 1: WorkspaceModel 文件操作方法

`PathDeck/FileWorkspace/WorkspaceModel.swift`：

```swift
enum PasteOperation {
    case copy, move
}

func pasteFiles(_ sourceURLs: [URL], operation: PasteOperation) {
    let fm = FileManager.default
    var newURLs: [URL] = []
    for source in sourceURLs {
        let dest = uniqueDestination(for: source.lastPathComponent, in: currentURL)
        do {
            switch operation {
            case .copy: try fm.copyItem(at: source, to: dest)
            case .move: try fm.moveItem(at: source, to: dest)
            }
            newURLs.append(dest)
        } catch {
            NSSound.beep()
        }
    }
    reload()
    if !newURLs.isEmpty { selectedURLs = newURLs; revealSelection = newURLs }
}

func duplicateItems() {
    pasteFiles(selectedURLs, operation: .copy)
}

/// "file copy.txt", "file copy 2.txt" 递增命名，对齐 Finder。
private func uniqueDestination(for name: String, in directory: URL) -> URL {
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    let suffix = ext.isEmpty ? "" : ".\(ext)"

    let candidate = directory.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
        return candidate
    }

    let copyBase = "\(base) copy"
    let first = directory.appendingPathComponent("\(copyBase)\(suffix)")
    if !FileManager.default.fileExists(atPath: first.path(percentEncoded: false)) {
        return first
    }

    var n = 2
    while true {
        let url = directory.appendingPathComponent("\(copyBase) \(n)\(suffix)")
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return url
        }
        n += 1
    }
}
```

### Step 2: FileTableView 回调 + FileNSOutlineView selector

`PathDeck/FileWorkspace/FileTableView.swift`：

**FileTableView struct 新增回调**：
```swift
var onPasteFiles: ([URL], PasteOperation) -> Void
var onDuplicate: () -> Void
```

**FileNSOutlineView 新增 selector**：
```swift
@objc func copy(_ sender: Any?) {
    guard let urls = coordinator?.selectedURLs(), !urls.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects(urls.map { $0 as NSURL })
    pb.setString(urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
}

@objc func paste(_ sender: Any?) {
    guard let urls = readFileURLsFromPasteboard(), !urls.isEmpty else { return }
    coordinator?.onPaste(urls, .copy)
}

@objc func moveItemHere(_ sender: Any?) {
    guard let urls = readFileURLsFromPasteboard(), !urls.isEmpty else { return }
    coordinator?.onPaste(urls, .move)
}

@objc func duplicate(_ sender: Any?) {
    coordinator?.onDuplicate()
}

override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(copy(_:)), #selector(duplicate(_:)):
        return selectedRowIndexes.count > 0
    case #selector(paste(_:)), #selector(moveItemHere(_:)):
        return readFileURLsFromPasteboard() != nil
    default:
        return super.validateUserInterfaceItem(item)
    }
}

private func readFileURLsFromPasteboard() -> [URL]? {
    let urls = NSPasteboard.general.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]
    return urls?.isEmpty == false ? urls : nil
}
```

**Coordinator 转发**：
```swift
var onPaste: ([URL], PasteOperation) -> Void = { _, _ in }
var onDuplicate: () -> Void = {}
```

`makeNSView` 中绑定：
```swift
context.coordinator.onPaste = { [self] urls, op in onPasteFiles(urls, op) }
context.coordinator.onDuplicate = { [self] in onDuplicate() }
```

### Step 3: Edit 菜单 pasteboard section

`PathDeck/PathDeckApp.swift` — `ViewCommands` 中的 `CommandGroup(after: .pasteboard)` 改为 `CommandGroup(replacing: .pasteboard)`：

```swift
CommandGroup(replacing: .pasteboard) {
    // Copy — 标准 ⌘C，action 走 responder chain 到 FileNSOutlineView.copy:
    // SwiftUI Button 的 action 不走 responder chain，需要手动 sendAction
    Button("Copy") {
        NSApp.sendAction(#selector(NSResponder.copy(_:)), to: nil, from: nil)
    }
    .keyboardShortcut("c")

    // Paste — 标准 ⌘V
    Button("Paste") {
        NSApp.sendAction(#selector(NSResponder.paste(_:)), to: nil, from: nil)
    }
    .keyboardShortcut("v")

    // Move Item Here — ⌘⌥V（Finder 行为）
    // SwiftUI 不支持 NSMenuItem.isAlternate，用独立菜单项 + ⌘⌥V
    Button("Move Item Here") {
        NSApp.sendAction(#selector(FileTableView.FileNSOutlineView.moveItemHere(_:)),
                         to: nil, from: nil)
    }
    .keyboardShortcut("v", modifiers: [.command, .option])

    Divider()

    // Duplicate — ⌘D
    Button("Duplicate") {
        NSApp.sendAction(Selector(("duplicate:")), to: nil, from: nil)
    }
    .keyboardShortcut("d")

    Divider()

    // Select All — ⌘A，NSOutlineView 内置
    Button("Select All") {
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
    }
    .keyboardShortcut("a")

    Divider()

    Button("Copy Current Path") {
        keyWorkspaceController()?.workspace.copyCurrentPath()
    }
    .keyboardShortcut("c", modifiers: [.command, .option])
}
```

> **注意**：`replacing: .pasteboard` 会移除 SwiftUI 自动生成的 Cut/Copy/Paste/Select All。上面手动重建了需要的子集。Cut 不加（文件不用 ⌘X）。

### Step 4: GhosttySurfaceView reserved shortcuts 更新

`PathDeck/Terminal/GhosttySurfaceView.swift` — `appReservedShortcuts` 新增 ⌘D（Duplicate），避免终端拦截：

```swift
// 现有：["t", "w", "o", "f", "q", ","]
// 新增 "d"
for c: Character in ["t", "w", "o", "f", "q", ",", "d"] {
    s.insert(.init(char: c, shift: false, option: false))
}
```

> ⌘C / ⌘V 不加入 reserved——终端焦点时它们应走 Ghostty keybinding（copy/paste 终端文本）。只有文件列表焦点时才走 Edit 菜单 → responder chain。

### Step 5: WorkspaceRootView 传递回调

`FileTableView` 调用处新增两个回调参数绑定到 `WorkspaceModel`：

```swift
FileTableView(
    // ... 现有参数 ...
    onPasteFiles: { urls, op in controller.workspace.pasteFiles(urls, operation: op) },
    onDuplicate: { controller.workspace.duplicateItems() }
)
```

### Step 6: 右键菜单补齐

`FileTableView.Coordinator.menuNeedsUpdate` 中追加 Duplicate 和 Paste 菜单项：

```swift
// 在 "Copy Path" 之后
addMenuItem(to: menu, title: String(localized: "Duplicate"),
            action: #selector(menuDuplicate(_:)))

// 在空白区右键菜单（clickedRow < 0）中追加
let canPaste = FileNSOutlineView.readFileURLsFromPasteboard() != nil
let pasteItem = addMenuItem(to: menu, title: String(localized: "Paste"),
                            action: #selector(menuPaste(_:)))
pasteItem.isEnabled = canPaste
```

对应 `@objc` 方法：
```swift
@objc private func menuDuplicate(_ sender: Any?) { onDuplicate() }
@objc private func menuPaste(_ sender: Any?) {
    guard let urls = outlineView?.readFileURLsFromPasteboard() else { return }
    onPaste(urls, .copy)
}
```

`readFileURLsFromPasteboard` 提升为 `static` 或 `internal` 供 Coordinator 调用。

### Step 7: 单元测试

`PathDeckTests/FileEditActionTests.swift`（新文件）：

- `uniqueDestination` 命名递增逻辑（临时目录：无冲突 / 同名存在 / 多次递增）
- `pasteFiles(.copy)` 文件确实复制到目标目录
- `pasteFiles(.move)` 源文件消失、目标出现
- `duplicateItems()` 就地复制 + 名称带 " copy"
- NSPasteboard 双类型写入验证（`.fileURL` + `.string`）

### Step 8: 验证

- **自动**：单测覆盖文件操作逻辑 + NSPasteboard 写入
- **手动走查**（程序测不到的 Edit 菜单联动）：
  1. 文件列表选中文件 → ⌘C → 终端 ⌘V 粘贴路径 ✓
  2. 文件列表选中文件 → ⌘C → Finder ⌘V 粘贴文件 ✓
  3. Finder 选中文件 → ⌘C → PathDeck ⌘V 粘贴到当前目录 ✓
  4. ⌘⌥V 移动文件（源消失、目标出现）✓
  5. ⌘D 就地复制 ✓
  6. ⌘A 全选 ✓
  7. 无选中时 Edit > Copy 灰色禁用 ✓
  8. pasteboard 无文件时 Edit > Paste 灰色禁用 ✓
  9. 终端焦点时 ⌘C/⌘V 仍正常工作（Ghostty 处理）✓

### Step 9: AGENTS.md 更新

`PathDeck/FileWorkspace/AGENTS.md` 变更日志追加 S35 记录。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `FileWorkspace/WorkspaceModel.swift` | +`PasteOperation` +`pasteFiles` +`duplicateItems` +`uniqueDestination` |
| `FileWorkspace/FileTableView.swift` | +2 回调 +`FileNSOutlineView` 5 个 selector + validate + pasteboard 读取 + 右键菜单项 |
| `PathDeckApp.swift` | `CommandGroup(replacing: .pasteboard)` 重建 Edit 菜单 |
| `Terminal/GhosttySurfaceView.swift` | `appReservedShortcuts` +`"d"` |
| `Workspace/WorkspaceRootView.swift` | 传递 `onPasteFiles` / `onDuplicate` 回调 |
| `PathDeckTests/FileEditActionTests.swift` | 新增 |
| `FileWorkspace/AGENTS.md` | 变更日志 |
| `Localizable.xcstrings` | Duplicate / Move Item Here / Paste 中文 |

## 最脆弱假设

`CommandGroup(replacing: .pasteboard)` 中的 SwiftUI `Button` action 使用 `NSApp.sendAction(selector, to: nil, from: nil)` 路由到 responder chain。如果 SwiftUI 拦截了这些标准 selector 不让透传到 AppKit 响应链，需要改为在 `AppDelegate` 中用 NSMenu API 直接构建 Edit 菜单。运行时验证即可——构建后第一步检查 Edit 菜单项是否正确启用/禁用。
