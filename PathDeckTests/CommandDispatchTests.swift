import Testing
import Foundation
import AppKit
@testable import PathDeck

/// S38：CommandDispatch.resolve 决策矩阵（键 × 焦点语境 × enabled → 命令 / 放行）。
/// R1 仲裁与 targetPolicy 语义见 docs/adr/0002。
@MainActor
struct CommandDispatchTests {
    private func makeManager() -> WorkspaceManager {
        let suite = UserDefaults(suiteName: "CommandDispatchTests-\(UUID().uuidString)")!
        return WorkspaceManager(
            preferences: WorkspacePreferences(defaults: suite),
            pinnedFolders: PinnedFolders(userDefaults: suite),
            engine: GhosttyTerminalEngine(),
            router: AppRouter(),
            persistence: WorkspacePersistence(defaults: suite)
        )
    }

    private func stroke(_ char: Character?, keyCode: UInt16 = 0,
                        _ mods: KeyModifiers) -> CommandDispatch.KeyStroke {
        CommandDispatch.KeyStroke(char: char, keyCode: keyCode, modifiers: mods)
    }

    private func resolveID(_ s: CommandDispatch.KeyStroke,
                           focus: CommandDispatch.Focus?,
                           target: WorkspaceController? = nil) -> String? {
        CommandDispatch.resolve(s, focus: focus, target: target)?.spec.id
    }

    // MARK: - 双语义键按语境分流

    @Test
    func commandTSplitsByFocus() {
        #expect(resolveID(stroke("t", [.command]), focus: .file) == "newTab")
        #expect(resolveID(stroke("t", [.command]), focus: .terminal) == "newTerminalTab")
    }

    /// ⌘W 终端焦点：有活动终端关终端；无活动终端 R1 回退到关窗口（复刻现状）。
    @Test
    func commandWFallsBackWhenNoActiveTerminal() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }

        c.viewState.activeTerminalID = UUID()
        #expect(resolveID(stroke("w", [.command]), focus: .terminal, target: c) == "closeTerminal")
        c.viewState.activeTerminalID = nil
        #expect(resolveID(stroke("w", [.command]), focus: .terminal, target: c) == "closeWindow")
        #expect(resolveID(stroke("w", [.command]), focus: .file, target: c) == "closeWindow")
    }

    /// ⌘⇧T 终端焦点：终端栈非空重开终端；终端栈空回退重开窗口（R1 行为变化，
    /// 原 monitor 吞键 no-op）；两栈皆空放行（nil）。
    @Test
    func commandShiftTReopenArbitration() {
        let manager = makeManager()
        let c = manager.openNewWindow(cwd: FileManager.default.temporaryDirectory)
        defer { c.close() }
        let s = stroke("t", [.command, .shift])

        #expect(resolveID(s, focus: .terminal, target: c) == nil)

        manager.closedWindows.push(ClosedWindowRecord(
            state: WorkspaceWindowState(
                cwd: "/tmp", isCustomTitle: false, customTitle: nil,
                mode: WorkspaceMode.finderFirst.rawValue, isTerminalVisible: false,
                anchorCwdPath: nil, terminalStates: [], activeTerminalIndex: nil
            ),
            frame: nil, hostGroup: nil
        ))
        #expect(resolveID(s, focus: .terminal, target: c) == "reopenClosedWindow")
        #expect(resolveID(s, focus: .file, target: c) == "reopenClosedWindow")

        c.closedTerminals.push(ClosedTerminalRecord(
            title: "Terminal", cwd: FileManager.default.temporaryDirectory,
            isManuallyRenamed: false, index: 0
        ))
        #expect(resolveID(s, focus: .terminal, target: c) == "reopenClosedTerminal")
    }

    // MARK: - global 语境与参数化

    @Test
    func globalCommandsResolveInBothFocuses() {
        let s = stroke("p", [.command, .shift])
        #expect(resolveID(s, focus: .file) == "commandPalette")
        #expect(resolveID(s, focus: .terminal) == "commandPalette")
        #expect(resolveID(stroke("\u{F700}", [.command]), focus: .file) == "goToParent")
    }

    @Test
    func digitRangeResolvesWithIndex() {
        let r = CommandDispatch.resolve(stroke("3", [.command]), focus: .file, target: nil)
        #expect(r?.spec.id == "selectTabN")
        #expect(r?.index == 3)
        #expect(resolveID(stroke("0", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("3", [.command, .shift]), focus: .file) == nil)
    }

    @Test
    func keyCodeMatchersResolveTabSwitching() {
        #expect(resolveID(stroke(nil, keyCode: 48, [.control]), focus: .file) == "nextTab")
        #expect(resolveID(stroke(nil, keyCode: 48, [.control, .shift]), focus: .terminal) == "previousTab")
        #expect(resolveID(stroke(nil, keyCode: 50, [.control]), focus: .file) == "toggleTerminal")
        #expect(resolveID(stroke(nil, keyCode: 50, [.control, .shift]), focus: .file) == "newTerminal")
    }

    /// 修饰键精确匹配：⌘B 与 ⌘⇧B 是两条命令。
    @Test
    func modifiersMatchExactly() {
        #expect(resolveID(stroke("b", [.command]), focus: .file) == "toggleSidebar")
        #expect(resolveID(stroke("b", [.command, .shift]), focus: .file) == "togglePreviewPane")
        #expect(resolveID(stroke("b", [.command, .option]), focus: .file) == nil)
    }

    // MARK: - 放行路径

    /// textEditing（重命名 / 搜索框 / Palette 输入）一律放行。
    @Test
    func textEditingPassesEverything() {
        #expect(resolveID(stroke("t", [.command]), focus: .textEditing) == nil)
        #expect(resolveID(stroke("w", [.command]), focus: .textEditing) == nil)
        #expect(resolveID(stroke("\u{7F}", [.command]), focus: .textEditing) == nil)
        #expect(resolveID(stroke("3", [.command]), focus: .textEditing) == nil)
    }

    /// menuOnly（responder-chain）与 viewLocal（裸键 / ⌘↓）不经 monitor 派发。
    @Test
    func menuOnlyAndViewLocalAreExcluded() {
        #expect(resolveID(stroke("c", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("v", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("a", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("d", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("\u{F701}", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("\r", []), focus: .file) == nil)
        #expect(resolveID(stroke(" ", []), focus: .file) == nil)
    }

    @Test
    func unknownKeystrokePasses() {
        #expect(resolveID(stroke("k", [.command]), focus: .file) == nil)
        #expect(resolveID(stroke("t", []), focus: .file) == nil)
    }

    // MARK: - focus == nil（keyWindow 非 workspace window）

    /// 仅 allowsFallback 命令参与；strict 命令放行给菜单。
    @Test
    func nonWorkspaceKeyWindowHonorsTargetPolicy() {
        #expect(resolveID(stroke(".", [.command, .shift]), focus: nil) == "toggleHiddenFiles")
        #expect(resolveID(stroke("t", [.command]), focus: nil) == "newTab")
        #expect(resolveID(stroke("b", [.command]), focus: nil) == nil)
        #expect(resolveID(stroke("w", [.command]), focus: nil) == nil)
    }
}
