import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsCategory? = .appearance

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.title, systemImage: category.icon).tag(category)
            }
            .navigationSplitViewColumnWidth(176)
        } detail: {
            Group {
                switch selection ?? .appearance {
                case .appearance: AppearanceSettingsTab()
                case .terminal: TerminalSettingsTab()
                }
            }
            .navigationTitle((selection ?? .appearance).title)
        }
        .frame(width: 660, height: 460)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case terminal

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        }
    }

    var icon: String {
        switch self {
        case .appearance: "paintpalette"
        case .terminal: "terminal"
        }
    }
}
