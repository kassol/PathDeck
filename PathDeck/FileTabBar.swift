import SwiftUI

struct FileTabBar: View {
    var tabs: [FileTab]
    var activeTabID: UUID?
    var tabModels: [UUID: WorkspaceModel]
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onNewTab: () -> Void
    var onRename: (UUID, String) -> Void
    var onReorder: (UUID, Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    FileTabItem(
                        tab: tab,
                        displayName: tab.isCustomTitle
                            ? tab.title
                            : (tabModels[tab.id]?.currentURL.lastPathComponent ?? tab.title),
                        isActive: tab.id == activeTabID,
                        canClose: tabs.count > 1,
                        onSelect: { onSelect(tab.id) },
                        onClose: { onClose(tab.id) },
                        onRename: { onRename(tab.id, $0) },
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
    var onDrop: (UUID, Bool) -> Void

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var hoveredEdge: TabDropEdge?
    @State private var measuredWidth: CGFloat = 0

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
        .draggable(FileTabDragID(id: tab.id))
        .dropDestination(for: FileTabDragID.self) { items, location in
            guard let source = items.first?.id, source != tab.id else { return false }
            let width = measuredWidth > 0 ? measuredWidth : 1
            let after = location.x >= width / 2
            onDrop(source, after)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
            if !hovering { hoveredEdge = nil }
        }
        .onTapGesture(count: 2) {
            editingTitle = displayName
            isEditing = true
        }
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

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditing = false
    }
}

