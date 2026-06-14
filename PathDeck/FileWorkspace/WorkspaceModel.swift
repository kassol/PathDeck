import Foundation
import Observation

@Observable
final class WorkspaceModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    private(set) var changes: [ChangeEvent] = []

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

    func reload() {
        items = (try? DirectoryLister.list(currentURL)) ?? []
        refreshChanges()
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
