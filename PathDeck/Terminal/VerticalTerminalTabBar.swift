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

    @State private var hoveredDropIndex: Int?

    private var ownedIDs: Set<UUID> { Set(sessions.map(\.id)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TerminalTabStyle.gap) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        VerticalTabItem(
                            session: session,
                            isActive: session.id == activeID,
                            isShiftedUp: shouldShiftUp(at: index),
                            isShiftedDown: shouldShiftDown(at: index),
                            ownedIDs: ownedIDs,
                            onSelect: { onSelect(session.id) },
                            onClose: { onCloseTab(session.id) },
                            onRename: { onRename(session.id, $0) },
                            onNavigateToCwd: onNavigateToCwd,
                            onDrop: { sourceID, after in
                                let target = after ? index + 1 : index
                                withAnimation(TerminalTabStyle.dropSpring) {
                                    onReorder(sourceID, target)
                                }
                                hoveredDropIndex = nil
                            },
                            onHoverEdge: { edge in
                                guard let edge else { hoveredDropIndex = nil; return }
                                hoveredDropIndex = edge == .start ? index : index + 1
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
                .animation(TerminalTabStyle.shiftSpring, value: hoveredDropIndex)
            }

            Divider()

            Button(action: onNewTab) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Terminal")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Terminal")
        }
        .background(.bar)
    }

    private func shouldShiftUp(at index: Int) -> Bool {
        guard let drop = hoveredDropIndex else { return false }
        return index >= drop && index > 0
    }

    private func shouldShiftDown(at index: Int) -> Bool {
        guard let drop = hoveredDropIndex else { return false }
        return index < drop
    }
}

private struct VerticalTabItem: View {
    let session: TerminalSession
    let isActive: Bool
    var isShiftedUp: Bool
    var isShiftedDown: Bool
    /// 当前 workspace window 拥有的 session ID 集合；drop 时拒绝跨 window 拖入。
    var ownedIDs: Set<UUID>
    var onSelect: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void
    var onNavigateToCwd: ((URL) -> Void)?
    var onDrop: (UUID, Bool) -> Void
    var onHoverEdge: (TabDropEdge?) -> Void

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var hoveredEdge: TabDropEdge?
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $editingTitle, onCommit: commitRename)
                        .textFieldStyle(.plain)
                        .font(TerminalTabStyle.titleFont)
                        .onExitCommand { isEditing = false }
                } else {
                    Text(session.title)
                        .font(TerminalTabStyle.titleFont)
                        .lineLimit(1)
                }
                Text(session.currentCwd.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .onTapGesture { onNavigateToCwd?(session.currentCwd) }
                    .help(session.currentCwd.path(percentEncoded: false))
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
            .padding(.trailing, 8)
            .opacity((isHovering || isActive) ? 1 : 0)
        }
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: TerminalTabStyle.cornerRadius, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(alignment: .top) {
            if isDropTargeted, hoveredEdge == .start {
                RoundedRectangle(cornerRadius: 1).fill(TerminalTabStyle.dropLineColor).frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if isDropTargeted, hoveredEdge == .end {
                RoundedRectangle(cornerRadius: 1).fill(TerminalTabStyle.dropLineColor).frame(height: 2)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in measuredHeight = new }
            }
        )
        .padding(.horizontal, 4)
        .offset(y: isShiftedUp ? -TerminalTabStyle.shiftDistance : (isShiftedDown ? TerminalTabStyle.shiftDistance : 0))
        .contentShape(Rectangle())
        .draggable(TerminalSessionDragID(id: session.id)) {
            TerminalTabDragPreview(title: session.title, isActive: isActive)
        }
        .dropDestination(for: TerminalSessionDragID.self) { items, location in
            // 显式拒绝：源不属于本 window 的 session（跨 window 拖动场景），UI 不再假装接受 drop。
            guard let source = items.first?.id, source != session.id,
                  ownedIDs.contains(source) else { return false }
            let height = measuredHeight > 0 ? measuredHeight : 1
            let after = location.y >= height / 2
            onDrop(source, after)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
            if !hovering { hoveredEdge = nil; onHoverEdge(nil) }
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
                let edge: TabDropEdge = location.y < half ? .start : .end
                hoveredEdge = edge
                onHoverEdge(edge)
            case .ended:
                hoveredEdge = nil
                onHoverEdge(nil)
            }
        }
    }

    private var backgroundFill: AnyShapeStyle {
        if isActive { return AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) }
        if isHovering { return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.5)) }
        return AnyShapeStyle(Color.clear)
    }

    private func commitRename() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespaces)
        onRename(trimmed)
        isEditing = false
    }
}
