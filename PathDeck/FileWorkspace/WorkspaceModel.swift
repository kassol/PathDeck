import Foundation
import Observation
import AppKit

enum SortColumn: String {
    case name, date, size, kind
}

enum PasteOperation {
    case copy, move
}

@Observable
final class WorkspaceModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []

    let outlineDataSource = OutlineDataSource()

    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false
    var selectedURLs: [URL] = []
    var pendingRenameURL: URL?
    /// 命令式选择信号：驱动 `FileTableView` 选中这组 URL 的行并滚动到首项（单项即长度 1），消费后置 nil。
    var revealSelection: [URL]?
    var isSearching: Bool = false
    var searchQuery: String = "" {
        didSet { applySearch() }
    }

    /// FSWatcher 事件命中的 dirty 目录集合（主线程设置，FileTableView 消费后清空）。
    var dirtyDirectories: Set<String>?

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

    init(root: URL, sortColumn: SortColumn = .name, sortAscending: Bool = true, showHidden: Bool = false) {
        self.currentURL = root
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
        self.showHidden = showHidden

        watcher = FSWatcher { [weak self] dirtyDirs in
            DispatchQueue.main.async {
                self?.handleFSEvents(dirtyDirs: dirtyDirs)
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
        let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
        allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        applySearch()
        outlineDataSource.sortColumn = sortColumn
        outlineDataSource.sortAscending = sortAscending
        outlineDataSource.showHidden = showHidden
        outlineDataSource.loadRoot(currentURL)
        syncWatcherExpandedDirs()
        watcher?.watch(directory: currentURL)
    }

    /// 导航到首项父目录并高亮选择集（跨目录 reveal / Open Selection，单项即长度 1）。
    func reveal(_ fileURLs: [URL]) {
        guard let first = fileURLs.first else { return }
        navigate(to: first.deletingLastPathComponent())
        let names = Set(fileURLs.map(\.lastPathComponent))
        let targets = items.filter { names.contains($0.name) }.map(\.url)
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

        outlineDataSource.sortColumn = col
        outlineDataSource.sortAscending = ascending
        outlineDataSource.resortAll()
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

    func pasteFiles(_ sourceURLs: [URL], operation: PasteOperation) {
        let fm = FileManager.default
        var newURLs: [URL] = []
        for source in sourceURLs {
            let dest = uniqueDestination(for: source.lastPathComponent, in: currentURL)
            do {
                switch operation {
                case .copy: try fm.copyItem(at: source, to: dest)
                case .move: try fm.moveItem(at: source, to: dest)
                }
                newURLs.append(dest)
            } catch {
                NSSound.beep()
            }
        }
        reload()
        if !newURLs.isEmpty {
            selectedURLs = newURLs
            revealSelection = newURLs
        }
    }

    func duplicateItems() {
        pasteFiles(selectedURLs, operation: .copy)
    }

    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let fm = FileManager.default

        let candidate = directory.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        let copyBase = "\(base) copy"
        let first = directory.appendingPathComponent("\(copyBase)\(suffix)")
        if !fm.fileExists(atPath: first.path(percentEncoded: false)) {
            return first
        }

        var n = 2
        while true {
            let url = directory.appendingPathComponent("\(copyBase) \(n)\(suffix)")
            if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
                return url
            }
            n += 1
        }
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

    static func newFolderName(in existingNames: Set<String>, baseName: String = String(localized: "untitled folder")) -> String {
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

        outlineDataSource.sortColumn = sortColumn
        outlineDataSource.sortAscending = sortAscending
        outlineDataSource.showHidden = showHidden
        outlineDataSource.refreshAll(currentURL)
        syncWatcherExpandedDirs()
    }

    func updateWatcherExpandedDirectories() {
        syncWatcherExpandedDirs()
    }

    private func syncWatcherExpandedDirs() {
        watcher?.setExpandedDirectories(outlineDataSource.expandedDirectoryURLs)
    }

    private func handleFSEvents(dirtyDirs: Set<String>) {
        let rootPath: String = {
            var p = currentURL.path(percentEncoded: false)
            if p.hasSuffix("/") && p.count > 1 { p = String(p.dropLast()) }
            return p
        }()

        if dirtyDirs.contains(rootPath) {
            let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
            allItems = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
            applySearch()
            outlineDataSource.refreshRoot(currentURL)
        }

        for dirPath in dirtyDirs where dirPath != rootPath {
            let url = URL(fileURLWithPath: dirPath)
            _ = outlineDataSource.reloadChildren(for: url)
        }

        syncWatcherExpandedDirs()
        dirtyDirectories = dirtyDirs
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
}
