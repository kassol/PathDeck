import SwiftUI

struct VerticalTerminalTabBar: View {
    var sessions: [TerminalSession]
    var activeID: UUID?
    var onSelect: (UUID) -> Void
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?
    var onReorder: (UUID, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        VerticalTabItem(
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
                }
            }

            Divider()

            Button(action: onNewTab) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Terminal")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
            .help("New Terminal")
        }
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
    var onDrop: (UUID, Bool) -> Void

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var hoveredEdge: TabDropEdge?
    @State private var measuredHeight: CGFloat = 0

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
        .background(backgroundColor)
        .overlay(alignment: .top) {
            if isDropTargeted, hoveredEdge == .start {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if isDropTargeted, hoveredEdge == .end {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in measuredHeight = new }
            }
        )
        .contentShape(Rectangle())
        .draggable(TerminalSessionDragID(id: session.id))
        .dropDestination(for: TerminalSessionDragID.self) { items, location in
            guard let source = items.first?.id, source != session.id else { return false }
            let height = measuredHeight > 0 ? measuredHeight : 1
            let after = location.y >= height / 2
            onDrop(source, after)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
            if !hovering { hoveredEdge = nil }
        }
        .onTapGesture(count: 2) {
            editingTitle = session.title
            isEditing = true
        }
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .onContinuousHover { phase in
            guard isDropTargeted else { return }
            switch phase {
            case .active(let location):
                let half = (measuredHeight > 0 ? measuredHeight : 1) / 2
                hoveredEdge = location.y < half ? .start : .end
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

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        onRename(trimmed)
        isEditing = false
    }
}
