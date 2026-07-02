import Foundation
import Observation

/// 全局终端偏好单实例（@Observable）。所有 NSWindow workspace 共享同一份。
/// 与 `WorkspacePreferences`（文件工作区布局）并列，本类专管终端外观/行为。
/// 改值经 `didSet` 持久化；外观项额外 post `.terminalAppearanceDidChange`，
/// 由 `GhosttyTerminalEngine` 重写 runtime.conf + 热重载到所有活动 surface。
/// `nonisolated`：本类被 nonisolated 的 `GhosttyApp`（C runtime 桥）读取，与其同源；
/// 实际访问均在主线程（SwiftUI 设置面板 / 启动 / 主队列热重载），状态读写线程安全。
@Observable
nonisolated final class TerminalPreferences {
    static let shared = TerminalPreferences()

    /// 默认 shell（`"custom"` 表示用 `customShellPath`）。仅影响新建终端，不触发外观热重载。
    var shell: String {
        didSet { defaults.set(shell, forKey: Self.shellKey) }
    }
    var customShellPath: String {
        didSet { defaults.set(customShellPath, forKey: Self.customShellKey) }
    }
    /// 终端字号（pt）。热重载。
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Self.fontSizeKey); postAppearanceChange() }
    }
    /// scrollback 行数（UI 心智）。写 conf 时按 ~1KB/行换算成 ghostty 的字节 `scrollback-limit`。
    /// ghostty 注解：runtime 改动仅新建终端生效。
    var scrollback: Int {
        didSet { defaults.set(scrollback, forKey: Self.scrollbackKey); postAppearanceChange() }
    }
    /// 终端字体族（空 = 系统默认等宽）。ghostty 注解：仅新建终端生效（font-size 才能热重载）。
    var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Self.fontFamilyKey); postAppearanceChange() }
    }
    /// 字体样式（"Regular"/"Bold"/"Light" 等，空 = 字体默认面）。仅新建终端生效。
    var fontStyle: String {
        didSet { defaults.set(fontStyle, forKey: Self.fontStyleKey); postAppearanceChange() }
    }
    /// 连字（calt/liga）。false 时输出 `font-feature = -calt` + `-liga`。仅新建终端生效。
    var useLigatures: Bool {
        didSet { defaults.set(useLigatures, forKey: Self.useLigaturesKey); postAppearanceChange() }
    }
    /// 字体加粗渲染（ghostty `font-thicken`，UI 标注 Anti-aliased）。仅新建终端生效。
    var fontThicken: Bool {
        didSet { defaults.set(fontThicken, forKey: Self.fontThickenKey); postAppearanceChange() }
    }
    /// 是否为非 ASCII 文本使用独立字体（ghostty `font-codepoint-map`）。仅新建终端生效。
    var useNonASCIIFont: Bool {
        didSet { defaults.set(useNonASCIIFont, forKey: Self.useNonASCIIFontKey); postAppearanceChange() }
    }
    /// 非 ASCII 字体族（空 = 系统默认）。仅新建终端生效。
    var nonASCIIFontFamily: String {
        didSet { defaults.set(nonASCIIFontFamily, forKey: Self.nonASCIIFontFamilyKey); postAppearanceChange() }
    }
    /// 光标样式（`bar` / `block` / `underline`）。热重载。
    var cursorStyle: String {
        didSet { defaults.set(cursorStyle, forKey: Self.cursorStyleKey); postAppearanceChange() }
    }
    /// 窗口内边距（pt，x=y 统一）。ghostty 注解：仅新建终端生效。
    var padding: Int {
        didSet { defaults.set(padding, forKey: Self.paddingKey); postAppearanceChange() }
    }
    /// 背景不透明度（0.5–1.0）。ghostty 注解：macOS 改动需完整重启 Ghostty；本实现至少新建终端生效。
    var opacity: Double {
        didSet { defaults.set(opacity, forKey: Self.opacityKey); postAppearanceChange() }
    }
    /// 背景模糊（半透明时观感更佳）。仅新建终端生效。
    var blur: Bool {
        didSet { defaults.set(blur, forKey: Self.blurKey); postAppearanceChange() }
    }
    /// 选中即复制。热重载。
    var copyOnSelect: Bool {
        didSet { defaults.set(copyOnSelect, forKey: Self.copyOnSelectKey); postAppearanceChange() }
    }

    private let defaults: UserDefaults

    private static let shellKey = "terminalShell"
    private static let customShellKey = "terminalCustomShellPath"
    private static let fontSizeKey = "terminalFontSize"
    private static let scrollbackKey = "terminalScrollback"
    private static let fontFamilyKey = "terminalFontFamily"
    private static let fontStyleKey = "terminalFontStyle"
    private static let useLigaturesKey = "terminalUseLigatures"
    private static let fontThickenKey = "terminalFontThicken"
    private static let useNonASCIIFontKey = "terminalUseNonASCIIFont"
    private static let nonASCIIFontFamilyKey = "terminalNonASCIIFontFamily"
    private static let cursorStyleKey = "terminalCursorStyle"
    private static let paddingKey = "terminalPadding"
    private static let opacityKey = "terminalOpacity"
    private static let blurKey = "terminalBlur"
    private static let copyOnSelectKey = "terminalCopyOnSelect"

    static let defaultFontSize: Double = 13
    static let defaultScrollback: Int = 10000
    static let defaultCursorStyle = "bar"
    static let defaultPadding = 8
    static let defaultOpacity: Double = 1.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shell = defaults.string(forKey: Self.shellKey) ?? Self.defaultShell
        customShellPath = defaults.string(forKey: Self.customShellKey) ?? ""
        let storedFont = defaults.double(forKey: Self.fontSizeKey)
        fontSize = storedFont > 0 ? storedFont : Self.defaultFontSize
        let storedScroll = defaults.integer(forKey: Self.scrollbackKey)
        scrollback = storedScroll > 0 ? storedScroll : Self.defaultScrollback
        fontFamily = defaults.string(forKey: Self.fontFamilyKey) ?? ""
        fontStyle = defaults.string(forKey: Self.fontStyleKey) ?? ""
        useLigatures = defaults.object(forKey: Self.useLigaturesKey) != nil
            ? defaults.bool(forKey: Self.useLigaturesKey) : true
        fontThicken = defaults.object(forKey: Self.fontThickenKey) != nil
            ? defaults.bool(forKey: Self.fontThickenKey) : true
        useNonASCIIFont = defaults.bool(forKey: Self.useNonASCIIFontKey)
        nonASCIIFontFamily = defaults.string(forKey: Self.nonASCIIFontFamilyKey) ?? ""
        cursorStyle = defaults.string(forKey: Self.cursorStyleKey) ?? Self.defaultCursorStyle
        padding = defaults.object(forKey: Self.paddingKey) != nil
            ? defaults.integer(forKey: Self.paddingKey) : Self.defaultPadding
        opacity = defaults.object(forKey: Self.opacityKey) != nil
            ? defaults.double(forKey: Self.opacityKey) : Self.defaultOpacity
        blur = defaults.bool(forKey: Self.blurKey)
        copyOnSelect = defaults.bool(forKey: Self.copyOnSelectKey)
    }

    /// 系统默认 shell（`$SHELL`，回退 `/bin/zsh`）。
    static var defaultShell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    /// 解析出实际可执行 shell 路径（`"custom"` → `customShellPath`，空则回退默认）。
    var resolvedShell: String {
        if shell == "custom" {
            return customShellPath.isEmpty ? Self.defaultShell : customShellPath
        }
        return shell
    }

    private func postAppearanceChange() {
        NotificationCenter.default.post(name: .terminalAppearanceDidChange, object: nil)
    }
}
