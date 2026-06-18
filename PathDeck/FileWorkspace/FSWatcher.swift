import Foundation

nonisolated final class FSWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var watchedDirectory: String?
    /// 除根目录外额外监听的已展开子目录路径集合。
    private var expandedDirectories: Set<String> = []
    let queue = DispatchQueue(label: "in.riverflows.PathDeck.fswatcher", qos: .utility)
    private static let queueKey = DispatchSpecificKey<Bool>()
    private let handler: @Sendable (Set<String>) -> Void

    private var dirtyDirs: Set<String> = []
    private var flushWork: DispatchWorkItem?
    private static let coalesceWindow: TimeInterval = 0.5

    init(handler: @escaping @Sendable (Set<String>) -> Void) {
        self.handler = handler
        queue.setSpecific(key: Self.queueKey, value: true)
    }

    func watch(directory: URL) {
        stop()

        var dirPath = directory.path(percentEncoded: false)
        if dirPath.hasSuffix("/") && dirPath.count > 1 {
            dirPath = String(dirPath.dropLast())
        }
        queue.sync {
            watchedDirectory = dirPath
            expandedDirectories = []
        }

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
        let cleanup = {
            self.watchedDirectory = nil
            self.expandedDirectories = []
            self.flushWork?.cancel()
            self.flushWork = nil
            if !self.dirtyDirs.isEmpty {
                let dirs = self.dirtyDirs
                self.dirtyDirs.removeAll()
                self.handler(dirs)
            }
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            cleanup()
        } else {
            queue.sync(execute: cleanup)
        }
    }

    deinit {
        stop()
    }

    func setWatchedDirectory(_ url: URL) {
        var dirPath = url.path(percentEncoded: false)
        if dirPath.hasSuffix("/") && dirPath.count > 1 {
            dirPath = String(dirPath.dropLast())
        }
        queue.sync {
            watchedDirectory = dirPath
            expandedDirectories = []
        }
    }

    func setExpandedDirectories(_ urls: Set<URL>) {
        let paths = Set(urls.map { url -> String in
            var p = url.path(percentEncoded: false)
            if p.hasSuffix("/") && p.count > 1 { p = String(p.dropLast()) }
            return p
        })
        queue.sync { expandedDirectories = paths }
    }

    func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard let watchedDir = watchedDirectory else { return }

        var watchedDirs = expandedDirectories
        watchedDirs.insert(watchedDir)

        for (path, flag) in zip(paths, flags) {
            let isFile = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
            let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            guard isFile || isDir else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            if watchedDirs.contains(parent) {
                dirtyDirs.insert(parent)
            }
        }

        guard !dirtyDirs.isEmpty else { return }
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
        guard !dirtyDirs.isEmpty else { return }
        let dirs = dirtyDirs
        dirtyDirs.removeAll()
        handler(dirs)
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
