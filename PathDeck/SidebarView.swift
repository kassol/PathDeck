import SwiftUI
import UniformTypeIdentifiers
import AppKit

@Observable
final class PinnedFolders {
    static let shared = PinnedFolders()

    private let bookmarkKey = "pinnedFolderBookmarks"
    private let legacyKey = "pinnedFolders"
    private(set) var items: [URL] = []
    private var bookmarks: [Data] = []

    private init() {
        if let stored = UserDefaults.standard.array(forKey: bookmarkKey) as? [Data] {
            loadFromBookmarks(stored)
        } else if let paths = UserDefaults.standard.stringArray(forKey: legacyKey) {
            migrateLegacy(paths)
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

    func contains(_ url: URL) -> Bool {
        items.contains { $0.standardizedFileURL == url.standardizedFileURL }
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
        UserDefaults.standard.removeObject(forKey: legacyKey)
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
        UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
    }
}

struct SidebarView: View {
    var currentURL: URL
    var onNavigate: (URL) -> Void
    @State private var pinnedFolders = PinnedFolders.shared

    private static let favorites: [(name: String, icon: String, url: URL)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Desktop", "menubar.dock.rectangle", home.appending(path: "Desktop")),
            ("Documents", "doc", home.appending(path: "Documents")),
            ("Downloads", "arrow.down.circle", home.appending(path: "Downloads")),
            (NSUserName(), "house", home),
            ("Applications", "menubar.rectangle", URL(fileURLWithPath: "/Applications")),
        ]
    }()

    var body: some View {
        List(selection: Binding(
            get: { currentURL.standardizedFileURL },
            set: { if let url = $0 { onNavigate(url) } }
        )) {
            Section("Favorites") {
                ForEach(Self.favorites, id: \.url) { item in
                    Label(item.name, systemImage: item.icon)
                        .tag(item.url.standardizedFileURL)
                }
            }

            if !pinnedFolders.items.isEmpty {
                Section("Pinned") {
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
                }
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
