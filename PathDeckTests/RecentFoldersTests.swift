import Testing
import Foundation
@testable import PathDeck

struct RecentFoldersTests {

    @Test func addAppendsToFront() {
        let recent = RecentFolders(defaults: .init(suiteName: "test-add")!)
        let url = URL(fileURLWithPath: "/tmp/a")
        recent.add(url)
        #expect(recent.items.count == 1)
        #expect(recent.items.first?.path(percentEncoded: false) == "/tmp/a")
    }

    @Test func addDeduplicatesAndMovesToFront() {
        let recent = RecentFolders(defaults: .init(suiteName: "test-dedup")!)
        recent.add(URL(fileURLWithPath: "/tmp/a"))
        recent.add(URL(fileURLWithPath: "/tmp/b"))
        recent.add(URL(fileURLWithPath: "/tmp/a"))
        #expect(recent.items.count == 2)
        #expect(recent.items[0].path(percentEncoded: false) == "/tmp/a")
        #expect(recent.items[1].path(percentEncoded: false) == "/tmp/b")
    }

    @Test func addTruncatesAtMax() {
        let recent = RecentFolders(defaults: .init(suiteName: "test-max")!)
        for i in 0..<15 {
            recent.add(URL(fileURLWithPath: "/tmp/\(i)"))
        }
        #expect(recent.items.count == 10)
        #expect(recent.items.first?.path(percentEncoded: false) == "/tmp/14")
    }

    @Test func clearRemovesAll() {
        let recent = RecentFolders(defaults: .init(suiteName: "test-clear")!)
        recent.add(URL(fileURLWithPath: "/tmp/a"))
        recent.add(URL(fileURLWithPath: "/tmp/b"))
        recent.clear()
        #expect(recent.items.isEmpty)
    }
}
