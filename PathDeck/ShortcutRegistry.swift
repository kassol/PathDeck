import AppKit
import QuickLookUI

/// 全部快捷键与命令元数据的唯一真相源（S36 建立，S37 升级为命令表）。
/// 键位、标题、分组、焦点语境、预留标记、动作、可用条件集中在此维护；
/// 菜单（PathDeckApp.swift）与 monitor（WorkspaceController）的键位绑定手写但必须与本表一致，
/// 菜单动作统一引用本表 action；GhosttySurfaceView 的终端拦截集合与快捷键浮窗内容完全由本表派生。
/// 调整任何快捷键：先改这里，再改对应菜单/monitor 绑定处；
/// ShortcutRegistryTests / ShortcutCommandTests 守护一致性。

enum ShortcutGroup: CaseIterable {
    case view
    case files
    case terminal
    case tabs
    /// 系统级显而易见项（⌘Q/⌘,），仅用于终端拦截派生，不进浮窗布局。
    case system

    var title: String {
        switch self {
        case .view: return String(localized: "View")
        case .files: return String(localized: "Files")
        case .terminal: return String(localized: "Terminal")
        case .tabs: return String(localized: "Tabs & Window")
        case .system: return ""
        }
    }
}

/// 快捷键生效的焦点语境。同一物理键可在不同语境绑不同动作（⌘T/⌘W）。
enum ShortcutContext: Hashable {
    case global
    case fileFocus
    case terminalFocus

    /// 浮窗上双语义键的语境标注；global 不标注。
    var badge: String? {
        switch self {
        case .global: return nil
        case .fileFocus: return String(localized: "file focus")
        case .terminalFocus: return String(localized: "terminal focus")
        }
    }
}

/// 终端焦点下需要从 libghostty 手里保留给 app 的 ⌘ 组合。
struct TerminalReservedKey: Hashable {
    let char: Character
    var shift = false
    var option = false
}

struct ShortcutSpec: Identifiable {
    let id: String
    /// 键帽 token 序列，如 ["⌘", "⇧", "B"]、["Space"]、["⌘", "1–9"]。
    let keys: [String]
    let title: String
    let group: ShortcutGroup
    let context: ShortcutContext
    /// 预留键位（Reserved Shortcut）：已规划用途、当前不绑定动作，不进菜单与浮窗。
    var isReserved = false
    /// 不在浮窗显示（系统级显而易见项）。
    var showsInOverlay = true
    /// 终端焦点需拦截还给 app 的 ⌘ 组合（多数键一条；⌘1–9 一组）。
    var reservedInTerminal: [TerminalReservedKey] = []
    /// 命令动作（S37）：菜单与 Command Palette 共用的执行入口。入参为目标 workspace
    /// controller；workspace 型命令收到 nil 时 no-op（Settings 为 key 的菜单场景），
    /// responder-chain 型与全局偏好型不依赖它。nil = 无直接动作（system 组、参数化 ⌘1–9）。
    var action: (@MainActor (WorkspaceController?) -> Void)? = nil
    /// 可用条件（菜单/Palette 置灰依据）；默认恒真。
    var isEnabled: @MainActor (WorkspaceController?) -> Bool = { _ in true }
}

// MARK: - Action helpers

/// workspace 型命令：要求非空 controller，nil 时 no-op。
private func requiresController(
    _ body: @escaping @MainActor (WorkspaceController) -> Void
) -> @MainActor (WorkspaceController?) -> Void {
    { c in if let c { body(c) } }
}

/// responder-chain 型命令：派发给 first responder（文件列表 / Settings 文本框等）。
private func sendsResponderAction(_ selectorName: String) -> @MainActor (WorkspaceController?) -> Void {
    { _ in NSApp.sendAction(Selector((selectorName)), to: nil, from: nil) }
}

private func fallbackManager(_ c: WorkspaceController?) -> WorkspaceManager? {
    c?.manager ?? (NSApp.delegate as? AppDelegate)?.workspaceManager
}

private let hasSelection: @MainActor (WorkspaceController?) -> Bool = {
    $0?.workspace.selectedURLs.isEmpty == false
}

private let hasSingleSelection: @MainActor (WorkspaceController?) -> Bool = {
    $0?.workspace.selectedURLs.count == 1
}

private let hasFileURLsOnPasteboard: @MainActor (WorkspaceController?) -> Bool = { _ in
    let urls = NSPasteboard.general.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]
    return urls?.isEmpty == false
}

