import SwiftUI

struct ChangeListView: View {
    let events: [ChangeEvent]

    var body: some View {
        if events.isEmpty {
            Text("无最近变化")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(events) { event in
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
            .listStyle(.plain)
        }
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
