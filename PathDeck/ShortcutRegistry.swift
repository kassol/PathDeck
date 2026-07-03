import Foundation

/// 全部快捷键元数据的唯一真相源（S36）。
/// 键位、标题、分组、焦点语境、预留标记集中在此维护；菜单（PathDeckApp.swift）与
/// monitor（WorkspaceController）的动作手写但键位必须与本表一致；
/// GhosttySurfaceView 的终端拦截集合与快捷键浮窗内容完全由本表派生。
/// 调整任何快捷键：先改这里，再改对应菜单/monitor 绑定处；ShortcutRegistryTests 守护一致性。

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
}

enum ShortcutRegistry {
    static let all: [ShortcutSpec] = [
        // MARK: 视图
        ShortcutSpec(id: "toggleSidebar", keys: ["⌘", "B"],
                     title: String(localized: "Toggle Sidebar"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: "b")]),
        ShortcutSpec(id: "togglePreviewPane", keys: ["⌘", "⇧", "B"],
                     title: String(localized: "Toggle Preview Pane"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: "b", shift: true)]),
        ShortcutSpec(id: "toggleTerminal", keys: ["⌃", "`"],
                     title: String(localized: "Toggle Terminal"),
                     group: .view, context: .global),
        ShortcutSpec(id: "toggleHiddenFiles", keys: ["⌘", "⇧", "."],
                     title: String(localized: "Hidden Files"),
                     group: .view, context: .global,
                     reservedInTerminal: [.init(char: ".", shift: true)]),

        // MARK: 文件
        ShortcutSpec(id: "openSelection", keys: ["⌘", "↓"],
                     title: String(localized: "Open"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "renameFile", keys: ["↩"],
                     title: String(localized: "Rename"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "quickLook", keys: ["Space"],
                     title: String(localized: "Quick Look"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "goToParent", keys: ["⌘", "↑"],
                     title: String(localized: "Go to Parent"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "\u{F700}")]),
        ShortcutSpec(id: "openFolder", keys: ["⌘", "O"],
                     title: String(localized: "Open Folder…"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "o")]),
        ShortcutSpec(id: "newFolder", keys: ["⌘", "⇧", "N"],
                     title: String(localized: "New Folder"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "n", shift: true)]),
        ShortcutSpec(id: "moveToTrash", keys: ["⌘", "⌫"],
                     title: String(localized: "Move to Trash"),
                     group: .files, context: .fileFocus,
                     reservedInTerminal: [.init(char: "\u{7F}")]),
        ShortcutSpec(id: "duplicate", keys: ["⌘", "D"],
                     title: String(localized: "Duplicate"),
                     group: .files, context: .fileFocus,
                     reservedInTerminal: [.init(char: "d")]),
        ShortcutSpec(id: "copy", keys: ["⌘", "C"],
                     title: String(localized: "Copy"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "paste", keys: ["⌘", "V"],
                     title: String(localized: "Paste"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "moveItemHere", keys: ["⌘", "⌥", "V"],
                     title: String(localized: "Move Item Here"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "selectAll", keys: ["⌘", "A"],
                     title: String(localized: "Select All"),
                     group: .files, context: .fileFocus),
        ShortcutSpec(id: "copyCurrentPath", keys: ["⌘", "⌥", "C"],
                     title: String(localized: "Copy Current Path"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "c", option: true)]),
        ShortcutSpec(id: "find", keys: ["⌘", "F"],
                     title: String(localized: "Find…"),
                     group: .files, context: .global,
                     reservedInTerminal: [.init(char: "f")]),

        // MARK: 终端
        ShortcutSpec(id: "newTerminal", keys: ["⌃", "⇧", "`"],
                     title: String(localized: "New Terminal"),
                     group: .terminal, context: .global),
        ShortcutSpec(id: "sendPathToTerminal", keys: ["⌘", "↩"],
                     title: String(localized: "Send Path to Terminal"),
                     group: .terminal, context: .global,
                     reservedInTerminal: [.init(char: "\r")]),
        ShortcutSpec(id: "newTerminalTab", keys: ["⌘", "T"],
                     title: String(localized: "New Terminal Tab"),
                     group: .terminal, context: .terminalFocus),
        ShortcutSpec(id: "closeTerminal", keys: ["⌘", "W"],
                     title: String(localized: "Close Terminal"),
                     group: .terminal, context: .terminalFocus),

        // MARK: Tab 与窗口
        ShortcutSpec(id: "newTab", keys: ["⌘", "T"],
                     title: String(localized: "New Tab"),
                     group: .tabs, context: .fileFocus,
                     reservedInTerminal: [.init(char: "t")]),
        ShortcutSpec(id: "closeWindow", keys: ["⌘", "W"],
                     title: String(localized: "Close Window"),
                     group: .tabs, context: .fileFocus,
                     reservedInTerminal: [.init(char: "w")]),
        ShortcutSpec(id: "selectTabN", keys: ["⌘", "1–9"],
                     title: String(localized: "Tab 1–9"),
                     group: .tabs, context: .global,
                     reservedInTerminal: (1...9).map { .init(char: Character("\($0)")) }),
        ShortcutSpec(id: "nextTab", keys: ["⌃", "⇥"],
                     title: String(localized: "Next Tab"),
                     group: .tabs, context: .global),
        ShortcutSpec(id: "previousTab", keys: ["⌃", "⇧", "⇥"],
                     title: String(localized: "Previous Tab"),
                     group: .tabs, context: .global),
        ShortcutSpec(id: "renameWorkspace", keys: ["⌘", "⇧", "R"],
                     title: String(localized: "Rename Workspace…"),
                     group: .tabs, context: .global,
                     reservedInTerminal: [.init(char: "r", shift: true)]),

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

        // MARK: 预留键位（Reserved Shortcut）
        ShortcutSpec(id: "reservedCommandPalette", keys: ["⌘", "⇧", "P"],
                     title: "Command Palette",
                     group: .system, context: .global,
                     isReserved: true, showsInOverlay: false),
        ShortcutSpec(id: "reservedReopenClosedTab", keys: ["⌘", "⇧", "T"],
                     title: "Reopen Closed Tab",
                     group: .system, context: .global,
                     isReserved: true, showsInOverlay: false),
    ]

    /// 浮窗展示的条目（预留位与系统级不显示）。
    static var overlaySpecs: [ShortcutSpec] {
        all.filter { $0.showsInOverlay && !$0.isReserved }
    }

    /// 浮窗三列布局：每列一到多个分组。
    static let overlayColumns: [[ShortcutGroup]] = [[.files], [.view, .terminal], [.tabs]]

    /// 终端焦点下 GhosttySurfaceView 需保留给 app 的 ⌘ 组合全集。
    static let terminalReservedKeys: Set<TerminalReservedKey> =
        Set(all.flatMap(\.reservedInTerminal))
}