enum ShortcutRegistry {
    static let all: [ShortcutSpec] = [
        // MARK: 视图
        ShortcutSpec(id: "toggleSidebar", keys: ["⌘", "B"],
                     title: String(localized: "Toggle Sidebar"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: "b")],
                     action: requiresController { $0.viewState.isSidebarVisible.toggle() }),
        ShortcutSpec(id: "togglePreviewPane", keys: ["⌘", "⇧", "B"],
                     title: String(localized: "Toggle Preview Pane"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: "b", shift: true)],
                     action: requiresController { $0.viewState.isPreviewPaneVisible.toggle() }),
        ShortcutSpec(id: "toggleTerminal", keys: ["⌃", "`"],
                     title: String(localized: "Toggle Terminal"),
                     group: .view, context: .global,
                     action: requiresController { $0.viewState.isTerminalVisible.toggle() }),
        ShortcutSpec(id: "commandPalette", keys: ["⌘", "⇧", "P"],
                     title: String(localized: "Command Palette…"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: "p", shift: true)],
                     action: requiresController { $0.showCommandPalette() }),
        ShortcutSpec(id: "toggleHiddenFiles", keys: ["⌘", "⇧", "."],
                     title: String(localized: "Hidden Files"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: ".", shift: true)],
                     // 全局偏好命令，与窗口无关；Settings 为 key（c == nil）时也生效。
                     action: { fallbackManager($0)?.toggleHidden() }),

        // MARK: 文件
        ShortcutSpec(id: "openSelection", keys: ["⌘", "↓"],
                     title: String(localized: "Open"),
                     group: .files, context: .fileFocus,
                     action: requiresController { $0.workspace.openSelection() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "renameFile", keys: ["↩"],
                     title: String(localized: "Rename"),
                     group: .files, context: .fileFocus,
                     action: requiresController { c in
                         if let url = c.workspace.selectedURLs.first {
                             c.workspace.pendingRenameURL = url
                         }
                     },
                     isEnabled: hasSingleSelection),
        ShortcutSpec(id: "quickLook", keys: ["Space"],
                     title: String(localized: "Quick Look"),
                     group: .files, context: .fileFocus,
                     action: { _ in ShortcutRegistry.toggleQuickLookPanel() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "goToParent", keys: ["⌘", "↑"],
                     title: String(localized: "Go to Parent"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "\u{F700}")],
                     action: requiresController { $0.workspace.goUp() }),
        ShortcutSpec(id: "openFolder", keys: ["⌘", "O"],
                     title: String(localized: "Open Folder…"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "o")],
                     action: requiresController { $0.workspace.openFolder() }),
        ShortcutSpec(id: "newFolder", keys: ["⌘", "⇧", "N"],
                     title: String(localized: "New Folder"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "n", shift: true)],
                     action: requiresController { $0.workspace.newFolder() }),
        ShortcutSpec(id: "moveToTrash", keys: ["⌘", "⌫"],
                     title: String(localized: "Move to Trash"),
                     group: .files, context: .fileFocus,
                     reservedInTerminal: [.init(char: "\u{7F}")],
                     action: requiresController { $0.workspace.trashItems() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "duplicate", keys: ["⌘", "D"],
                     title: String(localized: "Duplicate"),
                     group: .files, context: .fileFocus,
                     reservedInTerminal: [.init(char: "d")],
                     action: sendsResponderAction("duplicate:"),
                     isEnabled: hasSelection),
        ShortcutSpec(id: "copy", keys: ["⌘", "C"],
                     title: String(localized: "Copy"),
                     group: .files, context: .fileFocus,
                     action: sendsResponderAction("copy:"),
                     isEnabled: hasSelection),
        ShortcutSpec(id: "paste", keys: ["⌘", "V"],
                     title: String(localized: "Paste"),
                     group: .files, context: .fileFocus,
                     action: sendsResponderAction("paste:"),
                     isEnabled: hasFileURLsOnPasteboard),
        ShortcutSpec(id: "moveItemHere", keys: ["⌘", "⌥", "V"],
                     title: String(localized: "Move Item Here"),
                     group: .files, context: .fileFocus,
                     action: sendsResponderAction("moveItemHere:"),
                     isEnabled: hasFileURLsOnPasteboard),
        ShortcutSpec(id: "selectAll", keys: ["⌘", "A"],
                     title: String(localized: "Select All"),
                     group: .files, context: .fileFocus,
                     action: sendsResponderAction("selectAll:")),
        ShortcutSpec(id: "copyCurrentPath", keys: ["⌘", "⌥", "C"],
                     title: String(localized: "Copy Current Path"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "c", option: true)],
                     action: requiresController { $0.workspace.copyCurrentPath() }),
        ShortcutSpec(id: "find", keys: ["⌘", "F"],
                     title: String(localized: "Find…"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "f")],
                     action: requiresController { $0.workspace.isSearching = true }),

        // MARK: 终端
        ShortcutSpec(id: "newTerminal", keys: ["⌃", "⇧", "`"],
                     title: String(localized: "New Terminal"),
                     group: .terminal, context: .global,
                     action: requiresController { c in
                         c.createTerminal()
                         if !c.viewState.isTerminalVisible { c.viewState.isTerminalVisible = true }
                     }),
        ShortcutSpec(id: "sendPathToTerminal", keys: ["⌘", "↩"],
                     title: String(localized: "Send Path to Terminal"),
                     group: .terminal, context: .global,
                     reservedInTerminal: [.init(char: "\r")],
                     action: requiresController { $0.sendSelectionPathToTerminal() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "newTerminalTab", keys: ["⌘", "T"],
                     title: String(localized: "New Terminal Tab"),
                     group: .terminal, context: .terminalFocus,
                     action: requiresController { c in
                         c.createTerminal()
                         if !c.viewState.isTerminalVisible { c.viewState.isTerminalVisible = true }
                     }),
        ShortcutSpec(id: "closeTerminal", keys: ["⌘", "W"],
                     title: String(localized: "Close Terminal"),
                     group: .terminal, context: .terminalFocus,
                     action: requiresController { c in
                         if let id = c.viewState.activeTerminalID { c.closeTerminal(id) }
                     },
                     isEnabled: { $0?.viewState.activeTerminalID != nil }),
        ShortcutSpec(id: "reopenClosedTerminal", keys: ["⌘", "⇧", "T"],
                     title: String(localized: "Reopen Closed Terminal"),
                     group: .terminal, context: .terminalFocus,
                     action: requiresController { $0.reopenClosedTerminal() },
                     isEnabled: { $0?.closedTerminals.isEmpty == false }),

        // MARK: Tab 与窗口
        ShortcutSpec(id: "newTab", keys: ["⌘", "T"],
                     title: String(localized: "New Tab"),
                     group: .tabs, context: .fileFocus,
                     reservedInTerminal: [.init(char: "t")],
                     // c == nil（Settings 为 key）时沿用 lastActive 兜底开新 tab（与旧菜单行为一致）。
                     action: { c in
                         guard let manager = fallbackManager(c) else { return }
                         let target = c ?? manager.keyController
                         let cwd = target?.workspace.currentURL
                             ?? FileManager.default.homeDirectoryForCurrentUser
                         manager.openNewWindow(cwd: cwd, tabbedTo: target?.window)
                     }),
        ShortcutSpec(id: "closeWindow", keys: ["⌘", "W"],
                     title: String(localized: "Close Window"),
                     group: .tabs, context: .fileFocus,
                     reservedInTerminal: [.init(char: "w")],
                     action: requiresController { $0.window?.performClose(nil) }),
        ShortcutSpec(id: "selectTabN", keys: ["⌘", "1–9"],
                     title: String(localized: "Tab 1–9"),
                     group: .tabs, context: .global,
                     reservedInTerminal: (1...9).map { .init(char: Character("\($0)")) }),
        ShortcutSpec(id: "nextTab", keys: ["⌃", "⇥"],
                     title: String(localized: "Next Tab"),
                     group: .tabs, context: .global,
                     action: requiresController { $0.window?.selectNextTab(nil) }),
        ShortcutSpec(id: "previousTab", keys: ["⌃", "⇧", "⇥"],
                     title: String(localized: "Previous Tab"),
                     group: .tabs, context: .global,
                     action: requiresController { $0.window?.selectPreviousTab(nil) }),
        ShortcutSpec(id: "reopenClosedWindow", keys: ["⌘", "⇧", "T"],
                     title: String(localized: "Reopen Closed Tab"),
                     group: .tabs, context: .fileFocus,
                     reservedInTerminal: [.init(char: "t", shift: true)],
                     action: requiresController { $0.manager?.reopenClosedWindow() },
                     isEnabled: { $0?.manager?.closedWindows.isEmpty == false }),
        ShortcutSpec(id: "renameWorkspace", keys: ["⌘", "⇧", "R"],
                     title: String(localized: "Rename Workspace…"),
                     group: .tabs, context: .global,
                     reservedInTerminal: [.init(char: "r", shift: true)],
                     action: requiresController { $0.promptRenameWorkspace() }),

        // MARK: 系统级（仅终端拦截派生）
        ShortcutSpec(id: "settings", keys: ["⌘", ","],
                     title: "Settings…",
                     group: .system, context: .global,
                     showsInOverlay: false,
                     reservedInTerminal: [.init(char: ",")]),
        ShortcutSpec(id: "quit", keys: ["⌘", "Q"],
                     title: "Quit",
                     group: .system, context: .global,
                     showsInOverlay: false,
                     reservedInTerminal: [.init(char: "q")]),
    ]

    /// 按 id 查找条目（菜单动作绑定入口）。
    static func spec(_ id: String) -> ShortcutSpec? {
        all.first { $0.id == id }
    }

    /// 浮窗展示的条目（预留位与系统级不显示）。
    static var overlaySpecs: [ShortcutSpec] {
        all.filter { $0.showsInOverlay && !$0.isReserved }
    }

    /// Command Palette 展示的命令（有 action 的非预留、非系统条目），按浮窗分组序排列。
    static var paletteSpecs: [ShortcutSpec] {
        let eligible = all.filter { $0.action != nil && !$0.isReserved && $0.group != .system }
        return overlayColumns.flatMap { $0 }.flatMap { group in
            eligible.filter { $0.group == group }
        }
    }

    /// 浮窗三列布局：每列一到多个分组。
    static let overlayColumns: [[ShortcutGroup]] = [[.files], [.view, .terminal], [.tabs]]

    /// 终端焦点下 GhosttySurfaceView 需保留给 app 的 ⌘ 组合全集。
    static let terminalReservedKeys: Set<TerminalReservedKey> =
        Set(all.flatMap(\.reservedInTerminal))

    /// Quick Look 面板显隐（文件列表 Space 键与 quickLook 命令共用）。
    static func toggleQuickLookPanel() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
        }
    }
}
