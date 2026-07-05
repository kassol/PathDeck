import AppKit

/// Command 派发 module（S38，ADR-0002）：keystroke → 命令表决策的唯一路径。
/// `resolve` 是纯决策函数——按键、焦点语境、目标 controller 进，命中命令（含 ⌘1–9
/// 参数）或 nil（放行给系统/菜单）出；执行由全局 monitor adapter
/// （`WorkspaceManager.installCommandMonitor`）完成，仅一行 action 调用。
/// 派发遥测（测试缝）：记录一次按键在真实事件管线中实际执行的路径次数。
/// ⌘T 双开回归（2026-07-05）的管线级测试靠它观测「monitor + 菜单合计恰好执行一次」，
/// keyWindow 在 xcodebuild 会话不可得，无法用窗口数作信号。运行时开销为两次计数写入。
@MainActor
enum CommandDispatchTelemetry {
    static var monitorDispatchCount = 0
    static var menuRunIDs: [String] = []
    static func reset() {
        monitorDispatchCount = 0
        menuRunIDs = []
    }
}

@MainActor
enum CommandDispatch {

    /// keystroke 的归一表示：从 NSEvent 提取，测试可直接构造。
    /// 修饰键只取 ⌘⌃⇧⌥ 四位——方向键等 function key 附带的 .function/.numericPad
    /// 不参与匹配（⌘↑ 的 modifierFlags 含 function 位，精确比对会永远失配）。
    struct KeyStroke {
        /// charactersIgnoringModifiers 首字符，lowercased；死键等无字符事件为 nil。
        let char: Character?
        let keyCode: UInt16
        let modifiers: KeyModifiers

        init(char: Character?, keyCode: UInt16, modifiers: KeyModifiers) {
            self.char = char
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        init(event: NSEvent) {
            let flags = event.modifierFlags
            var mods: KeyModifiers = []
            if flags.contains(.command) { mods.insert(.command) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.control) { mods.insert(.control) }
            self.init(
                char: event.charactersIgnoringModifiers?.lowercased().first,
                keyCode: event.keyCode,
                modifiers: mods
            )
        }
    }

    /// 焦点语境。textEditing（NSText field editor：inline rename / 搜索框 / Palette
    /// 输入框）下所有命令放行——monitor 吞键会劫持正常文本编辑（⌘⌫ 在重命名中是
    /// 删至行首，不是移到废纸篓）。
    enum Focus {
        case terminal
        case file
        case textEditing
    }

    struct Resolution {
        let spec: ShortcutSpec
        /// ⌘1–9 命中时的 1 起序号；非参数化命令为 nil。
        let index: Int?
    }

    /// R1 仲裁：同一 keystroke 的候选按「语境精确 > global > 跨语境」排序，
    /// 首个 isEnabled 的候选胜出；全部不可用 → nil（事件放行，系统/菜单兜底）。
    /// focus == nil（keyWindow 不是 workspace window，如 Settings）时仅
    /// `.allowsFallback` 候选参与，语境不再区分。
    static func resolve(_ stroke: KeyStroke,
                        focus: Focus?,
                        target: WorkspaceController?) -> Resolution? {
        if focus == .textEditing { return nil }

        var candidates: [(rank: Int, resolution: Resolution)] = []
        for spec in ShortcutRegistry.all {
            guard !spec.isReserved, spec.dispatchVia == .monitor,
                  let hit = match(spec.match, stroke) else { continue }
            if let focus {
                candidates.append((contextRank(spec.context, focus: focus),
                                   Resolution(spec: spec, index: hit)))
            } else if spec.targetPolicy == .allowsFallback {
                candidates.append((0, Resolution(spec: spec, index: hit)))
            }
        }
        // 稳定排序：同 rank 保持表内顺序。
        return candidates.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .first { $0.element.resolution.spec.isEnabled(target) }?
            .element.resolution
    }

    /// 双层可选表达「是否命中 + 可选参数」：外层 nil = 未命中；
    /// 内层为 ⌘1–9 序号，非参数化命中为 .some(nil)。
    private static func match(_ match: KeyMatch, _ stroke: KeyStroke) -> Int?? {
        guard match.modifiers == stroke.modifiers else { return .none }
        switch match {
        case .char(let ch, _):
            return stroke.char == ch ? .some(nil) : .none
        case .keyCode(let code, _):
            return stroke.keyCode == code ? .some(nil) : .none
        case .digits(let range, _):
            guard let ch = stroke.char, let n = Int(String(ch)),
                  range.contains(n) else { return .none }
            return .some(n)
        }
    }

    /// 菜单 action 入口守卫（⌘T 双开回归修复，2026-07-05）：local monitor 返回 nil
    /// 只拦截事件向 window/responder 的继续派发，拦不住同一次 sendEvent 内的菜单
    /// key-equivalent 处理（实测：探针显示一次 ⌘T 令 monitor 与菜单各执行一次）。
    /// monitor 型命令的键盘触发菜单执行必然与全局 monitor 重复——monitor 放行的
    /// 键盘场景（textEditing / 全候选禁用 / 非 workspace keyWindow 的 strict）在菜单
    /// 侧也均为 no-op 死路径——一律跳过；鼠标点击菜单（currentEvent 非 keyDown）照常。
    static func menuShouldRun(_ spec: ShortcutSpec, triggeredBy event: NSEvent?) -> Bool {
        !(spec.dispatchVia == .monitor && event?.type == .keyDown)
    }

    /// R1 排序：语境精确命中 0，global 1，跨语境 2。
    private static func contextRank(_ context: ShortcutContext, focus: Focus) -> Int {
        switch (focus, context) {
        case (.terminal, .terminalFocus), (.file, .fileFocus):
            return 0
        case (_, .global):
            return 1
        default:
            return 2
        }
    }
}
