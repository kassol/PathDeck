import SwiftUI

struct FileTabBar: View {
    var tabs: [FileTab]
    var activeTabID: UUID?
    var tabModels: [UUID: WorkspaceModel]
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onNewTab: () -> Void
    var onRename: (UUID, String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    FileTabItem(
                        tab: tab,
                        displayName: tab.isCustomTitle
                            ? tab.title
                            : (tabModels[tab.id]?.currentURL.lastPathComponent ?? tab.title),
                        isActive: tab.id == activeTabID,
                        canClose: tabs.count > 1,
                        onSelect: { onSelect(tab.id) },
                        onClose: { onClose(tab.id) },
                        onRename: { onRename(tab.id, $0) }
                    )
                }

                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("New Tab")
            }
        }
        .frame(height: 28)
        .background(.bar)
    }
}

private struct FileTabItem: View {
    let tab: FileTab
    let displayName: String
    let isActive: Bool
    let canClose: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if tab.terminalAnchorCwd != nil {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if isEditing {
                TextField("", text: $editingTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)
                    .onExitCommand { isEditing = false }
            } else {
                Text(displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .opacity(isHovering || isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingTitle = displayName
            isEditing = true
        }
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditing = false
    }
}
