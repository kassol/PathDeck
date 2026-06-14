import SwiftUI

struct ChangeListView: View {
    let events: [ChangeEvent]
    var onNavigate: ((ChangeEvent) -> Void)?

    @State private var filter: ChangeEventType?

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(filter: $filter)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            let filtered = filteredEvents
            let groups = ChangeEvent.grouped(filtered)

            if groups.isEmpty {
                Text("无最近变化")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups, id: \.group) { section in
                        Section {
                            ForEach(section.events) { event in
                                ChangeRow(event: event)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onNavigate?(event) }
                            }
                        } header: {
                            Text("\(section.group.label) (\(section.events.count))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredEvents: [ChangeEvent] {
        guard let filter else { return events }
        return events.filter { $0.eventType == filter }
    }
}

// MARK: - Filter Bar

private struct FilterBar: View {
    @Binding var filter: ChangeEventType?

    var body: some View {
        HStack(spacing: 4) {
            FilterChip(label: "全部", isSelected: filter == nil) {
                filter = nil
            }
            FilterChip(label: "新增", color: .green, isSelected: filter == .added) {
                filter = .added
            }
            FilterChip(label: "修改", color: .orange, isSelected: filter == .modified) {
                filter = .modified
            }
            FilterChip(label: "删除", color: .red, isSelected: filter == .deleted) {
                filter = .deleted
            }
            Spacer()
        }
    }
}

private struct FilterChip: View {
    let label: String
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? color.opacity(0.15) : Color.clear)
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Change Row

private struct ChangeRow: View {
    let event: ChangeEvent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.eventType.iconName)
                .foregroundStyle(event.eventType.color)
                .frame(width: 16)
            Text(event.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(event.timestamp, style: .relative)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .font(.system(size: 12))
    }
}

extension ChangeEventType {
    var iconName: String {
        switch self {
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        }
    }
}
