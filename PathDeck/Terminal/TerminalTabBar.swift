import SwiftUI

struct TerminalTabBar: View {
    @Binding var sessions: [TerminalSession]
    @Binding var activeID: UUID?
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onNavigateToCwd: ((URL) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach($sessions) { $session in
                TabItem(
                    session: $session,
                    isActive: session.id == activeID,
                    onSelect: { activeID = session.id },
                    onClose: { onCloseTab(session.id) },
                    onNavigateToCwd: onNavigateToCwd
                )
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("新建终端")

            Spacer()
        }
        .frame(height: 28)
        .background(.bar)
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    @Binding var session: TerminalSession
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
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
        if !trimmed.isEmpty {
            session.title = trimmed
        }
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }
}
