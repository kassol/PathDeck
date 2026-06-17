import Testing
import Foundation
@testable import PathDeck

struct PerformanceTests {
    private func createTempDirectory(fileCount: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckPerfTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<fileCount {
            let file = dir.appendingPathComponent("file_\(String(format: "%05d", i)).txt")
            try "content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }
        return dir
    }

    @Test func coldOpenThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 1_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = CFAbsoluteTimeGetCurrent()
        let model = WorkspaceModel(root: dir)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(model.items.count == 1_000)
        #expect(elapsed < 1.0, "cold open took \(elapsed)s, expected < 1s")
    }

    @Test func sortThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 1_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let _ = WorkspaceModel.sortedItems(items, by: .name, ascending: true)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 0.2, "sort took \(elapsed)s, expected < 0.2s")
    }

    @Test func sortByDateThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 1_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let _ = WorkspaceModel.sortedItems(items, by: .date, ascending: false)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 0.2, "date sort took \(elapsed)s, expected < 0.2s")
    }

    @Test func filterThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 1_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let filtered = WorkspaceModel.filterItems(items, query: "file_009")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(!filtered.isEmpty)
        #expect(elapsed < 0.1, "filter took \(elapsed)s, expected < 0.1s")
    }

    // MARK: - 10k file baseline (PRD FR-FILE-002 / §14.1)

    @Test func coldOpenTenThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 10_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = CFAbsoluteTimeGetCurrent()
        let model = WorkspaceModel(root: dir)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(model.items.count == 10_000)
        #expect(elapsed < 5.0, "cold open took \(elapsed)s, expected < 5s")
    }

    @Test func sortTenThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 10_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let _ = WorkspaceModel.sortedItems(items, by: .name, ascending: true)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 1.0, "sort took \(elapsed)s, expected < 1s")
    }

    @Test func sortByDateTenThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 10_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let _ = WorkspaceModel.sortedItems(items, by: .date, ascending: false)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 1.0, "date sort took \(elapsed)s, expected < 1s")
    }

    @Test func filterTenThousandFiles() throws {
        let dir = try createTempDirectory(fileCount: 10_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        let items = try DirectoryLister.list(dir, includeHidden: false)
        let start = CFAbsoluteTimeGetCurrent()
        let filtered = WorkspaceModel.filterItems(items, query: "file_009")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(!filtered.isEmpty)
        #expect(elapsed < 0.5, "filter took \(elapsed)s, expected < 0.5s")
    }
}
