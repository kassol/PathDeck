import Foundation
import Observation
import AppKit

enum SortColumn: String {
    case name, date, size, kind
}

@Observable
final class WorkspaceModel {
    private static let lastFolderKey = "lastOpenedFolder"
    private static let sortColumnKey = "sortColumn"
    private static let sortAscendingKey = "sortAscending"
    private static let showHiddenKey = "showHidden"

    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []
    private(set) var changes: [ChangeEvent] = []
    private(set) var changeIndicators: [String: ChangeEventType] = [:]
    private(set) var hiddenCount: Int = 0
    private(set) var versionedPaths: Set<String> = []

    var sortColumn: SortColumn = .name {
        didSet { defaults.set(sortColumn.rawValue, forKey: Self.sortColumnKey) }
    }
    var sortAscending: Bool = true {
        didSet { defaults.set(sortAscending, forKey: Self.sortAscendingKey) }
    }
    var showHidden: Bool = false {
        didSet { defaults.set(showHidden, forKey: Self.showHiddenKey) }
    }
    var selectedURLs: [URL] = []
    var pendingRenameURL: URL?
    /// 命令式选择信号：驱动 `FileTableView` 选中这组 URL 的行并滚动到首项（单项即长度 1），消费后置 nil。
    var revealSelection: [URL]?
    var isSearching: Bool = false
    var isBottomPanelVisible: Bool = false
    var searchQuery: String = "" {
        didSet { applySearch() }
    }

    var pathSegments: [(name: String, url: URL)] {
        var segments: [(name: String, url: URL)] = []
        var url = currentURL.standardizedFileURL
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.path(percentEncoded: false)

        while true {
            let path = url.path(percentEncoded: false)
            if path == homePath {
                segments.append((name: "~", url: url))
                break
            }
            if path == "/" {
                segments.append((name: "/", url: url))
                break
            }
            segments.append((name: url.lastPathComponent, url: url))
            url = url.deletingLastPathComponent().standardizedFileURL
        }
        segments.reverse()
        return segments
    }

    private let defaults: UserDefaults
    private var watcher: FSWatcher?
    private var changeStore: ChangeStore?
    private(set) var versionStore: VersionStore?
    private var indicatorTimers: [String: Timer] = [:]

