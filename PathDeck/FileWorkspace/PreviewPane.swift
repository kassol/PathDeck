import SwiftUI
import QuickLookThumbnailing
import AppKit

struct PreviewPane: View {
    let selectedURLs: [URL]
    let currentDirectory: URL
    var onSendPath: (([URL]) -> Void)?

    var body: some View {
        Group {
            if let url = selectedURLs.first {
                if selectedURLs.count > 1 {
                    multiSelectionView(count: selectedURLs.count)
                } else {
                    singleFileView(url: url)
                }
            } else {
                folderSummaryView
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
    }

    // MARK: - Single File

    private func singleFileView(url: URL) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ThumbnailView(url: url)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

                VStack(alignment: .leading, spacing: 12) {
                    fileNameSection(url: url)
                    Divider()
                    metadataSection(url: url)
                    Divider()
                    actionsSection(url: url)
                }
                .padding(12)
            }
        }
    }

    private func fileNameSection(url: URL) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(fileKind(for: url))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func metadataSection(url: URL) -> some View {
        let attrs = fileAttributes(for: url)
        VStack(spacing: 6) {
            MetadataRow(label: "Kind", value: fileKind(for: url))
            if let size = attrs.size {
                MetadataRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            MetadataRow(label: "Where", value: relativePath(for: url))
            if let created = attrs.created {
                MetadataRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            if let modified = attrs.modified {
                MetadataRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func actionsSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick Actions")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ActionButton(title: "Send Path to Terminal", icon: "terminal") {
                onSendPath?([url])
            }
            ActionButton(title: "Copy Path", icon: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
            }
        }
    }

    // MARK: - Multi Selection

    private func multiSelectionView(count: Int) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("\(count) items selected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Folder Summary

    private var folderSummaryView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(nsImage: NSWorkspace.shared.icon(forFile: currentDirectory.path(percentEncoded: false)))
                .resizable()
                .frame(width: 48, height: 48)
            Text(currentDirectory.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
            if let summary = folderSummary() {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    // MARK: - Helpers

    private struct FileAttrs {
        var size: Int64?
        var created: Date?
        var modified: Date?
    }

    private func fileAttributes(for url: URL) -> FileAttrs {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ) else { return FileAttrs() }
        return FileAttrs(
            size: attrs[.size] as? Int64,
            created: attrs[.creationDate] as? Date,
            modified: attrs[.modificationDate] as? Date
        )
    }

    private func fileKind(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey])
        return values?.localizedTypeDescription ?? "Document"
    }

    private func relativePath(for url: URL) -> String {
        let full = url.deletingLastPathComponent().path(percentEncoded: false)
        let base = currentDirectory.path(percentEncoded: false)
        if full == base { return "." }
        if full.hasPrefix(base) {
            return String(full.dropFirst(base.count + 1))
        }
        return (full as NSString).abbreviatingWithTildeInPath
    }

    private func folderSummary() -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            atPath: currentDirectory.path(percentEncoded: false)
        ) else { return nil }
        let visible = contents.filter { !$0.hasPrefix(".") }
        return "\(visible.count) items"
    }
}

// MARK: - Subviews

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .font(.system(size: 11))
                .lineLimit(2)
                .padding(.leading, 8)
            Spacer(minLength: 0)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }
        }
        .task(id: url) {
            image = nil
            image = await generateThumbnail(for: url)
        }
    }

    private func generateThumbnail(for url: URL) async -> NSImage? {
        let size = CGSize(width: 480, height: 360)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        return representation.nsImage
    }
}
