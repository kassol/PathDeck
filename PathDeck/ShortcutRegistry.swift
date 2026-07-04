import AppKit
import QuickLookUI

/// 全部快捷键与命令元数据的唯一真相源（S36 建立，S37 升级为命令表，S38 键位单源化）。
/// 键位（KeyMatch 机器可匹配描述）、标题、分组、焦点语境、派发方式、目标 policy、
/// 预留标记、动作、可用条件集中在此维护；键帽 token、终端拦截集合、快捷键浮窗与
/// Command Palette 内容全部由本表派生。
/// 调整任何快捷键：只改这里；ShortcutRegistryTests / ShortcutCommandTests 守护一致性。

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

/// 键位修饰集。自有类型而非 NSEvent.ModifierFlags：需要 Hashable，且要同时派生
/// 匹配谓词、SwiftUI KeyboardShortcut 与键帽 token 三种表示。
struct KeyModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
}

/// 机器可匹配的键位描述——键位唯一真相源：键帽 token、终端拦截三元组、
/// monitor 匹配谓词、SwiftUI KeyboardShortcut 全部由此派生，杜绝多份键位漂移。
enum KeyMatch: Hashable {
    /// 按 charactersIgnoringModifiers 匹配；Character 一律小写存储（匹配时 lowercased 比较）。
    case char(Character, KeyModifiers)
    /// 按物理 keyCode 匹配（⇥=48、`=50 等 char 表示不稳定/不唯一的键）。
    case keyCode(UInt16, KeyModifiers)
    /// 数字范围（⌘1–9），命中时解析出参数 n。
    case digits(ClosedRange<Int>, KeyModifiers)

    var modifiers: KeyModifiers {
        switch self {
        case .char(_, let m), .keyCode(_, let m), .digits(_, let m):
            return m
        }
    }

    /// 浮窗 / Palette 展示的键帽 token 序列，如 ["⌘", "⇧", "B"]、["Space"]、["⌘", "1–9"]。
    var keycapTokens: [String] {
        var tokens: [String] = []
        if modifiers.contains(.command) { tokens.append("⌘") }
        if modifiers.contains(.control) { tokens.append("⌃") }
        if modifiers.contains(.shift) { tokens.append("⇧") }
        if modifiers.contains(.option) { tokens.append("⌥") }
        tokens.append(keyToken)
        return tokens
    }

    private var keyToken: String {
        switch self {
        case .digits(let range, _):
            return "\(range.lowerBound)–\(range.upperBound)"
        case .keyCode(let code, _):
            switch code {
            case 48: return "⇥"
            case 50: return "`"
            default: return "key\(code)"
            }
        case .char(let ch, _):
            switch ch {
            case "\r": return "↩"
            case " ": return "Space"
            case "\u{7F}": return "⌫"
            case "\u{F700}": return "↑"
            case "\u{F701}": return "↓"
            default: return String(ch).uppercased()
            }
        }
    }
}

/// 命令的 keystroke 派发方式。
enum CommandDispatchVia {
    /// 全局 monitor 派发（CommandDispatch）：AppKit first responder 下 SwiftUI
    /// keyboardShortcut 不可靠，直接动作型命令一律走这里。
    case monitor
    /// 仅菜单派发：responder-chain 型（⌘C/⌘V 等文本编辑不可吞）与系统级条目。
    case menuOnly
    /// 视图内派发：裸键（↩/Space）monitor 匹配必吞正常输入；⌘↓ 因 Quick Look
    /// 面板事件转发直调 outlineView.keyDown 也留在视图。
    case viewLocal
}

/// 命令的目标 Workspace 解析 policy（keyWindow 不是 workspace window 时的行为）。
enum CommandTargetPolicy {
    /// 严格：只作用于 key workspace；Settings 等面板为 key 时 monitor 放行、菜单 no-op。
    case workspaceStrict
    /// 允许兜底：与窗口无关或明确允许 lastActive 兜底的命令（全局偏好 / 全局窗口栈）。
    case allowsFallback
}

