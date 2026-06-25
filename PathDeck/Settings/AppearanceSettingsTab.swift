import SwiftUI
import AppKit

struct AppearanceSettingsTab: View {
    @Bindable private var prefs = TerminalPreferences.shared

    var body: some View {
        Form {
            Section("Theme") {
                ThemeGalleryView(prefs: prefs)
                    .padding(.vertical, 4)
            }

            Section {
                Picker("Font", selection: $prefs.fontFamily) {
                    Text("System Default").tag("")
                    ForEach(availableFonts, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                HStack {
                    Text("Preview")
                    Spacer()
                    Text(verbatim: "AaBb 0O1lI")
                        .font(fontPreview)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Font Size")
                    Spacer()
                    // clamp 在 binding set 端，挡住 TextField 直接键入的越界值（Stepper 的 in: 仅约束按钮）。
                    TextField("", value: clampedFontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: clampedFontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }
                Picker("Cursor", selection: $prefs.cursorStyle) {
                    Text("Bar").tag("bar")
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                }
            } header: {
                Text("Text & Font")
            } footer: {
                // 主题/字号/光标即时生效；font-family ghostty 限新建终端（库文档：only affect new windows/tabs）。
                Text("Font family takes effect in new terminals.")
            }

            Section {
                sliderRow(title: "Padding",
                          value: Binding(get: { Double(prefs.padding) },
                                         set: { prefs.padding = Int($0) }),
                          range: 0...24, step: 1, readout: "\(prefs.padding)")
                sliderRow(title: "Opacity",
                          value: $prefs.opacity,
                          range: 0.5...1.0, step: 0.05,
                          readout: "\(Int((prefs.opacity * 100).rounded()))%")
                Toggle("Background Blur", isOn: $prefs.blur)
            } header: {
                Text("Size & Opacity")
            } footer: {
                // padding 限新建终端；macOS 上 background-opacity 改动 ghostty 文档标注需完整重启。
                Text("Takes effect in new terminals.")
            }
        }
        .formStyle(.grouped)
    }

    private var clampedFontSize: Binding<Double> {
        Binding(get: { prefs.fontSize }, set: { prefs.fontSize = min(max($0, 8), 32) })
    }

    private var fontPreview: Font {
        prefs.fontFamily.isEmpty
            ? .system(size: 13, design: .monospaced)
            : .custom(prefs.fontFamily, size: 13)
    }

    /// 在常见等宽字体里筛出本机已安装的，避免列举全部字体（傻瓜化）。空 tag = 系统默认。
    private var availableFonts: [String] {
        let curated = ["SF Mono", "Menlo", "Monaco", "Courier New",
                       "Fira Code", "JetBrains Mono", "Hack", "Cascadia Code", "IBM Plex Mono"]
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return curated.filter { installed.contains($0) }
    }

    @ViewBuilder
    private func sliderRow(title: LocalizedStringKey, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double, readout: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text(readout)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
