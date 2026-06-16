import Foundation

nonisolated final class FSWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var watchedDirectory: String?
    private let queue = DispatchQueue(label: "in.riverflows.PathDeck.fswatcher", qos: .utility)
    private let handler: @Sendable () -> Void

    private var dirty = false
    private var flushWork: DispatchWorkItem?
    private static let coalesceWindow: TimeInterval = 0.5

    init(handler: @escaping @Sendable () -> Void) {
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
        queue.sync {
            watchedDirectory = nil
            flushWork?.cancel()
            flushWork = nil
            if dirty {
                dirty = false
                handler()
            }
        }
    }

    deinit {
        stop()
    }

    func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard let watchedDir = watchedDirectory else { return }

        for (path, flag) in zip(paths, flags) {
            let isFile = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
            let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            guard isFile || isDir else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent == watchedDir else { continue }
            dirty = true
            break
        }

        guard dirty else { return }
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
        guard dirty else { return }
        dirty = false
        handler()
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
