import Foundation

/// 把终端外观/行为偏好序列化成 ghostty 配置文件文本，写到受管 runtime.conf。
/// 内置 Monokai Pro Light 固定配色，字体/光标/窗口属性从 `TerminalPreferences` 读取。
///
/// 这是 PathDeck → libghostty 的唯一外观透传通道：vendored `GhosttyKit.xcframework`
/// 不导出逐键 `ghostty_config_set`，只能 `ghostty_config_new` →
/// `ghostty_config_load_file(runtime.conf)` → `ghostty_config_finalize`。
/// `nonisolated`：纯序列化 + 文件 IO，被 nonisolated 的 `GhosttyApp` 调用，与其同源。
nonisolated enum TerminalConfigWriter {
    /// 受管配置文件路径：`NSTemporaryDirectory()/PathDeck/runtime.conf`。
    static var runtimeConfURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PathDeck", isDirectory: true)
            .appendingPathComponent("runtime.conf", isDirectory: false)
    }

    /// 从当前偏好序列化并原子写入 runtime.conf，返回文件 URL。失败时返回路径但文件可能缺失
    /// （`GhosttyApp.reloadConfig` 对 load_file 失败静默降级，旧 config 不变、外观不动、会话不丢）。
    @discardableResult
    static func writeCurrent(_ prefs: TerminalPreferences = .shared) -> URL {
        let url = runtimeConfURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? serialize(prefs).data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // Monokai Pro Light — from iTerm2-Color-Schemes (mbadolato/iTerm2-Color-Schemes)
    private static let themeLines: [String] = [
        "background = #faf4f2",
        "foreground = #29242a",
        "cursor-color = #706b6e",
        "selection-background = #bfb9ba",
        "selection-foreground = #29242a",
        "palette = 0=#faf4f2",
        "palette = 1=#e14775",
        "palette = 2=#269d69",
        "palette = 3=#cc7a0a",
        "palette = 4=#e16032",
        "palette = 5=#7058be",
        "palette = 6=#1c8ca8",
        "palette = 7=#29242a",
        "palette = 8=#a59fa0",
        "palette = 9=#e14775",
        "palette = 10=#269d69",
        "palette = 11=#cc7a0a",
        "palette = 12=#e16032",
        "palette = 13=#7058be",
        "palette = 14=#1c8ca8",
        "palette = 15=#29242a",
    ]

    /// 纯函数：偏好 → ghostty 配置文本（每行 `key = value`）。脱离文件系统可单测。
    static func serialize(_ prefs: TerminalPreferences) -> String {
        var lines: [String] = []
        lines.append(contentsOf: themeLines)
        if !prefs.fontFamily.isEmpty {
            lines.append("font-family = \(prefs.fontFamily)")
        }
        if !prefs.fontStyle.isEmpty {
            lines.append("font-style = \(prefs.fontStyle)")
        }
        lines.append("font-size = \(formatNumber(prefs.fontSize))")
        if !prefs.useLigatures {
            lines.append("font-feature = -calt")
            lines.append("font-feature = -liga")
        }
        if prefs.fontThicken {
            lines.append("font-thicken = true")
        }
        if prefs.useNonASCIIFont && !prefs.nonASCIIFontFamily.isEmpty {
            lines.append("font-codepoint-map = U+0080-U+FFFF=\(prefs.nonASCIIFontFamily)")
        }
        lines.append("cursor-style = \(prefs.cursorStyle)")
        lines.append("window-padding-x = \(prefs.padding)")
        lines.append("window-padding-y = \(prefs.padding)")
        lines.append("background-opacity = \(formatNumber(prefs.opacity))")
        if prefs.blur {
            lines.append("background-blur = 20")
        }
        if prefs.copyOnSelect {
            lines.append("copy-on-select = true")
        }
        lines.append("scrollback-limit = \(scrollbackBytes(lines: prefs.scrollback))")
        return lines.joined(separator: "\n") + "\n"
    }

    /// ghostty `scrollback-limit` 单位是字节（含活动屏）。UI 以「行」表达，按 ~1KB/行估算，
    /// 使 10000 行 ≈ 10MB（对齐 ghostty 默认量级），单调递增。
    static func scrollbackBytes(lines: Int) -> Int {
        max(lines, 1) * 1024
    }

    /// 整数省略小数点：`13.0` → `"13"`，`13.5` → `"13.5"`（ghostty `font-size` 接受非整数）。
    static func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
