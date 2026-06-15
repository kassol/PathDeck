import SwiftUI

struct ChangesSettingsTab: View {
    @AppStorage("changesEnabled") private var changesEnabled: Bool = true
    @AppStorage("versionsEnabled") private var versionsEnabled: Bool = true
    @AppStorage("versionMaxSizeKB") private var maxSizeKB: Int = 1024
    @AppStorage("versionMaxCount") private var maxCount: Int = 10
    @State private var showIgnoreRules = false

    var body: some View {
        Form {
            Section("Recent Changes") {
                Toggle("Enable file change tracking", isOn: $changesEnabled)
            }

            Section("Version Snapshots") {
                Toggle("Enable lightweight version snapshots", isOn: $versionsEnabled)

                if versionsEnabled {
                    HStack {
                        Text("Max file size")
                        Spacer()
                        Text(fileSizeLabel)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    Slider(value: Binding(
                        get: { Double(maxSizeKB) },
                        set: { maxSizeKB = Int($0) }
                    ), in: 256...5120, step: 256)

                    Stepper("Versions per file: \(maxCount)", value: $maxCount, in: 5...50)
                }
            }

            Section("Ignore Rules") {
                Button("Manage Ignore Rules…") {
                    showIgnoreRules.toggle()
                }
                .popover(isPresented: $showIgnoreRules) {
                    IgnoreRulesPopover()
                        .frame(width: 300, height: 320)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var fileSizeLabel: String {
        if maxSizeKB >= 1024 {
            return "\(maxSizeKB / 1024) MB"
        }
        return "\(maxSizeKB) KB"
    }
}
