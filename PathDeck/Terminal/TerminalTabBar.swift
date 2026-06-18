import SwiftUI

struct TerminalTabBar: View {
    var sessions: [TerminalSession]
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?
    var onReorder: (UUID, Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                TabItem(
                    session: session,
                    isActive: session.id == activeID,
                    onSelect: { onSelect(session.id) },
                    onClose: { onCloseTab(session.id) },
                    onRename: { onRename(session.id, $0) },
                    onNavigateToCwd: onNavigateToCwd,
                    onDrop: { sourceID, after in
                        let target = after ? index + 1 : index
                        onReorder(sourceID, target)
                    }
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
    var onDrop: (UUID, Bool) -> Void

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var hoveredEdge: TabDropEdge?
    @State private var measuredWidth: CGFloat = 0

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
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .leading) {
            if isDropTargeted, hoveredEdge == .start {
                Rectangle().fill(Color.accentColor).frame(width: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if isDropTargeted, hoveredEdge == .end {
                Rectangle().fill(Color.accentColor).frame(width: 2)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in measuredWidth = new }
            }
        )
        .contentShape(Rectangle())
        .draggable(TerminalSessionDragID(id: session.id))
        .dropDestination(for: TerminalSessionDragID.self) { items, location in
            guard let source = items.first?.id, source != session.id else { return false }
            let width = measuredWidth > 0 ? measuredWidth : 1
            let after = location.x >= width / 2
            onDrop(source, after)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
            if !hovering { hoveredEdge = nil }
        }
        .onTapGesture(count: 2) { startRename() }
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .onContinuousHover { phase in
            guard isDropTargeted else { return }
            switch phase {
            case .active(let location):
                let half = (measuredWidth > 0 ? measuredWidth : 1) / 2
                hoveredEdge = location.x < half ? .start : .end
            case .ended:
                hoveredEdge = nil
            }
        }
    }

    private var backgroundColor: Color {
        if isDropTargeted, hoveredEdge == nil { return Color.accentColor.opacity(0.18) }
        if isActive { return Color.accentColor.opacity(0.1) }
        return Color.clear
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

