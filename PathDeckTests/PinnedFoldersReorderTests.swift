import Testing
import Foundation
@testable import PathDeck

@Suite
struct PinnedFoldersReorderTests {
    private func makeWithItems(_ count: Int) -> (PinnedFolders, UserDefaults, String, URL) {
        let suiteName = "PathDeckTests-reorder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-reorder-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for i in 0..<count {
            let dir = tmp.appendingPathComponent("item\(i)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defaults.set([Data](), forKey: "pinnedFolderBookmarks")
        let folders = PinnedFolders(userDefaults: defaults)
        for i in 0..<count {
            folders.add(tmp.appendingPathComponent("item\(i)"))
        }
        return (folders, defaults, suiteName, tmp)
    }

    @Test
    func moveSwapsItemsAndPersists() {
        let (folders, defaults, suite, tmp) = makeWithItems(3)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tmp)
        }

        let originalFirst = folders.items[0]
        let originalLast = folders.items[2]
        folders.move(from: IndexSet(integer: 0), to: 3)
        #expect(folders.items.last?.standardizedFileURL == originalFirst.standardizedFileURL)
        #expect(folders.items.first?.standardizedFileURL != originalFirst.standardizedFileURL)
        #expect(folders.items[1].standardizedFileURL == originalLast.standardizedFileURL)
    }

    @Test
    func moveBackwardsReordersCorrectly() {
        let (folders, defaults, suite, tmp) = makeWithItems(3)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tmp)
        }

        let originalLast = folders.items[2]
        folders.move(from: IndexSet(integer: 2), to: 0)
        #expect(folders.items.first?.standardizedFileURL == originalLast.standardizedFileURL)
    }

    @Test
    func movePersistedOrderSurvivesReload() {
        let (folders, defaults, suite, tmp) = makeWithItems(3)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tmp)
        }

        folders.move(from: IndexSet(integer: 0), to: 3)
        let expectedOrder = folders.items.map { $0.standardizedFileURL }

        let reloaded = PinnedFolders(userDefaults: defaults)
        let reloadedOrder = reloaded.items.map { $0.standardizedFileURL }
        #expect(reloadedOrder == expectedOrder)
    }

    @Test
    func moveMultipleItemsContiguous() {
        let (folders, defaults, suite, tmp) = makeWithItems(5)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tmp)
        }

        let original = folders.items.map { $0.standardizedFileURL }
        folders.move(from: IndexSet([0, 1]), to: 5)
        let result = folders.items.map { $0.standardizedFileURL }
        #expect(result.suffix(2) == [original[0], original[1]])
        #expect(result.prefix(3) == [original[2], original[3], original[4]])
    }

    @Test
    func moveSingleItemNoop() {
        let (folders, defaults, suite, tmp) = makeWithItems(1)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tmp)
        }
        let before = folders.items.map { $0.standardizedFileURL }
        folders.move(from: IndexSet(integer: 0), to: 0)
        let after = folders.items.map { $0.standardizedFileURL }
        #expect(before == after)
    }
}
