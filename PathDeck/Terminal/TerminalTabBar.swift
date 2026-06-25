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

    @State private var hoveredDropIndex: Int?

    private var ownedIDs: Set<UUID> { Set(sessions.map(\.id)) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TerminalTabStyle.gap) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        TabItem(
                            session: session,
                            isActive: session.id == activeID,
                            isShiftedLeft: shouldShiftLeft(at: index),
                            isShiftedRight: shouldShiftRight(at: index),
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
                        .id(session.id)
                    }

                    Button(action: onNewTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal")

                    Spacer()
                }
                .padding(.horizontal, 4)
                .animation(TerminalTabStyle.shiftSpring, value: hoveredDropIndex)
            }
            .frame(height: TerminalTabStyle.tabHeight + 4)
            .background(.bar)
            .onChange(of: activeID) { _, new in
                if let id = new { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func shouldShiftLeft(at index: Int) -> Bool {
        guard let drop = hoveredDropIndex else { return false }
        return index >= drop && index > 0
    }

    private func shouldShiftRight(at index: Int) -> Bool {
        guard let drop = hoveredDropIndex else { return false }
        return index < drop
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let session: TerminalSession
    let isActive: Bool
    var isShiftedLeft: Bool
    var isShiftedRight: Bool
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
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("", text: $editingTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(TerminalTabStyle.titleFont)
                    .frame(width: 100)
                    .onExitCommand { cancelRename() }
            } else {
                Text(session.title)
                    .font(TerminalTabStyle.titleFont)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                    .truncationMode(.tail)
                if isActive {
                    Text(session.currentCwd.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .onTapGesture { onNavigateToCwd?(session.currentCwd) }
                        .help(session.currentCwd.path(percentEncoded: false))
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
            .opacity((isHovering || isActive) ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: TerminalTabStyle.tabHeight)
        .background(
            RoundedRectangle(cornerRadius: TerminalTabStyle.cornerRadius, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(alignment: .leading) {
            if isDropTargeted, hoveredEdge == .start {
                RoundedRectangle(cornerRadius: 1).fill(TerminalTabStyle.dropLineColor).frame(width: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if isDropTargeted, hoveredEdge == .end {
                RoundedRectangle(cornerRadius: 1).fill(TerminalTabStyle.dropLineColor).frame(width: 2)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in measuredWidth = new }
            }
        )
        .offset(x: isShiftedLeft ? -TerminalTabStyle.shiftDistance : (isShiftedRight ? TerminalTabStyle.shiftDistance : 0))
        .contentShape(Rectangle())
        .draggable(TerminalSessionDragID(id: session.id)) {
            TerminalTabDragPreview(title: session.title, isActive: isActive)
        }
        .dropDestination(for: TerminalSessionDragID.self) { items, location in
            // 显式拒绝：源不属于本 window 的 session（跨 window 拖动场景），UI 不再假装接受 drop。
            guard let source = items.first?.id, source != session.id,
                  ownedIDs.contains(source) else { return false }
            let width = measuredWidth > 0 ? measuredWidth : 1
            let after = location.x >= width / 2
            onDrop(source, after)
            return true
        } isTargeted: { hovering in
            isDropTargeted = hovering
            if !hovering { hoveredEdge = nil; onHoverEdge(nil) }
        }
        .onTapGesture(count: 2) { startRename() }
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .onContinuousHover { phase in
            guard isDropTargeted else { return }
            switch phase {
            case .active(let location):
                let half = (measuredWidth > 0 ? measuredWidth : 1) / 2
                let edge: TabDropEdge = location.x < half ? .start : .end
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

/// 拖拽 ghost：tab snapshot 风格的轻量预览。
struct TerminalTabDragPreview: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(TerminalTabStyle.titleFont)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: TerminalTabStyle.tabHeight)
        .background(
            RoundedRectangle(cornerRadius: TerminalTabStyle.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .opacity(0.85)
        .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
    }
}

/// 终端 tab 视觉 token，对齐 NSWindowTab 设计语言。
enum TerminalTabStyle {
    static let tabHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 8
    static let gap: CGFloat = 4
    static let shiftDistance: CGFloat = 28
    static let titleFont: Font = .system(size: 13, weight: .regular)
    static var dropLineColor: Color { Color(nsColor: NSColor.controlAccentColor).opacity(0.7) }
    static let shiftSpring: Animation = .spring(response: 0.25, dampingFraction: 0.75)
    static let dropSpring: Animation = .spring(response: 0.35, dampingFraction: 0.7)
}
