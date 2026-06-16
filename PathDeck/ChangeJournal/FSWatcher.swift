import Foundation

nonisolated final class FSWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var watchedDirectory: String?
    private let queue = DispatchQueue(label: "in.riverflows.PathDeck.fswatcher", qos: .utility)
    private let handler: @Sendable ([(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])]) -> Void
    private let snapshotProvider: @Sendable () -> [TerminalActivitySnapshot]

    private var pending: [String: ChangeEventType] = [:]
    private var pendingSnapshots: [String: [TerminalActivitySnapshot]] = [:]
    private var flushWork: DispatchWorkItem?
    private static let coalesceWindow: TimeInterval = 0.5

    init(
        snapshotProvider: @escaping @Sendable () -> [TerminalActivitySnapshot] = { [] },
        handler: @escaping @Sendable ([(path: String, type: ChangeEventType, directory: String, snapshots: [TerminalActivitySnapshot])]) -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.handler = handler
    }

    func watch(directory: URL) {
        stop()

        var dirPath = directory.path(percentEncoded: false)
        if dirPath.hasSuffix("/") && dirPath.count > 1 {
            dirPath = String(dirPath.dropLast())
        }
        queue.sync { watchedDirectory = dirPath }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [dirPath] as CFArray
        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            nil,
            fsWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        // 在 watcher queue 上清理 pending + watchedDirectory，与在途 handleRawEvents/flush 串行，
        // 避免主线程（navigate→stop）与后台回调并发 mutate 共享状态（UB）。
        // batch 用清空前的 watchedDirectory 填 directory：pending 事件归属旧目录，
        // 而非导航后已切换的新目录（否则旧目录变化会写进新目录的 journal）。
        queue.sync {
            let dir = watchedDirectory
            watchedDirectory = nil
            flushWork?.cancel()
            flushWork = nil
            defer { pending.removeAll(); pendingSnapshots.removeAll() }
            guard !pending.isEmpty, let dir else { return }
            let batch = pending.map { (path: $0.key, type: $0.value, directory: dir, snapshots: pendingSnapshots[$0.key] ?? []) }
            handler(batch)
        }
    }

    deinit {
        stop()
    }

    /// internal（非 fileprivate）以便单测直接注入 raw 事件验证归属目录，不依赖真实 FSEventStream 异步回调。
    func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard let watchedDir = watchedDirectory else { return }

        for (path, flag) in zip(paths, flags) {
            let isFile = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
            let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            guard isFile || isDir else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent == watchedDir else { continue }
            guard let type = Self.classify(flag: flag, path: path) else { continue }
            pending[path] = Self.mergeType(existing: pending[path], new: type)
            // 入队时刻（首次见到该 path）捕获终端活跃快照——最接近写入时刻；
            // coalesce 后续不覆盖，消除「flush 时刻读、跨 tab 切换污染」。
            if pendingSnapshots[path] == nil {
                pendingSnapshots[path] = snapshotProvider()
            }
        }

        guard !pending.isEmpty else { return }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        flushWork = work
        queue.asyncAfter(deadline: .now() + Self.coalesceWindow, execute: work)
    }

    private func flush() {
        guard !pending.isEmpty, let dir = watchedDirectory else { return }
        let batch = pending.map { (path: $0.key, type: $0.value, directory: dir, snapshots: pendingSnapshots[$0.key] ?? []) }
        pending.removeAll()
        pendingSnapshots.removeAll()
        handler(batch)
    }

    static func mergeType(existing: ChangeEventType?, new: ChangeEventType) -> ChangeEventType {
        guard let existing else { return new }
        switch (existing, new) {
        case (.added, .modified): return .added
        case (.added, .deleted): return .deleted
        case (.modified, .added): return .modified
        case (.modified, .deleted): return .deleted
        case (.deleted, .added): return .modified
        case (.deleted, .modified): return .modified
        default: return existing
        }
    }

    static func classify(flag: FSEventStreamEventFlags, path: String) -> ChangeEventType? {
        let removed = flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
        let created = flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        let modified = flag & UInt32(kFSEventStreamEventFlagItemModified) != 0
        let renamed = flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        let exists = FileManager.default.fileExists(atPath: path)

        if removed && !exists { return .deleted }
        if renamed && !exists { return .deleted }
        if renamed && created && exists { return .added }
        if renamed && exists { return .modified }
        if created && exists { return .added }
        if modified && exists { return .modified }
        return nil
    }
}

private nonisolated func fsWatcherCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let watcher = Unmanaged<FSWatcher>.fromOpaque(clientInfo).takeUnretainedValue()

    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    var flags: [FSEventStreamEventFlags] = []

    for i in 0..<numEvents {
        guard let rawPath = CFArrayGetValueAtIndex(cfPaths, i) else { continue }
        let cfStr = Unmanaged<CFString>.fromOpaque(rawPath).takeUnretainedValue()
        paths.append(cfStr as String)
        flags.append(eventFlags[i])
    }

    watcher.handleRawEvents(paths: paths, flags: flags)
}