/// 终端焦点下需要从 libghostty 手里保留给 app 的 ⌘ 组合。
struct TerminalReservedKey: Hashable {
    let char: Character
    var shift = false
    var option = false
}

struct ShortcutSpec: Identifiable {
    let id: String
    /// 机器可匹配键位（唯一真相源），展示与拦截派生见 `keys` / `reservedInTerminal`。
    let match: KeyMatch
    let title: String
    let group: ShortcutGroup
    let context: ShortcutContext
    /// 预留键位（Reserved Shortcut）：已规划用途、当前不绑定动作，不进菜单与浮窗。
    var isReserved = false
    /// 不在浮窗显示（系统级显而易见项）。
    var showsInOverlay = true
    /// keystroke 派发方式；直接动作型默认走全局 monitor。
    var dispatchVia: CommandDispatchVia = .monitor
    /// 目标 Workspace 解析 policy；默认严格 key workspace。
    var targetPolicy: CommandTargetPolicy = .workspaceStrict
    /// 终端焦点需拦截还给 app（true 时从 match 派生三元组；⌘1–9 一组）。
    var isReservedInTerminal = false
    /// 命令动作（S37）：菜单与 Command Palette 共用的执行入口。入参为目标 workspace
    /// controller；workspace 型命令收到 nil 时 no-op（Settings 为 key 的菜单场景），
    /// responder-chain 型与全局偏好型不依赖它。nil = 无直接动作（system 组）。
    var action: (@MainActor (WorkspaceController?) -> Void)? = nil
    /// 参数化动作（⌘1–9：n 为 1 起的 tab 序号）；与 action 互斥。
    var indexedAction: (@MainActor (WorkspaceController?, Int) -> Void)? = nil
    /// 可用条件（菜单/Palette 置灰依据）；默认恒真。
    var isEnabled: @MainActor (WorkspaceController?) -> Bool = { _ in true }

    /// 键帽 token 序列（浮窗 / Palette 展示），从 match 派生。
    var keys: [String] { match.keycapTokens }

