import Foundation

/// 终端主题预设：一组完整配色（背景 / 前景 / 光标 + 16 色 ANSI palette），全部 `#RRGGBB`。
///
/// vendored `GhosttyKit.xcframework` 不含 themes 资源、不能引用主题名（`theme = Dracula` 会失败），
/// 故 PathDeck 在 Swift 端自定义 preset，透传时展开成显式 `background` / `foreground` /
/// `cursor-color` / `palette = N=#hex` 配置键值。详见 `docs/plans/2026-06-25-s33-...md`。
nonisolated struct ThemePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let background: String
    let foreground: String
    let cursor: String
    /// 16 个 `#RRGGBB`，索引 0–15（标准 ANSI）。
    let palette: [String]

    /// 序列化成 ghostty 配置文本行。
    func configLines() -> [String] {
        var lines = [
            "background = \(background)",
            "foreground = \(foreground)",
            "cursor-color = \(cursor)",
        ]
        for (index, color) in palette.enumerated() {
            lines.append("palette = \(index)=\(color)")
        }
        return lines
    }
}

/// 内置主题目录（首发 6 套：4 深 + 2 浅）。色板取自成熟开源配色方案。
nonisolated enum BuiltInThemes {
    static let defaultID = "catppuccin-mocha"

    static let all: [ThemePreset] = [mocha, dracula, nord, solarizedDark, latte, solarizedLight]

    /// 按 id 取 preset，未知 id 回退默认（防持久化了已删除主题导致空白）。
    static func preset(id: String) -> ThemePreset {
        all.first { $0.id == id } ?? mocha
    }

    static let mocha = ThemePreset(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
        background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc",
        palette: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                  "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"])

    static let dracula = ThemePreset(
        id: "dracula", name: "Dracula", isDark: true,
        background: "#282a36", foreground: "#f8f8f2", cursor: "#f8f8f2",
        palette: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                  "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"])

    static let nord = ThemePreset(
        id: "nord", name: "Nord", isDark: true,
        background: "#2e3440", foreground: "#d8dee9", cursor: "#d8dee9",
        palette: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                  "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"])

    static let solarizedDark = ThemePreset(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: "#002b36", foreground: "#839496", cursor: "#93a1a1",
        palette: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                  "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"])

    static let latte = ThemePreset(
        id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false,
        background: "#eff1f5", foreground: "#4c4f69", cursor: "#dc8a78",
        palette: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
                  "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"])

    static let solarizedLight = ThemePreset(
        id: "solarized-light", name: "Solarized Light", isDark: false,
        background: "#fdf6e3", foreground: "#657b83", cursor: "#586e75",
        palette: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                  "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"])
}
