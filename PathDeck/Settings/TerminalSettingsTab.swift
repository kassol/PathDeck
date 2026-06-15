import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage("terminalShell") private var shell: String = TerminalDefaults.defaultShell
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @AppStorage("terminalScrollback") private var scrollback: Int = 10000
    @State private var customShellPath: String = ""

    private let shells = ["/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/opt/homebrew/bin/fish"]

    var body: some View {
        Form {
            Section("Shell") {
                Picker("Default Shell", selection: $shell) {
                    ForEach(availableShells, id: \.self) { path in
                        Text(shellLabel(path)).tag(path)
                    }
                    Text("Custom…").tag("custom")
                }
                .onChange(of: shell) { _, newValue in
                    if newValue == "custom" && customShellPath.isEmpty {
                        customShellPath = "/bin/zsh"
                    }
                }

                if shell == "custom" {
                    TextField("Shell Path", text: $customShellPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customShellPath) { _, path in
                            if !path.isEmpty {
                                UserDefaults.standard.set(path, forKey: "terminalCustomShellPath")
                            }
                        }
                }
            }

            Section("Appearance") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    TextField("", value: $fontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: $fontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }
            }

            Section("Scrollback") {
                HStack {
                    Text("Lines")
                    Spacer()
                    Text("\(scrollback)")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { Double(scrollback) },
                    set: { scrollback = Int($0) }
                ), in: 1000...50000, step: 1000)
            }

            Section {
                Text("Changes apply to new terminal tabs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            customShellPath = UserDefaults.standard.string(forKey: "terminalCustomShellPath") ?? ""
        }
    }

    private var availableShells: [String] {
        shells.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func shellLabel(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum TerminalDefaults {
    static var defaultShell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    static var resolvedShell: String {
        let stored = UserDefaults.standard.string(forKey: "terminalShell") ?? defaultShell
        if stored == "custom" {
            return UserDefaults.standard.string(forKey: "terminalCustomShellPath") ?? defaultShell
        }
        return stored
    }

    static var fontSize: Double {
        let val = UserDefaults.standard.double(forKey: "terminalFontSize")
        return val > 0 ? val : 13
    }

    static var scrollback: Int {
        let val = UserDefaults.standard.integer(forKey: "terminalScrollback")
        return val > 0 ? val : 10000
    }
}