    /// 终端拦截三元组，从 match 派生（仅 ⌘ 系组合有意义）。
    var reservedInTerminal: [TerminalReservedKey] {
        guard isReservedInTerminal, match.modifiers.contains(.command) else { return [] }
        switch match {
        case .char(let ch, let m):
            return [TerminalReservedKey(char: ch,
                                        shift: m.contains(.shift),
                                        option: m.contains(.option))]
        case .digits(let range, _):
            return range.map { TerminalReservedKey(char: Character("\($0)")) }
        case .keyCode:
            return []
        }
    }
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

/// New Terminal / New Terminal Tab 共用：建 session 并确保终端面板可见。
private let createsTerminalSession: @MainActor (WorkspaceController?) -> Void =
    requiresController { c in
        c.createTerminal()
        if !c.viewState.isTerminalVisible { c.viewState.isTerminalVisible = true }
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
        ShortcutSpec(id: "toggleSidebar", match: .char("b", [.command]),
                     title: String(localized: "Toggle Sidebar"),
                     group: .view, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.viewState.isSidebarVisible.toggle() }),
        ShortcutSpec(id: "togglePreviewPane", match: .char("b", [.command, .shift]),
                     title: String(localized: "Toggle Preview Pane"),
                     group: .view, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.viewState.isPreviewPaneVisible.toggle() }),
        ShortcutSpec(id: "toggleTerminal", match: .keyCode(50, [.control]),
                     title: String(localized: "Toggle Terminal"),
                     group: .view, context: .global,
                     action: requiresController { $0.viewState.isTerminalVisible.toggle() }),
        ShortcutSpec(id: "commandPalette", match: .char("p", [.command, .shift]),
                     title: String(localized: "Command Palette…"),
                     group: .view, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.showCommandPalette() }),
        ShortcutSpec(id: "toggleHiddenFiles", match: .char(".", [.command, .shift]),
                     title: String(localized: "Hidden Files"),
                     group: .view, context: .global,
                     targetPolicy: .allowsFallback,
                     isReservedInTerminal: true,
                     // 全局偏好命令，与窗口无关；Settings 为 key（c == nil）时也生效。
                     action: { fallbackManager($0)?.toggleHidden() }),

        // MARK: 文件
        ShortcutSpec(id: "openSelection", match: .char("\u{F701}", [.command]),
                     title: String(localized: "Open"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .viewLocal,
                     action: requiresController { $0.workspace.openSelection() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "renameFile", match: .char("\r", []),
                     title: String(localized: "Rename"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .viewLocal,
                     action: requiresController { c in
                         if let url = c.workspace.selectedURLs.first {
                             c.workspace.pendingRenameURL = url
                         }
                     },
                     isEnabled: hasSingleSelection),
        ShortcutSpec(id: "quickLook", match: .char(" ", []),
                     title: String(localized: "Quick Look"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .viewLocal,
                     action: { _ in ShortcutRegistry.toggleQuickLookPanel() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "goToParent", match: .char("\u{F700}", [.command]),
                     title: String(localized: "Go to Parent"),
                     group: .files, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.goUp() }),
        ShortcutSpec(id: "openFolder", match: .char("o", [.command]),
                     title: String(localized: "Open Folder…"),
                     group: .files, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.openFolder() }),
        ShortcutSpec(id: "newFolder", match: .char("n", [.command, .shift]),
                     title: String(localized: "New Folder"),
                     group: .files, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.newFolder() }),
        ShortcutSpec(id: "moveToTrash", match: .char("\u{7F}", [.command]),
                     title: String(localized: "Move to Trash"),
                     group: .files, context: .fileFocus,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.trashItems() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "duplicate", match: .char("d", [.command]),
                     title: String(localized: "Duplicate"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .menuOnly,
                     isReservedInTerminal: true,
                     action: sendsResponderAction("duplicate:"),
                     isEnabled: hasSelection),
        ShortcutSpec(id: "copy", match: .char("c", [.command]),
                     title: String(localized: "Copy"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .menuOnly,
                     action: sendsResponderAction("copy:"),
                     isEnabled: hasSelection),
        ShortcutSpec(id: "paste", match: .char("v", [.command]),
                     title: String(localized: "Paste"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .menuOnly,
                     action: sendsResponderAction("paste:"),
                     isEnabled: hasFileURLsOnPasteboard),
        ShortcutSpec(id: "moveItemHere", match: .char("v", [.command, .option]),
                     title: String(localized: "Move Item Here"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .menuOnly,
                     action: sendsResponderAction("moveItemHere:"),
                     isEnabled: hasFileURLsOnPasteboard),
        ShortcutSpec(id: "selectAll", match: .char("a", [.command]),
                     title: String(localized: "Select All"),
                     group: .files, context: .fileFocus,
                     dispatchVia: .menuOnly,
                     action: sendsResponderAction("selectAll:")),
        ShortcutSpec(id: "copyCurrentPath", match: .char("c", [.command, .option]),
                     title: String(localized: "Copy Current Path"),
                     group: .files, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.copyCurrentPath() }),
        ShortcutSpec(id: "find", match: .char("f", [.command]),
                     title: String(localized: "Find…"),
                     group: .files, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.workspace.isSearching = true }),

        // MARK: 终端
        ShortcutSpec(id: "newTerminal", match: .keyCode(50, [.control, .shift]),
                     title: String(localized: "New Terminal"),
                     group: .terminal, context: .global,
                     action: createsTerminalSession),
        ShortcutSpec(id: "sendPathToTerminal", match: .char("\r", [.command]),
                     title: String(localized: "Send Path to Terminal"),
                     group: .terminal, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.sendSelectionPathToTerminal() },
                     isEnabled: hasSelection),
        ShortcutSpec(id: "newTerminalTab", match: .char("t", [.command]),
                     title: String(localized: "New Terminal Tab"),
                     group: .terminal, context: .terminalFocus,
                     action: createsTerminalSession),
        ShortcutSpec(id: "closeTerminal", match: .char("w", [.command]),
                     title: String(localized: "Close Terminal"),
                     group: .terminal, context: .terminalFocus,
                     action: requiresController { c in
                         if let id = c.viewState.activeTerminalID { c.closeTerminal(id) }
                     },
                     isEnabled: { $0?.viewState.activeTerminalID != nil }),
        ShortcutSpec(id: "reopenClosedTerminal", match: .char("t", [.command, .shift]),
                     title: String(localized: "Reopen Closed Terminal"),
                     group: .terminal, context: .terminalFocus,
                     action: requiresController { $0.reopenClosedTerminal() },
                     isEnabled: { $0?.closedTerminals.isEmpty == false }),

        // MARK: Tab 与窗口
        ShortcutSpec(id: "newTab", match: .char("t", [.command]),
                     title: String(localized: "New Tab"),
                     group: .tabs, context: .fileFocus,
                     targetPolicy: .allowsFallback,
                     isReservedInTerminal: true,
                     // c == nil（Settings 为 key）时沿用 lastActive 兜底开新 tab（与旧菜单行为一致）。
                     action: { c in
                         guard let manager = fallbackManager(c) else { return }
                         let target = c ?? manager.keyController
                         let cwd = target?.workspace.currentURL
                             ?? FileManager.default.homeDirectoryForCurrentUser
                         manager.openNewWindow(cwd: cwd, tabbedTo: target?.window)
                     }),
        ShortcutSpec(id: "closeWindow", match: .char("w", [.command]),
                     title: String(localized: "Close Window"),
                     group: .tabs, context: .fileFocus,
                     isReservedInTerminal: true,
                     action: requiresController { $0.window?.performClose(nil) }),
        ShortcutSpec(id: "selectTabN", match: .digits(1...9, [.command]),
                     title: String(localized: "Tab 1–9"),
                     group: .tabs, context: .global,
                     isReservedInTerminal: true,
                     indexedAction: { c, n in
                         guard let tabs = c?.window?.tabbedWindows,
                               tabs.indices.contains(n - 1) else { return }
                         tabs[n - 1].makeKeyAndOrderFront(nil)
                     }),
        ShortcutSpec(id: "nextTab", match: .keyCode(48, [.control]),
                     title: String(localized: "Next Tab"),
                     group: .tabs, context: .global,
                     action: requiresController { $0.window?.selectNextTab(nil) }),
        ShortcutSpec(id: "previousTab", match: .keyCode(48, [.control, .shift]),
                     title: String(localized: "Previous Tab"),
                     group: .tabs, context: .global,
                     action: requiresController { $0.window?.selectPreviousTab(nil) }),
        ShortcutSpec(id: "reopenClosedWindow", match: .char("t", [.command, .shift]),
                     title: String(localized: "Reopen Closed Tab"),
                     group: .tabs, context: .fileFocus,
                     targetPolicy: .allowsFallback,
                     isReservedInTerminal: true,
                     // 窗口栈是全局的，与 newTab 同理允许 Settings 为 key 时兜底执行。
                     action: { fallbackManager($0)?.reopenClosedWindow() },
                     isEnabled: { fallbackManager($0)?.closedWindows.isEmpty == false }),
        ShortcutSpec(id: "renameWorkspace", match: .char("r", [.command, .shift]),
                     title: String(localized: "Rename Workspace…"),
                     group: .tabs, context: .global,
                     isReservedInTerminal: true,
                     action: requiresController { $0.promptRenameWorkspace() }),

        // MARK: 系统级（仅终端拦截派生）
        ShortcutSpec(id: "settings", match: .char(",", [.command]),
                     title: "Settings…",
                     group: .system, context: .global,
                     showsInOverlay: false,
                     dispatchVia: .menuOnly,
                     isReservedInTerminal: true),
        ShortcutSpec(id: "quit", match: .char("q", [.command]),
                     title: "Quit",
                     group: .system, context: .global,
                     showsInOverlay: false,
                     dispatchVia: .menuOnly,
                     isReservedInTerminal: true),
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
