import Testing
import Foundation
@testable import PathDeck

@Suite
struct PinnedFoldersSeedTests {
    @Test
    func seedsDefaultsOnFreshInstall() {
        let suiteName = "PathDeckTests-seed-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folders = PinnedFolders(userDefaults: defaults)

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let apps = URL(fileURLWithPath: "/Applications").standardizedFileURL
        #expect(folders.items.contains { $0.standardizedFileURL == home })
        #expect(folders.items.contains { $0.standardizedFileURL == apps })
        #expect(defaults.object(forKey: "pinnedFolderBookmarks") != nil)
    }

    @Test
    func skipsSeedWhenKeyExistsEmpty() {
        let suiteName = "PathDeckTests-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([Data](), forKey: "pinnedFolderBookmarks")

        let folders = PinnedFolders(userDefaults: defaults)
        #expect(folders.items.isEmpty)
    }

    @Test
    func migratesLegacyAndSkipsSeed() throws {
        let suiteName = "PathDeckTests-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        defaults.set([tmp.path], forKey: "pinnedFolders")

        let folders = PinnedFolders(userDefaults: defaults)
        #expect(folders.items.count == 1)
        #expect(folders.items.first?.standardizedFileURL == tmp.standardizedFileURL)
        #expect(!folders.items.contains { $0.lastPathComponent == "Desktop" })
    }

    @Test
    func seedIsIdempotentAcrossLaunches() {
        let suiteName = "PathDeckTests-idempotent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = PinnedFolders(userDefaults: defaults)
        let firstCount = first.items.count
        _ = first

        let second = PinnedFolders(userDefaults: defaults)
        #expect(second.items.count == firstCount)
    }
}
