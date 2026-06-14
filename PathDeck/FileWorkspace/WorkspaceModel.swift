import Foundation
import Observation
import AppKit

enum SortColumn: String {
    case name, date, size, kind
}

@Observable
final class WorkspaceModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var changes: [ChangeEvent] = []

    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false

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

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser) {
        currentURL = root

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
        currentURL = item.url
        reload()
        watcher?.watch(directory: currentURL)
    }

    func goUp() {
        guard currentURL.path(percentEncoded: false) != "/" else { return }
        currentURL = currentURL.deletingLastPathComponent().standardizedFileURL
        reload()
        watcher?.watch(directory: currentURL)
    }

    func navigate(to url: URL) {
        currentURL = url.standardizedFileURL
        reload()
        watcher?.watch(directory: currentURL)
    }

    func toggleHidden() {
        showHidden.toggle()
        reload()
    }

    func applySort(column: String, ascending: Bool) {
        guard let col = SortColumn(rawValue: column) else { return }
        sortColumn = col
        sortAscending = ascending
        items = Self.sortedItems(items, by: sortColumn, ascending: sortAscending)
    }

    func copyCurrentPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentURL.path(percentEncoded: false), forType: .string)
    }

    func reload() {
        let rawItems = (try? DirectoryLister.list(currentURL, includeHidden: showHidden)) ?? []
        items = Self.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        refreshChanges()
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
        reload()
    }
}

