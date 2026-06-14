import Foundation
import Observation
import AppKit

enum SortColumn: String {
    case name, date, size, kind
}

@Observable
final class WorkspaceModel {
    private static let lastFolderKey = "lastOpenedFolder"

    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []
    private(set) var changes: [ChangeEvent] = []
    private(set) var changeIndicators: [String: ChangeEventType] = [:]

    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false
    var selectedURLs: [URL] = []
    var pendingRenameURL: URL?
    var scrollToURL: URL?
    var isSearching: Bool = false
    var isTerminalVisible: Bool = false
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

    private var watcher: FSWatcher?
    private var changeStore: ChangeStore?
    private var indicatorTimers: [String: Timer] = [:]

    init(root: URL? = nil) {
        if let root {
            currentURL = root
        } else if let saved = UserDefaults.standard.string(forKey: Self.lastFolderKey) {
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

        do {
            changeStore = try ChangeStore()
        } catch {
            NSLog("[PathDeck] ChangeStore init failed: \(error)")
        }

        watcher = FSWatcher { [weak self] events in
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
        UserDefaults.standard.set(currentURL.path(percentEncoded: false), forKey: Self.lastFolderKey)
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
        changes = (try? changeStore?.recentEvents(in: dir)) ?? []
    }

    private func handleFSEvents(_ events: [(path: String, type: ChangeEventType)]) {
        let dir = currentURL.path(percentEncoded: false)
        let batch = events.map { (path: $0.path, type: $0.type, directory: dir) }
        try? changeStore?.recordBatch(batch)

        for event in events {
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
}

