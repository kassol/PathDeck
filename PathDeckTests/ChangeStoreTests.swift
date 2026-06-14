import Testing
@testable import PathDeck
import Foundation

@Suite
struct ChangeStoreTests {
    private func makeTempStore() throws -> (ChangeStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = try ChangeStore(databasePath: tmpDir.appendingPathComponent("test.db").path(percentEncoded: false))
        return (store, tmpDir)
    }

    @Test
    func writeAndRead() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try store.recordBatch([
            (path: "/tmp/test.txt", type: .added, directory: "/tmp"),
            (path: "/tmp/other.txt", type: .modified, directory: "/tmp"),
        ])

        let events = try store.recentEvents(in: "/tmp")
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.id > 0 })
    }

    @Test
    func directoryFilter() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try store.recordBatch([
            (path: "/a/file.txt", type: .added, directory: "/a"),
            (path: "/b/file.txt", type: .added, directory: "/b"),
        ])

        let aEvents = try store.recentEvents(in: "/a")
        #expect(aEvents.count == 1)
        #expect(aEvents[0].directory == "/a")
        #expect(aEvents[0].fileName == "file.txt")
    }

    @Test
    func orderMostRecentFirst() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try store.recordBatch([
            (path: "/tmp/first.txt", type: .added, directory: "/tmp"),
        ])
        Thread.sleep(forTimeInterval: 0.05)
        try store.recordBatch([
            (path: "/tmp/second.txt", type: .modified, directory: "/tmp"),
        ])

        let events = try store.recentEvents(in: "/tmp")
        #expect(events.count == 2)
        #expect(events[0].fileName == "second.txt")
    }

    @Test
    func limitRespected() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let batch = (0..<10).map { i in
            (path: "/tmp/file\(i).txt", type: ChangeEventType.added, directory: "/tmp")
        }
        try store.recordBatch(batch)

        let events = try store.recentEvents(in: "/tmp", limit: 3)
        #expect(events.count == 3)
    }

    @Test
    func emptyBatchNoOp() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try store.recordBatch([])
        let events = try store.recentEvents(in: "/any")
        #expect(events.isEmpty)
    }

    @Test
    func fileNameExtracted() throws {
        let (store, tmpDir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try store.recordBatch([
            (path: "/Users/kassol/Documents/report.pdf", type: .added, directory: "/Users/kassol/Documents"),
        ])

        let events = try store.recentEvents(in: "/Users/kassol/Documents")
        #expect(events[0].fileName == "report.pdf")
        #expect(events[0].path == "/Users/kassol/Documents/report.pdf")
    }
}
