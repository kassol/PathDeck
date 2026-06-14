import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var workspaceModel: WorkspaceModel?
}

struct ContentView: View {
    @State private var model = WorkspaceModel()

    var body: some View {
        VStack(spacing: 0) {
            PathBarView(segments: model.pathSegments) { url in
                model.navigate(to: url)
            }

            if model.isSearching {
                Divider()
                SearchBarView(
                    query: Binding(
                        get: { model.searchQuery },
                        set: { model.searchQuery = $0 }
                    ),
                    onDismiss: {
                        model.isSearching = false
                        model.searchQuery = ""
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
            }

            Divider()

            FileTableView(
                items: model.items,
                pendingRenameURL: model.pendingRenameURL,
                onOpen: { model.enter($0) },
                onSort: { column, ascending in
                    model.applySort(column: column, ascending: ascending)
                },
                onSelectionChange: { items in
                    model.selectedURLs = items.map(\.url)
                },
                onTrash: { model.trashItems() },
                onRename: { model.renameItem(from: $0, to: $1) },
                onNewFolder: { model.newFolder() },
                onClearPendingRename: { model.pendingRenameURL = nil }
            )

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近变化")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.changes.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                ChangeListView(events: model.changes)
            }
            .frame(height: 180)
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(model.currentURL.lastPathComponent)
        .navigationSubtitle(
            (model.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.goUp() } label: {
                    Image(systemName: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("返回上级")
            }
        }
        .focusedSceneValue(\.workspaceModel, model)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                DispatchQueue.main.async {
                    model.navigate(to: url)
                    RecentFolders.shared.add(url)
                }
            }
            return true
        }
    }
}

// MARK: - Path Bar

private struct PathBarView: View {
    var segments: [(name: String, url: URL)]
    var onNavigate: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                    Button {
                        onNavigate(segment.url)
                    } label: {
                        Text(segment.name)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                index == segments.count - 1 ? .primary : .secondary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(height: 24)
        .background(.bar)
        .accessibilityIdentifier("pathBar")
    }
}
