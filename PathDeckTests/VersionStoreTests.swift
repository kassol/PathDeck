import Testing
import Foundation
@testable import PathDeck

@Suite
struct VersionStoreTests {
    private func makeTempStore() throws -> (VersionStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = try VersionStore(databasePath: tmpDir.appendingPathComponent("test-versions.db").path(percentEncoded: false))
        return (store, tmpDir)
    }

    @Test
    func saveAndRetrieveVersion() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let content = "hello world".data(using: .utf8)!
        let hash = content.sha256Hex
        try store.saveVersion(path: "/tmp/test.txt", directory: "/tmp", content: content, hash: hash)

        let latest = try store.latestVersion(for: "/tmp/test.txt")
        #expect(latest != nil)
        #expect(latest?.contentHash == hash)
        #expect(latest?.size == content.count)
        #expect(latest?.path == "/tmp/test.txt")
        #expect(latest?.directory == "/tmp")
    }

    @Test
    func oldestVersionsCleanedBeyondMax() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for i in 0..<12 {
            let content = "version \(i)".data(using: .utf8)!
            try store.saveVersion(
                path: "/tmp/file.txt", directory: "/tmp",
                content: content, hash: content.sha256Hex
            )
        }

        let versions = try store.versions(for: "/tmp/file.txt", limit: 20)
        #expect(versions.count == VersionStore.maxVersionsPerFile)
        #expect(versions[0].contentHash == "version 11".data(using: .utf8)!.sha256Hex)
    }

    @Test
    func duplicateHashSkipped() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let content = "same content".data(using: .utf8)!
        let hash = content.sha256Hex
        try store.saveVersion(path: "/tmp/dup.txt", directory: "/tmp", content: content, hash: hash)
        try store.saveVersion(path: "/tmp/dup.txt", directory: "/tmp", content: content, hash: hash)

        let versions = try store.versions(for: "/tmp/dup.txt")
        #expect(versions.count == 1)
    }

    @Test
    func pathsWithVersionsReturnsCorrectSet() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let c1 = "a".data(using: .utf8)!
        let c2 = "b".data(using: .utf8)!
        try store.saveVersion(path: "/dir/a.txt", directory: "/dir", content: c1, hash: c1.sha256Hex)
        try store.saveVersion(path: "/dir/b.txt", directory: "/dir", content: c2, hash: c2.sha256Hex)
        try store.saveVersion(path: "/other/c.txt", directory: "/other", content: c1, hash: c1.sha256Hex)

        let paths = try store.pathsWithVersions(in: "/dir")
        #expect(Set(paths) == ["/dir/a.txt", "/dir/b.txt"])
    }

    @Test
    func eligibilityCheck() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let textFile = tmpDir.appendingPathComponent("test.txt")
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)
        #expect(VersionStore.isEligible(url: textFile))

        let jsonFile = tmpDir.appendingPathComponent("data.json")
        try "{}".write(to: jsonFile, atomically: true, encoding: .utf8)
        #expect(VersionStore.isEligible(url: jsonFile))

        let pngFile = tmpDir.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngFile)
        #expect(!VersionStore.isEligible(url: pngFile))

        let bigFile = tmpDir.appendingPathComponent("big.txt")
        try Data(count: VersionStore.maxFileSize + 1).write(to: bigFile)
        #expect(!VersionStore.isEligible(url: bigFile))
    }
}
