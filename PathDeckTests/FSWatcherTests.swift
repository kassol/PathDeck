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

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func watchedPath(_ dir: URL) -> String {
        var path = dir.path(percentEncoded: false)
        if path.hasSuffix("/") && path.count > 1 {
            path = String(path.dropLast())
        }
        return path
    }

    // MARK: - Filter tests (no real stream, deterministic)

    @Test func parentMismatchIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.setWatchedDirectory(tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: ["/some/other/dir/file.txt"],
                flags: [Self.fileFlag]
            )
        }

        #expect(counter.count == 0)
    }

    @Test func missingFileOrDirFlagIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.setWatchedDirectory(tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [watchedPath(tmp) + "/file.txt"],
                flags: [Self.modifiedFlag]
            )
        }

        #expect(counter.count == 0)
    }

    @Test func deepChildIsIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.setWatchedDirectory(tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [watchedPath(tmp) + "/sub/file.txt"],
                flags: [Self.fileFlag]
            )
        }

        #expect(counter.count == 0)
    }

    // MARK: - Coalesce test (no real stream, semaphore for determinism)

    @Test func rapidEventsCoalesceToSingleCall() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let semaphore = DispatchSemaphore(value: 0)
        let counter = CallCounter()
        let watcher = FSWatcher {
            counter.increment()
            semaphore.signal()
        }
        watcher.setWatchedDirectory(tmp)

        let base = watchedPath(tmp)
        watcher.queue.sync {
            watcher.handleRawEvents(paths: [base + "/a.txt"], flags: [Self.fileFlag])
            watcher.handleRawEvents(paths: [base + "/b.txt"], flags: [Self.fileFlag])
            watcher.handleRawEvents(paths: [base + "/sub"], flags: [Self.dirFlag])
        }

        let result = semaphore.wait(timeout: .now() + 3.0)
        #expect(result == .success)
        // Brief wait to verify no second call
        Thread.sleep(forTimeInterval: 0.2)
        #expect(counter.count == 1)
    }

    // MARK: - Stop tests (need real stream for stop() logic)

    @Test func stopFlushesWhenDirty() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [watchedPath(tmp) + "/a.txt"],
                flags: [Self.fileFlag]
            )
        }
        watcher.stop()

        #expect(counter.count == 1)
    }

    @Test func stopDoesNotFireWhenClean() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { counter.increment() }
        watcher.watch(directory: tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: ["/elsewhere/a.txt"],
                flags: [Self.fileFlag]
            )
        }
        watcher.stop()

        #expect(counter.count == 0)
    }
}
