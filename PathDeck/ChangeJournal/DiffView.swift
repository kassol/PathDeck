import SwiftUI

struct DiffView: View {
    let path: String
    let versionStore: VersionStore
    var onClose: () -> Void
    var onRestored: (() -> Void)?

    @State private var diffLines: [DiffLine] = []
    @State private var snapshotVersion: FileVersion?
    @State private var snapshotContent: Data?
    @State private var errorMessage: String?
    @State private var showRestoreConfirm = false
    @State private var restoreError: String?
    @State private var isExternallyDirty = false

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffLines.isEmpty && snapshotVersion != nil {
                Text("无差异")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                diffContent
            }
        }
        .task(id: path) { loadDiff() }
        .alert("恢复上一版", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") { performRestore() }
        } message: {
            if let version = snapshotVersion {
                Text(restoreMessage(for: version))
            }
        }
        .alert("恢复失败", isPresented: .init(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("确定") { restoreError = nil }
        } message: {
            if let restoreError {
                Text(restoreError)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text("— 比较上一版")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if snapshotVersion != nil && errorMessage == nil {
                Button {
                    showRestoreConfirm = true
                } label: {
                    Label("恢复上一版", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var diffContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(diffLines) { line in
                    DiffLineRow(line: line)
                }
            }
        }
    }

    private func loadDiff() {
        diffLines = []
        snapshotVersion = nil
        snapshotContent = nil
        errorMessage = nil
        isExternallyDirty = false

        guard FileManager.default.fileExists(atPath: path),
              let currentData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let currentText = String(data: currentData, encoding: .utf8) else {
            errorMessage = "无法读取当前文件"
            return
        }

        let currentHash = currentData.sha256Hex
        let latest = try? versionStore.latestVersionWithContent(for: path)
        let previous = try? versionStore.previousVersionWithContent(for: path, excludingHash: currentHash)
        let selection = VersionStore.selectBaseline(latest: latest, previous: previous, currentHash: currentHash)
        isExternallyDirty = selection.isExternallyDirty

        guard let (version, oldData) = selection.baseline else {
            errorMessage = "当前内容尚未建立版本基线"
            return
        }
        snapshotVersion = version
        snapshotContent = oldData

        let oldText = String(data: oldData, encoding: .utf8) ?? ""

        let lines = DiffEngine.diff(old: oldText, new: currentText)
        if lines.count > 5000 {
            diffLines = Array(lines.prefix(5000))
        } else {
            diffLines = lines
        }
    }

    private func restoreMessage(for version: FileVersion) -> String {
        let base = "将 \(fileName) 恢复到 \(version.createdAt.formatted(date: .abbreviated, time: .shortened)) 的版本？"
        if isExternallyDirty {
            return base + "\n当前未保存的改动会先被快照，可随后恢复。"
        }
        return base
    }

    private func performRestore() {
        guard let snapshotContent else { return }
        do {
            try FileRestore.restore(store: versionStore, path: path, snapshotContent: snapshotContent)
            onRestored?()
        } catch {
            restoreError = error.localizedDescription
        }
    }
}

// MARK: - Diff Line Row

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(lineNumberText(line.oldLineNumber))
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(lineNumberText(line.newLineNumber))
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.tertiary)

            Text(prefix)
                .frame(width: 16, alignment: .center)
                .foregroundStyle(prefixColor)

            Text(line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.type {
        case .added: "+"
        case .deleted: "−"
        case .unchanged: " "
        }
    }

    private var prefixColor: Color {
        switch line.type {
        case .added: .green
        case .deleted: .red
        case .unchanged: .secondary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: Color(red: 48/255, green: 209/255, blue: 88/255).opacity(0.13)
        case .deleted: Color(red: 255/255, green: 69/255, blue: 58/255).opacity(0.13)
        case .unchanged: .clear
        }
    }

    private func lineNumberText(_ num: Int?) -> String {
        guard let num else { return "" }
        return String(num)
    }
}
