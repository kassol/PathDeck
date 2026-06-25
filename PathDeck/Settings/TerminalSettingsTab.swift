import SwiftUI

struct TerminalSettingsTab: View {
    @Bindable private var prefs = TerminalPreferences.shared

    private let shells = ["/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/opt/homebrew/bin/fish"]

    var body: some View {
        Form {
            Section {
                Picker("Default Shell", selection: $prefs.shell) {
                    ForEach(availableShells, id: \.self) { path in
                        Text(shellLabel(path)).tag(path)
                    }
                    Text("Custom…").tag("custom")
                }
                .onChange(of: prefs.shell) { _, newValue in
                    if newValue == "custom" && prefs.customShellPath.isEmpty {
                        prefs.customShellPath = "/bin/zsh"
                    }
                }

                if prefs.shell == "custom" {
                    TextField("Shell Path", text: $prefs.customShellPath)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Shell")
            } footer: {
                Text("Takes effect in new terminals.")
            }

            Section("Behavior") {
                Toggle("Copy on Select", isOn: $prefs.copyOnSelect)
            }

            Section {
                HStack {
                    Text("Lines")
                    Spacer()
                    Text("\(prefs.scrollback)")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { Double(prefs.scrollback) },
                    set: { prefs.scrollback = Int($0) }
                ), in: 1000...50000, step: 1000)
            } header: {
                Text("Scrollback")
            } footer: {
                Text("Takes effect in new terminals.")
            }
        }
        .formStyle(.grouped)
    }

    private var availableShells: [String] {
        shells.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func shellLabel(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
