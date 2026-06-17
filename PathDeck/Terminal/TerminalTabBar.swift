import SwiftUI

struct TerminalTabBar: View {
    var sessions: [TerminalSession]
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sessions) { session in
                TabItem(
                    session: session,
                    isActive: session.id == activeID,
                    onSelect: { onSelect(session.id) },
                    onClose: { onCloseTab(session.id) },
                    onRename: { onRename(session.id, $0) },
                    onNavigateToCwd: onNavigateToCwd
                )
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Terminal")

            Spacer()
        }
        .frame(height: 28)
        .background(.bar)
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let session: TerminalSession
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("", text: $editingTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)
                    .onExitCommand { cancelRename() }
            } else {
                Text(session.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if isActive {
                    Text(session.currentCwd.lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .onTapGesture { onNavigateToCwd?(session.currentCwd) }
                        .help(session.currentCwd.path(percentEncoded: false))
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
            .opacity(isHovering || isActive ? 1 : 0)
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
        .onTapGesture(count: 2) { startRename() }
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    private func startRename() {
        editingTitle = session.title
        isEditing = true
    }

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        onRename(trimmed)
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }
}
