import SwiftUI
import AppKit

struct AppearanceSettingsTab: View {
    @Bindable private var prefs = TerminalPreferences.shared
    @State private var fontDelegate = FontPanelDelegate()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Font")
                    Spacer()
                    Text(fontDescription)
                        .foregroundStyle(.secondary)
                    Button("Select…") { fontDelegate.showPanel(for: .main) }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: clampedFontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: clampedFontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text("Preview")
                    Spacer()
                    Text(verbatim: "AaBb 0O1lI")
                        .font(fontPreview)
                        .foregroundStyle(.secondary)
                }

                Toggle("Use Ligatures", isOn: $prefs.useLigatures)
                Toggle("Anti-aliased", isOn: $prefs.fontThicken)
            } header: {
                Text("Font")
            }

            Section {
                Toggle("Use a different font for non-ASCII text", isOn: $prefs.useNonASCIIFont)
                if prefs.useNonASCIIFont {
                    HStack {
                        Text("Font")
                        Spacer()
                        Text(nonASCIIFontDescription)
                            .foregroundStyle(.secondary)
                        Button("Select…") { fontDelegate.showPanel(for: .nonASCII) }
                    }
                }
            } header: {
                Text("Non-ASCII Font")
            }

            Section {
                Picker("Cursor", selection: $prefs.cursorStyle) {
                    Text("Bar").tag("bar")
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                }
            } header: {
                Text("Cursor")
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
                Text("Window")
            } footer: {
                Text("Font and window settings take effect in new terminals.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Font Display

    private var fontDescription: String {
        if prefs.fontFamily.isEmpty { return "System Default" }
        if prefs.fontStyle.isEmpty { return prefs.fontFamily }
        return "\(prefs.fontFamily) — \(prefs.fontStyle)"
    }

    private var nonASCIIFontDescription: String {
        prefs.nonASCIIFontFamily.isEmpty ? "System Default" : prefs.nonASCIIFontFamily
    }

    private var clampedFontSize: Binding<Double> {
        Binding(get: { prefs.fontSize }, set: { prefs.fontSize = min(max($0, 8), 32) })
    }

    private var fontPreview: Font {
        if prefs.fontFamily.isEmpty {
            return .system(size: 13, design: .monospaced)
        }
        var attrs: [NSFontDescriptor.AttributeName: Any] = [.family: prefs.fontFamily]
        if !prefs.fontStyle.isEmpty {
            attrs[.face] = prefs.fontStyle
        }
        if let nsFont = NSFont(descriptor: NSFontDescriptor(fontAttributes: attrs), size: 13) {
            return Font(nsFont)
        }
        return .custom(prefs.fontFamily, size: 13)
    }

    // MARK: - Helpers

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

// MARK: - NSFontPanel Bridge

private class FontPanelDelegate: NSObject {
    enum Target { case main, nonASCII }
    var activeTarget: Target = .main

    func showPanel(for target: Target) {
        activeTarget = target
        let font = resolveFont(for: target)
        NSFontManager.shared.setSelectedFont(font, isMultiple: false)
        NSFontManager.shared.target = self
        NSFontManager.shared.action = #selector(changeFont(_:))
        NSFontPanel.shared.orderFront(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let oldFont = resolveFont(for: activeTarget)
        let newFont = manager.convert(oldFont)
        let prefs = TerminalPreferences.shared

        switch activeTarget {
        case .main:
            prefs.fontFamily = newFont.familyName ?? ""
            prefs.fontStyle = (newFont.fontDescriptor.object(forKey: .face) as? String) ?? ""
            prefs.fontSize = min(max(Double(newFont.pointSize), 8), 32)
        case .nonASCII:
            prefs.nonASCIIFontFamily = newFont.familyName ?? ""
        }
    }

    private func resolveFont(for target: Target) -> NSFont {
        let prefs = TerminalPreferences.shared
        switch target {
        case .main:
            if prefs.fontFamily.isEmpty {
                return NSFont.monospacedSystemFont(ofSize: CGFloat(prefs.fontSize), weight: .regular)
            }
            var attrs: [NSFontDescriptor.AttributeName: Any] = [.family: prefs.fontFamily]
            if !prefs.fontStyle.isEmpty { attrs[.face] = prefs.fontStyle }
            return NSFont(descriptor: NSFontDescriptor(fontAttributes: attrs), size: CGFloat(prefs.fontSize))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(prefs.fontSize), weight: .regular)
        case .nonASCII:
            if prefs.nonASCIIFontFamily.isEmpty {
                return NSFont.systemFont(ofSize: CGFloat(prefs.fontSize))
            }
            return NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: prefs.nonASCIIFontFamily]),
                         size: CGFloat(prefs.fontSize))
                ?? NSFont.systemFont(ofSize: CGFloat(prefs.fontSize))
        }
    }
}
