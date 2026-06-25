import SwiftUI

/// 内置主题缩略图画廊：每张卡渲染该主题的迷你终端样张 + 16 色 ANSI 色条，
/// 点击即套用（经 `TerminalPreferences.activeThemeID` 热重载到所有活动终端）。
struct ThemeGalleryView: View {
    @Bindable var prefs: TerminalPreferences

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(BuiltInThemes.all) { theme in
                ThemeCard(theme: theme, isSelected: theme.id == prefs.activeThemeID)
                    .onTapGesture { prefs.activeThemeID = theme.id }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: ThemePreset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }
            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
                Image(systemName: theme.isDark ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }

    private var fg: Color { Color(hex: theme.foreground) ?? .white }
    private func ansi(_ i: Int) -> Color { Color(hex: theme.palette[i]) ?? fg }

    private var preview: some View {
        ZStack {
            Color(hex: theme.background) ?? .black
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#ff5f57")!).frame(width: 6, height: 6)
                    Circle().fill(Color(hex: "#febc2e")!).frame(width: 6, height: 6)
                    Circle().fill(Color(hex: "#28c840")!).frame(width: 6, height: 6)
                }
                Group {
                    HStack(spacing: 0) {
                        Text(verbatim: "~ ").foregroundStyle(ansi(4))
                        Text(verbatim: "$ ").foregroundStyle(ansi(2))
                        Text(verbatim: "ls -la").foregroundStyle(fg)
                    }
                    HStack(spacing: 0) {
                        Text(verbatim: "src  ").foregroundStyle(ansi(4))
                        Text(verbatim: "README").foregroundStyle(ansi(2))
                        Text(verbatim: ".md").foregroundStyle(fg)
                    }
                    HStack(spacing: 0) {
                        Text(verbatim: "$ ").foregroundStyle(ansi(2))
                        Text(verbatim: "git ").foregroundStyle(fg)
                        Text(verbatim: "status").foregroundStyle(ansi(3))
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 1) {
                    ForEach(0..<16, id: \.self) { i in
                        Rectangle().fill(ansi(i)).frame(height: 5)
                    }
                }
            }
            .padding(8)
        }
    }
}

extension Color {
    /// 从 `"#RRGGBB"` 解析 sRGB；失败返回 nil。
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}
