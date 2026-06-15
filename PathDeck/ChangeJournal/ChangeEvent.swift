import Foundation

import AppKit

enum ChangeEventType: String, Sendable, CaseIterable {
    case added
    case modified
    case deleted

    var nsColor: NSColor {
        switch self {
        case .added: .systemGreen
        case .modified: .systemOrange
        case .deleted: .systemRed
        }
    }
}

struct ChangeEvent: Identifiable, Hashable, Sendable {
    let id: Int64
    let path: String
    let fileName: String
    let eventType: ChangeEventType
    let timestamp: Date
    let directory: String
    let terminalSessionID: UUID?
}

// MARK: - Time Grouping

enum ChangeTimeGroup: CaseIterable, Hashable {
    case justNow
    case fiveMin
    case today
    case earlier

    var label: String {
        switch self {
        case .justNow: "刚刚"
        case .fiveMin: "5 分钟内"
        case .today: "今天"
        case .earlier: "更早"
        }
    }
}

extension ChangeEvent {
    static func grouped(_ events: [ChangeEvent],
                        relativeTo now: Date = .init()) -> [(group: ChangeTimeGroup, events: [ChangeEvent])] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        var buckets: [ChangeTimeGroup: [ChangeEvent]] = [:]
        for event in events {
            let interval = now.timeIntervalSince(event.timestamp)
            let group: ChangeTimeGroup
            if interval < 60 {
                group = .justNow
            } else if interval < 300 {
                group = .fiveMin
            } else if event.timestamp >= startOfToday {
                group = .today
            } else {
                group = .earlier
            }
            buckets[group, default: []].append(event)
        }

        return ChangeTimeGroup.allCases.compactMap { group in
            guard let events = buckets[group], !events.isEmpty else { return nil }
            return (group: group, events: events)
        }
    }
}
