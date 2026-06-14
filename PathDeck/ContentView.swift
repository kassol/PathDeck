import SwiftUI

struct ContentView: View {
    @State private var model = WorkspaceModel()

    var body: some View {
        VStack(spacing: 0) {
            FileTableView(items: model.items, onOpen: { model.enter($0) })

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
        .navigationSubtitle((model.currentURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.goUp() } label: {
                    Image(systemName: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("返回上级")
            }
        }
    }
}