    /// 终端活跃快照，由 `ContentView` 推送、`FSWatcher` 后台队列读取做归因。
    /// `NSLock` 保护跨线程读写（主线程写 / watcher 队列读）。
    private let snapshotsLock = NSLock()
    private var terminalSnapshots: [TerminalActivitySnapshot] = []

    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let root {
            currentURL = root
        } else if let saved = defaults.string(forKey: Self.lastFolderKey) {
            let url = URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir),
               isDir.boolValue {
                currentURL = url
            } else {
                currentURL = FileManager.default.homeDirectoryForCurrentUser
            }
        } else {
            currentURL = FileManager.default.homeDirectoryForCurrentUser
        }

        if let savedSort = defaults.string(forKey: Self.sortColumnKey),
           let col = SortColumn(rawValue: savedSort) {
            sortColumn = col
        }
        if defaults.object(forKey: Self.sortAscendingKey) != nil {
            sortAscending = defaults.bool(forKey: Self.sortAscendingKey)
        }
        if defaults.object(forKey: Self.showHiddenKey) != nil {
            showHidden = defaults.bool(forKey: Self.showHiddenKey)
        }

        do {
            changeStore = try ChangeStore()
        } catch {
            NSLog("[PathDeck] ChangeStore init failed: \(error)")
        }
        do {
            versionStore = try VersionStore()
        } catch {
            NSLog("[PathDeck] VersionStore init failed: \(error)")
        }

        watcher = FSWatcher(
            snapshotProvider: { [weak self] in self?.readTerminalSnapshots() ?? [] }
        ) { [weak self] events in
            DispatchQueue.main.async {
                self?.handleFSEvents(events)
            }
        }

        reload()
        watcher?.watch(directory: currentURL)
    }

    func enter(_ item: FileItem) {
        guard item.isDirectory else { return }
        navigate(to: item.url)
    }

    func goUp() {
        guard currentURL.path(percentEncoded: false) != "/" else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func navigate(to url: URL) {
        currentURL = url.standardizedFileURL
        searchQuery = ""
        isSearching = false
        clearExpiredIndicators()
        reload()
        watcher?.watch(directory: currentURL)
        defaults.set(currentURL.path(percentEncoded: false), forKey: Self.lastFolderKey)
    }

    /// 导航到首项父目录并高亮选择集（跨目录 reveal / Open Selection，单项即长度 1）。
    /// 单 workspace 只展示一个目录：仅高亮与首项同父目录的项，跨父目录的其余项忽略。
    /// `selectedURLs`/`revealSelection` 锚在 navigate 后的 `currentURL` 上，与 `DirectoryLister` 子项 URL 同构；
    /// `revealSelection` 驱动 `FileTableView` 一次性 `selectRowIndexes`（全部行）+ `scrollRowToVisible`（首项），
    /// 表格选中后经 `onSelectionChange` 回写 `selectedURLs`（单设 `selectedURLs` 不触发表格高亮）。
    func reveal(_ fileURLs: [URL]) {
        guard let first = fileURLs.first else { return }
        navigate(to: first.deletingLastPathComponent())
        let targets = fileURLs
            .filter { $0.deletingLastPathComponent().standardizedFileURL == currentURL }
            .map { currentURL.appendingPathComponent($0.lastPathComponent) }
        selectedURLs = targets
        revealSelection = targets
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        navigate(to: url)
        RecentFolders.shared.add(url)
    }

    func toggleHidden() {
        showHidden.toggle()
        reload()
    }

    func applySort(column: String, ascending: Bool) {
        guard let col = SortColumn(rawValue: column) else { return }
        sortColumn = col
        sortAscending = ascending
        allItems = Self.sortedItems(allItems, by: sortColumn, ascending: sortAscending)
        applySearch()
    }

    func clearExpiredIndicators() {
        changeIndicators.removeAll()
        for (_, timer) in indicatorTimers { timer.invalidate() }
        indicatorTimers.removeAll()
    }

    func copyCurrentPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentURL.path(percentEncoded: false), forType: .string)
    }

    func trashItems() {
        for url in selectedURLs {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        reload()
    }

    func renameItem(from oldURL: URL, to newName: String) -> Bool {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: newURL.path(percentEncoded: false)) {
            NSSound.beep()
            return false
        }
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            reload()
            selectedURLs = [newURL]
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    func newFolder() {
        let existingNames = Set(items.map(\.name))
        let name = Self.newFolderName(in: existingNames)
        let folderURL = currentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            reload()
            selectedURLs = [folderURL]
            pendingRenameURL = folderURL
        } catch {
            NSSound.beep()
        }
    }

    static func newFolderName(in existingNames: Set<String>) -> String {
        let baseName = "未命名文件夹"
        if !existingNames.contains(baseName) { return baseName }
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }

    func reload() {
        let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
        allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        applySearch()
        refreshChanges()
    }

    private func applySearch() {
        if searchQuery.isEmpty {
            items = allItems
        } else {
            items = allItems.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    static func filterItems(_ items: [FileItem], query: String) -> [FileItem] {
        if query.isEmpty { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    static func sortedItems(_ items: [FileItem], by column: SortColumn, ascending: Bool) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            switch column {
            case .name:
                let cmp = lhs.name.localizedStandardCompare(rhs.name)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case .date:
                guard let ld = lhs.modifiedDate else { return false }
                guard let rd = rhs.modifiedDate else { return true }
                return ascending ? ld < rd : ld > rd
            case .size:
                guard let ls = lhs.size else { return false }
                guard let rs = rhs.size else { return true }
                return ascending ? ls < rs : ls > rs
            case .kind:
                let cmp = lhs.kind.localizedStandardCompare(rhs.kind)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }

    private func refreshChanges() {
        let dir = currentURL.path(percentEncoded: false)
        let raw = (try? changeStore?.recentEvents(in: dir, limit: 200)) ?? []
        let filtered = raw.filter { !IgnoreRules.shouldIgnore(fileName: $0.fileName) }
        changes = Array(filtered.prefix(50))
        hiddenCount = raw.count - filtered.count
        versionedPaths = Set((try? versionStore?.pathsWithVersions(in: dir)) ?? [])
    }

    /// 由 `ContentView` 在终端 tab 活跃/cwd/增删变化时推送最新快照。
    func updateTerminalSnapshots(_ snapshots: [TerminalActivitySnapshot]) {
        snapshotsLock.lock()
        terminalSnapshots = snapshots
        snapshotsLock.unlock()
    }

    private func readTerminalSnapshots() -> [TerminalActivitySnapshot] {
        snapshotsLock.lock()
        defer { snapshotsLock.unlock() }
        return terminalSnapshots
    }

    private func handleFSEvents(_ events: [(path: String, type: ChangeEventType, snapshots: [TerminalActivitySnapshot])]) {
        let accepted = events.filter { event in
            let fileName = URL(fileURLWithPath: event.path).lastPathComponent
            return !IgnoreRules.shouldIgnore(fileName: fileName)
        }

        let changesEnabled = defaults.object(forKey: "changesEnabled") == nil
            ? true : defaults.bool(forKey: "changesEnabled")

        let dir = currentURL.path(percentEncoded: false)
        if changesEnabled {
            let batch = accepted.map { event -> (path: String, type: ChangeEventType, directory: String, terminalSessionID: UUID?) in
                let sessionID = TerminalAttribution.attribute(eventPath: event.path, snapshots: event.snapshots)
                return (path: event.path, type: event.type, directory: dir, terminalSessionID: sessionID)
            }
            try? changeStore?.recordBatch(batch)
        }

        for event in accepted where event.type == .added || event.type == .modified {
            snapshotIfEligible(path: event.path)
        }

        for event in accepted {
            guard event.type != .deleted else { continue }
            changeIndicators[event.path] = event.type
            indicatorTimers[event.path]?.invalidate()
            indicatorTimers[event.path] = Timer.scheduledTimer(
                withTimeInterval: 30, repeats: false
            ) { [weak self] _ in
                self?.changeIndicators.removeValue(forKey: event.path)
                self?.indicatorTimers.removeValue(forKey: event.path)
            }
        }

        reload()
    }

    private func snapshotIfEligible(path: String) {
        let url = URL(fileURLWithPath: path)
        guard VersionStore.isEligible(url: url),
              let content = try? Data(contentsOf: url) else { return }
        let hash = content.sha256Hex
        try? versionStore?.saveVersion(
            path: path,
            directory: currentURL.path(percentEncoded: false),
            content: content,
            hash: hash
        )
    }
}

