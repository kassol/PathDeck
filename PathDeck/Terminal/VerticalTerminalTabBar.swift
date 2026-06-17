import SwiftUI

struct VerticalTerminalTabBar: View {
    var sessions: [TerminalSession]
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        VerticalTabItem(
                            session: session,
                            isActive: session.id == activeID,
                            onSelect: { onSelect(session.id) },
                            onClose: { onCloseTab(session.id) },
                            onRename: { onRename(session.id, $0) },
                            onNavigateToCwd: onNavigateToCwd
                        )
                    }
                }
            }

            Divider()

            Button(action: onNewTab) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("终端")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
            .help("新建终端")
        }
        .frame(width: 140)
        .background(.bar)
    }
}

private struct VerticalTabItem: View {
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
        HStack(spacing: 0) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
            } else {
                Color.clear.frame(width: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $editingTitle, onCommit: commitRename)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onExitCommand { isEditing = false }
                } else {
                    Text(session.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }

                Text(session.currentCwd.lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .onTapGesture { onNavigateToCwd?(session.currentCwd) }
                    .help(session.currentCwd.path(percentEncoded: false))
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
            .padding(.trailing, 6)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .frame(height: 36)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingTitle = session.title
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
