import SwiftUI
import UniformTypeIdentifiers
import AppKit

@Observable
final class PinnedFolders {
    static let shared = PinnedFolders()

    private let key = "pinnedFolders"
    private(set) var items: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !items.contains(where: { $0.standardizedFileURL == standardized }) else { return }
        items.append(standardized)
        persist()
    }

    func remove(_ url: URL) {
        let standardized = url.standardizedFileURL
        items.removeAll { $0.standardizedFileURL == standardized }
        persist()
    }

    func contains(_ url: URL) -> Bool {
        items.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    private func persist() {
        UserDefaults.standard.set(items.map { $0.path(percentEncoded: false) }, forKey: key)
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
                            Button("从侧栏移除") {
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
