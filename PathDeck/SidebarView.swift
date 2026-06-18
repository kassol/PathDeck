import SwiftUI
import UniformTypeIdentifiers
import AppKit

@Observable
final class PinnedFolders {
    static let shared = PinnedFolders(userDefaults: .standard)

    private let bookmarkKey = "pinnedFolderBookmarks"
    private let legacyKey = "pinnedFolders"
    private let defaults: UserDefaults
    private(set) var items: [URL] = []
    private var bookmarks: [Data] = []

    // 测试入口，业务侧请用 shared
    init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
        if defaults.object(forKey: bookmarkKey) != nil {
            if let stored = defaults.array(forKey: bookmarkKey) as? [Data] {
                loadFromBookmarks(stored)
            }
        } else if let paths = defaults.stringArray(forKey: legacyKey) {
            migrateLegacy(paths)
        } else {
            seedDefaults()
        }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !items.contains(where: { $0.standardizedFileURL == standardized }) else { return }
        guard let data = createBookmark(for: standardized) else { return }
        items.append(standardized)
        bookmarks.append(data)
        persist()
    }

    func remove(_ url: URL) {
        let standardized = url.standardizedFileURL
        if let idx = items.firstIndex(where: { $0.standardizedFileURL == standardized }) {
            items.remove(at: idx)
            bookmarks.remove(at: idx)
            persist()
        }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        let sorted = offsets.sorted()
        var nextItems = items
        var nextBookmarks = bookmarks
        var extractedItems: [URL] = []
        var extractedBookmarks: [Data] = []
        for idx in sorted.reversed() {
            guard nextItems.indices.contains(idx) else { continue }
            extractedItems.insert(nextItems.remove(at: idx), at: 0)
            extractedBookmarks.insert(nextBookmarks.remove(at: idx), at: 0)
        }
        let shifts = sorted.filter { $0 < destination }.count
        let insertAt = max(0, min(destination - shifts, nextItems.count))
        nextItems.insert(contentsOf: extractedItems, at: insertAt)
        nextBookmarks.insert(contentsOf: extractedBookmarks, at: insertAt)
        if nextItems != items {
            items = nextItems
            bookmarks = nextBookmarks
            persist()
        }
    }

    func contains(_ url: URL) -> Bool {
        items.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    private func seedDefaults() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            home.appending(path: "Desktop"),
            home.appending(path: "Documents"),
            home.appending(path: "Downloads"),
            home,
            URL(fileURLWithPath: "/Applications"),
        ]
        for url in candidates {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path(percentEncoded: false)),
                  let data = createBookmark(for: standardized) else { continue }
            items.append(standardized)
            bookmarks.append(data)
        }
        persist()
    }

    private func loadFromBookmarks(_ stored: [Data]) {
        var resolvedURLs: [URL] = []
        var resolvedBookmarks: [Data] = []
        for data in stored {
            guard let (url, refreshed) = resolveBookmark(data) else { continue }
            resolvedURLs.append(url)
            resolvedBookmarks.append(refreshed ?? data)
        }
        items = resolvedURLs
        bookmarks = resolvedBookmarks
        if stored.count != resolvedBookmarks.count || zip(stored, resolvedBookmarks).contains(where: { $0 != $1 }) {
            persist()
        }
    }

    private func migrateLegacy(_ paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                  let data = createBookmark(for: url) else { continue }
            items.append(url)
            bookmarks.append(data)
        }
        persist()
        defaults.removeObject(forKey: legacyKey)
    }

    private func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveBookmark(_ data: Data) -> (URL, Data?)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let refreshed = isStale ? createBookmark(for: url) : nil
        return (url.standardizedFileURL, refreshed)
    }

    private func persist() {
        defaults.set(bookmarks, forKey: bookmarkKey)
    }
}

struct SidebarView: View {
    var currentURL: URL
    var onNavigate: (URL) -> Void
    @State private var pinnedFolders = PinnedFolders.shared

    var body: some View {
        List(selection: Binding(
            get: { currentURL.standardizedFileURL },
            set: { if let url = $0 { onNavigate(url) } }
        )) {
            Section("Favorites") {
                ForEach(pinnedFolders.items, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    }
                    .tag(url.standardizedFileURL)
                    .contextMenu {
                        Button("Remove from Sidebar") {
                            pinnedFolders.remove(url)
                        }
                    }
                }
                .onMove { from, to in pinnedFolders.move(from: from, to: to) }
            }
        }
        .listStyle(.sidebar)
        .onDrop(of: [UTType.fileURL], delegate: SidebarDropDelegate(pinnedFolders: pinnedFolders))
    }
}

private struct SidebarDropDelegate: DropDelegate {
    let pinnedFolders: PinnedFolders

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.folder])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            DispatchQueue.main.async { pinnedFolders.add(url) }
        }
        return true
    }
}
