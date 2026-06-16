import Testing
import Foundation
@testable import PathDeck

struct FSWatcherTests {
    /// 回归：导航瞬间 flush 的旧目录 pending 必须归属旧目录，而非导航后的新目录。
    /// （修复前 WorkspaceModel.handleFSEvents 回读 currentURL，旧目录变化会写进新目录 journal。）
    @Test func flushOnNavigationStampsEventsWithOriginDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckFSW-\(UUID().uuidString)")
        let dirA = base.appendingPathComponent("A")
        let dirB = base.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let box = CapturedBatches()
        let watcher = FSWatcher { batch in box.append(batch) }
        watcher.watch(directory: dirA)

        // 注入一个 A 目录下的 deleted 事件：文件不存在 → classify=.deleted，
        // 无需真实文件、不依赖真实 FSEventStream 的异步回调。
        let goneFlag = UInt32(kFSEventStreamEventFlagItemRemoved) | UInt32(kFSEventStreamEventFlagItemIsFile)
        let gonePath = dirA.appendingPathComponent("gone.txt").path(percentEncoded: false)
        watcher.handleRawEvents(paths: [gonePath], flags: [goneFlag])

        // 导航到 B —— watch 内部 stop() 立即 flush A 的 pending（早于 0.5s coalesce）。
        watcher.watch(directory: dirB)

        let dirs = box.snapshot().map { $0.directory }
        #expect(dirs.contains(dirA.path(percentEncoded: false)))
        #expect(!dirs.contains(dirB.path(percentEncoded: false)))
    }
}

/// 线程安全收集 handler 回调的 batch（handler 在 watcher queue 调用，测试主线程读取）。
private final class CapturedBatches: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])] = []

    func append(_ batch: [(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])]) {
        lock.lock(); items.append(contentsOf: batch); lock.unlock()
    }

    func snapshot() -> [(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])] {
        lock.lock(); defer { lock.unlock() }; return items
    }
}
