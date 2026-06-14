import Foundation

nonisolated final class FSWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var watchedDirectory: String?
    private let queue = DispatchQueue(label: "in.riverflows.PathDeck.fswatcher", qos: .utility)
    private let handler: @Sendable ([(path: String, type: ChangeEventType)]) -> Void

    init(handler: @escaping @Sendable ([(path: String, type: ChangeEventType)]) -> Void) {
        self.handler = handler
    }

    func watch(directory: URL) {
        stop()

        var dirPath = directory.path(percentEncoded: false)
        if dirPath.hasSuffix("/") && dirPath.count > 1 {
            dirPath = String(dirPath.dropLast())
        }
        watchedDirectory = dirPath

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
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

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
        watchedDirectory = nil
    }

    deinit {
        stop()
    }

    fileprivate func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard let watchedDir = watchedDirectory else { return }
        var classified: [(path: String, type: ChangeEventType)] = []

        for (path, flag) in zip(paths, flags) {
            let isFile = flag & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
            let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            guard isFile || isDir else { continue }
            let parent = (path as NSString).deletingLastPathComponent
            guard parent == watchedDir else { continue }
            if let type = Self.classify(flag: flag, path: path) {
                classified.append((path: path, type: type))
            }
        }

        guard !classified.isEmpty else { return }
        handler(classified)
    }

    static func classify(flag: FSEventStreamEventFlags, path: String) -> ChangeEventType? {
        let removed = flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
        let created = flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        let modified = flag & UInt32(kFSEventStreamEventFlagItemModified) != 0
        let renamed = flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        let exists = FileManager.default.fileExists(atPath: path)

        if removed && !exists { return .deleted }
        if renamed { return exists ? .added : .deleted }
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
