import Testing
import Foundation
@testable import PathDeck

struct ChangeTimeGroupTests {
    private let now = Date()

    private func event(secondsAgo: TimeInterval, type: ChangeEventType = .added) -> ChangeEvent {
        ChangeEvent(
            id: Int64(secondsAgo),
            path: "/tmp/file\(Int(secondsAgo)).txt",
            fileName: "file\(Int(secondsAgo)).txt",
            eventType: type,
            timestamp: now.addingTimeInterval(-secondsAgo),
            directory: "/tmp",
            terminalSessionID: nil
        )
    }

    @Test func justNowGroup() {
        let events = [event(secondsAgo: 5), event(secondsAgo: 30), event(secondsAgo: 59)]
        let groups = ChangeEvent.grouped(events, relativeTo: now)
        #expect(groups.count == 1)
        #expect(groups[0].group == .justNow)
        #expect(groups[0].events.count == 3)
    }

    @Test func fiveMinGroup() {
        let events = [event(secondsAgo: 61), event(secondsAgo: 180), event(secondsAgo: 299)]
        let groups = ChangeEvent.grouped(events, relativeTo: now)
        #expect(groups.count == 1)
        #expect(groups[0].group == .fiveMin)
        #expect(groups[0].events.count == 3)
    }

    @Test func todayGroup() {
        let events = [event(secondsAgo: 301), event(secondsAgo: 3600)]
        let groups = ChangeEvent.grouped(events, relativeTo: now)
        #expect(groups.count == 1)
        #expect(groups[0].group == .today)
    }

    @Test func earlierGroup() {
        let yesterday = ChangeEvent(
            id: 1,
            path: "/tmp/old.txt",
            fileName: "old.txt",
            eventType: .modified,
            timestamp: Calendar.current.date(byAdding: .day, value: -2, to: now)!,
            directory: "/tmp",
            terminalSessionID: nil
        )
        let groups = ChangeEvent.grouped([yesterday], relativeTo: now)
        #expect(groups.count == 1)
        #expect(groups[0].group == .earlier)
    }

    @Test func mixedGroupsOrdered() {
        let events = [
            event(secondsAgo: 10),
            event(secondsAgo: 120),
            event(secondsAgo: 600),
        ]
        let groups = ChangeEvent.grouped(events, relativeTo: now)
        #expect(groups.count == 3)
        #expect(groups[0].group == .justNow)
        #expect(groups[1].group == .fiveMin)
        #expect(groups[2].group == .today)
    }

    @Test func emptyEventsReturnsEmpty() {
        let groups = ChangeEvent.grouped([], relativeTo: now)
        #expect(groups.isEmpty)
    }
}
