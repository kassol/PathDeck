import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TerminalSettingsTab()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }

            ChangesSettingsTab()
                .tabItem {
                    Label("Changes", systemImage: "clock.arrow.circlepath")
                }
        }
        .frame(width: 420, height: 320)
    }
}
