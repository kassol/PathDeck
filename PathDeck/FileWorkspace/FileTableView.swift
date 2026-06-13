//
//  FileTableView.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import AppKit
import SwiftUI

/// 文件列表视图：SwiftUI 中嵌入 AppKit `NSTableView`。
/// 选用 NSTableView 而非 SwiftUI Table，见 FileWorkspace/AGENTS.md。
struct FileTableView: NSViewRepresentable {
    var items: [FileItem]
    var onOpen: (FileItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, onOpen: onOpen)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 22
        tableView.style = .inset
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let columns: [(id: String, title: String, width: CGFloat)] = [
            (Coordinator.nameColumn, "名称", 280),
            (Coordinator.dateColumn, "修改日期", 170),
            (Coordinator.sizeColumn, "大小", 90),
            (Coordinator.kindColumn, "类型", 150),
        ]
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            tableView.addTableColumn(column)
        }

        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.items = items
        context.coordinator.onOpen = onOpen
        (nsView.documentView as? NSTableView)?.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let nameColumn = "name"
        static let dateColumn = "date"
        static let sizeColumn = "size"
        static let kindColumn = "kind"

        var items: [FileItem]
        var onOpen: (FileItem) -> Void
        weak var tableView: NSTableView?

        private let sizeFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        init(items: [FileItem], onOpen: @escaping (FileItem) -> Void) {
            self.items = items
            self.onOpen = onOpen
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < items.count, let columnId = tableColumn?.identifier.rawValue else { return nil }
            let item = items[row]
            let reuseId = NSUserInterfaceItemIdentifier("cell.\(columnId)")
            let cell = (tableView.makeView(withIdentifier: reuseId, owner: self) as? NSTableCellView)
                ?? Self.makeCell(id: reuseId, withIcon: columnId == Self.nameColumn)

            switch columnId {
            case Self.nameColumn:
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
                cell.textField?.stringValue = item.name
            case Self.dateColumn:
                cell.textField?.stringValue = item.modifiedDate.map { dateFormatter.string(from: $0) } ?? "--"
            case Self.sizeColumn:
                cell.textField?.stringValue = item.size.map { sizeFormatter.string(fromByteCount: $0) } ?? "--"
            case Self.kindColumn:
                cell.textField?.stringValue = item.kind.isEmpty ? "--" : item.kind
            default:
                break
            }
            return cell
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < items.count else { return }
            onOpen(items[row])
        }

        private static func makeCell(id: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = textField
            cell.addSubview(textField)

            if withIcon {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = imageView
                cell.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            return cell
        }
    }
}
