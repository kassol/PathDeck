import Testing
import Foundation
@testable import PathDeck

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct FSWatcherTests {
    private static let fileFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)
    private static let dirFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
    private static let modifiedFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)

    // The coalesce window is 0.5s; wait past it to let any scheduled flush run.
    private static let settleInterval: TimeInterval = 0.7

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    // Mirrors the normalization watch(directory:) applies before storing watchedDirectory.
    private func watchedPath(_ dir: URL) -> String {
        var path = dir.path(percentEncoded: false)
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        return path
    }

    @Test func parentMismatchIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)
        defer { watcher.stop() }

        watcher.handleRawEvents(
            paths: ["/some/other/dir/file.txt"],
            flags: [Self.fileFlag]
        )
        Thread.sleep(forTimeInterval: Self.settleInterval)

        #expect(counter.count == 0)
    }

    @Test func missingFileOrDirFlagIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)
        defer { watcher.stop() }

        // Parent matches, but neither file nor dir flag is set.
        watcher.handleRawEvents(
            paths: [watchedPath(tmp) + "/file.txt"],
            flags: [Self.modifiedFlag]
        )
        Thread.sleep(forTimeInterval: Self.settleInterval)

        #expect(counter.count == 0)
    }

    @Test func deepChildIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)
        defer { watcher.stop() }

        watcher.handleRawEvents(
            paths: [watchedPath(tmp) + "/sub/file.txt"],
            flags: [Self.fileFlag]
        )
        Thread.sleep(forTimeInterval: Self.settleInterval)

        #expect(counter.count == 0)
    }

    @Test func rapidEventsCoalesceToSingleCall() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)
        defer { watcher.stop() }

        let base = watchedPath(tmp)
        watcher.handleRawEvents(paths: [base + "/a.txt"], flags: [Self.fileFlag])
        watcher.handleRawEvents(paths: [base + "/b.txt"], flags: [Self.fileFlag])
        watcher.handleRawEvents(paths: [base + "/sub"], flags: [Self.dirFlag])
        Thread.sleep(forTimeInterval: Self.settleInterval)

        #expect(counter.count == 1)
    }

    @Test func stopFlushesWhenDirty() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)

        watcher.handleRawEvents(paths: [watchedPath(tmp) + "/a.txt"], flags: [Self.fileFlag])
        // stop() runs before the 0.5s flush fires; it must flush synchronously.
        watcher.stop()

        #expect(counter.count == 1)
    }

    @Test func stopDoesNotFireWhenClean() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)

        // Filtered event leaves the watcher clean, so stop() must not fire.
        watcher.handleRawEvents(paths: ["/elsewhere/a.txt"], flags: [Self.fileFlag])
        watcher.stop()

        #expect(counter.count == 0)
    }
}
