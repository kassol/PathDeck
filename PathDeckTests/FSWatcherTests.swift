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
        let watcher = FSWatcher { _ in counter.increment() }
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
        let watcher = FSWatcher { _ in counter.increment() }
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
        let watcher = FSWatcher { _ in counter.increment() }
        watcher.setWatchedDirectory(tmp)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [watchedPath(tmp) + "/sub/file.txt"],
                flags: [Self.fileFlag]
            )
        }

        #expect(counter.count == 0)
    }

    @Test func expandedSubdirectoryEventIsMatched() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        var capturedDirs: Set<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        let watcher = FSWatcher { dirs in
            capturedDirs = dirs
            semaphore.signal()
        }
        watcher.setWatchedDirectory(tmp)
        watcher.setExpandedDirectories([sub])

        let subPath = watchedPath(sub)
        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [subPath + "/child.txt"],
                flags: [Self.fileFlag]
            )
        }

        let result = semaphore.wait(timeout: .now() + 3.0)
        #expect(result == .success)
        #expect(capturedDirs.contains(subPath))
    }

    // MARK: - Coalesce test (no real stream, semaphore for determinism)

    @Test func rapidEventsCoalesceToSingleCall() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let semaphore = DispatchSemaphore(value: 0)
        let counter = CallCounter()
        let watcher = FSWatcher { _ in
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

    @Test func dirtyDirsContainsBothRootAndExpanded() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        var capturedDirs: Set<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        let watcher = FSWatcher { dirs in
            capturedDirs = dirs
            semaphore.signal()
        }
        watcher.setWatchedDirectory(tmp)
        watcher.setExpandedDirectories([sub])

        let base = watchedPath(tmp)
        let subPath = watchedPath(sub)
        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [base + "/root.txt", subPath + "/child.txt"],
                flags: [Self.fileFlag, Self.fileFlag]
            )
        }

        let result = semaphore.wait(timeout: .now() + 3.0)
        #expect(result == .success)
        #expect(capturedDirs.contains(base))
        #expect(capturedDirs.contains(subPath))
    }

    // MARK: - Stop tests (need real stream for stop() logic)

    @Test func stopFlushesWhenDirty() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counter = CallCounter()
        let watcher = FSWatcher { _ in counter.increment() }
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
        let watcher = FSWatcher { _ in counter.increment() }
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

    // MARK: - S28 boundary tests

    @Test func reWatchRestartsCleanly() throws {
        let tmp1 = try makeTempDir()
        let tmp2 = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: tmp1)
            try? FileManager.default.removeItem(at: tmp2)
        }

        var capturedDirs: Set<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        let callCount = CallCounter()
        let watcher = FSWatcher { dirs in
            capturedDirs = dirs
            callCount.increment()
            semaphore.signal()
        }

        let base1 = watchedPath(tmp1)
        let base2 = watchedPath(tmp2)

        // watch tmp1, then re-watch tmp2 on same instance
        watcher.watch(directory: tmp1)
        watcher.watch(directory: tmp2)

        // old dir events should be ignored by same watcher after re-watch
        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [base1 + "/old.txt"],
                flags: [Self.fileFlag]
            )
        }
        Thread.sleep(forTimeInterval: 0.1)
        #expect(callCount.count == 0)

        // new dir events should be accepted
        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [base2 + "/new.txt"],
                flags: [Self.fileFlag]
            )
        }

        let result = semaphore.wait(timeout: .now() + 3.0)
        #expect(result == .success)
        #expect(capturedDirs.contains(base2))
        #expect(!capturedDirs.contains(base1))
    }

    @Test func setExpandedDirsDuringActiveEvents() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub1 = tmp.appendingPathComponent("sub1")
        let sub2 = tmp.appendingPathComponent("sub2")
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: false)

        var capturedDirs: Set<String> = []
        let semaphore = DispatchSemaphore(value: 0)
        let watcher = FSWatcher { dirs in
            capturedDirs = dirs
            semaphore.signal()
        }
        watcher.setWatchedDirectory(tmp)
        watcher.setExpandedDirectories([sub1])

        let sub1Path = watchedPath(sub1)
        let sub2Path = watchedPath(sub2)

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [sub1Path + "/a.txt"],
                flags: [Self.fileFlag]
            )
        }

        watcher.setExpandedDirectories([sub1, sub2])

        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [sub2Path + "/b.txt"],
                flags: [Self.fileFlag]
            )
        }

        let result = semaphore.wait(timeout: .now() + 3.0)
        #expect(result == .success)
        #expect(capturedDirs.contains(sub1Path))
        #expect(capturedDirs.contains(sub2Path))
    }

    @Test func removedExpandedDirStopsMatching() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        let counter = CallCounter()
        let watcher = FSWatcher { _ in counter.increment() }
        watcher.watch(directory: tmp)
        watcher.setExpandedDirectories([sub])
        watcher.setExpandedDirectories([])

        let subPath = watchedPath(sub)
        watcher.queue.sync {
            watcher.handleRawEvents(
                paths: [subPath + "/file.txt"],
                flags: [Self.fileFlag]
            )
        }

        // watch() created a real stream, so stop() enters the flush path;
        // if the removed expanded dir was wrongly matched, handler fires here
        watcher.stop()
        #expect(counter.count == 0)
    }
}
