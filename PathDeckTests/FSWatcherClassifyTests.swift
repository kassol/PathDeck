import Testing
import Foundation
@testable import PathDeck

struct FSWatcherClassifyTests {

    private func flag(_ bits: Int...) -> FSEventStreamEventFlags {
        bits.reduce(UInt32(0)) { $0 | UInt32($1) }
    }

    // MARK: - File Events

    @Test func createdFileClassifiesAsAdded() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == .added)
    }

    @Test func modifiedFileClassifiesAsModified() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemModified, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == .modified)
    }

    @Test func removedFileClassifiesAsDeleted() {
        let path = "/tmp/pd-nonexistent-\(UUID().uuidString)"
        let f = flag(kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: path) == .deleted)
    }

    @Test func renamedExistingFileClassifiesAsModified() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == .modified)
    }

    @Test func renamedCreatedExistingFileClassifiesAsAdded() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == .added)
    }

    @Test func renamedNonexistentFileClassifiesAsDeleted() {
        let path = "/tmp/pd-nonexistent-\(UUID().uuidString)"
        let f = flag(kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: path) == .deleted)
    }

    // MARK: - Directory Events

    @Test func createdDirClassifiesAsAdded() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemIsDir)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == .added)
    }

    @Test func removedDirClassifiesAsDeleted() {
        let path = "/tmp/pd-nonexistent-dir-\(UUID().uuidString)"
        let f = flag(kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemIsDir)
        #expect(FSWatcher.classify(flag: f, path: path) == .deleted)
    }

    // MARK: - Edge Cases

    @Test func noRelevantFlagReturnsNil() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let f = flag(kFSEventStreamEventFlagItemIsFile)
        #expect(FSWatcher.classify(flag: f, path: tmp.path) == nil)
    }
}
