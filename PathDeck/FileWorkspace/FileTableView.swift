import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct FileTableView: NSViewRepresentable {
    var items: [FileItem]
    var pendingRenameURL: URL?
    var changeIndicators: [String: ChangeEventType]
    /// 命令式选择信号：选中这组 URL 对应的行并滚动到首项（单项即长度 1）。消费后由 `onClearRevealSelection` 清空。
    var revealSelection: [URL]?
    var onOpen: (FileItem) -> Void
    var onSort: (String, Bool) -> Void
    var onSelectionChange: ([FileItem]) -> Void
    var onTrash: () -> Void
    var onRename: (URL, String) -> Bool
    var onNewFolder: () -> Void
    var onClearPendingRename: () -> Void
    var onClearRevealSelection: () -> Void
    var onSendPathToTerminal: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileNSTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 22
        tableView.style = .inset
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        let coordinator = context.coordinator
        tableView.onReturnKey = { [weak coordinator] row in
            coordinator?.beginRename(row: row)
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        menu.autoenablesItems = false
        tableView.menu = menu

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
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            tableView.addTableColumn(column)
        }

        tableView.sortDescriptors = [NSSortDescriptor(key: Coordinator.nameColumn, ascending: true)]
        tableView.setAccessibilityIdentifier("fileTable")
        tableView.coordinator = context.coordinator
        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let itemsChanged = coord.items != items
        let indicatorsChanged = coord.changeIndicators != changeIndicators
        coord.items = items
        coord.changeIndicators = changeIndicators
        coord.onOpen = onOpen
        coord.onSort = onSort
        coord.onSelectionChange = onSelectionChange
        coord.onTrash = onTrash
        coord.onRename = onRename
        coord.onNewFolder = onNewFolder
        coord.onSendPathToTerminal = onSendPathToTerminal

        guard let tv = nsView.documentView as? NSTableView else { return }
        if coord.editingRow < 0, itemsChanged || indicatorsChanged {
            tv.reloadData()
        }

        if let pendingURL = pendingRenameURL {
            let itemsSnapshot = items
            let clearPending = onClearPendingRename
            DispatchQueue.main.async {
                if let row = itemsSnapshot.firstIndex(where: { $0.url == pendingURL }) {
                    tv.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    tv.scrollRowToVisible(row)
                    coord.beginRename(row: row)
                }
                clearPending()
            }
        }

        if let targets = revealSelection, !targets.isEmpty {
            let itemsSnapshot = items
            let clearReveal = onClearRevealSelection
            DispatchQueue.main.async {
                let rows = IndexSet(targets.compactMap { url in
                    itemsSnapshot.firstIndex(where: { $0.url == url })
                })
                if !rows.isEmpty {
                    tv.selectRowIndexes(rows, byExtendingSelection: false)
                    if let firstRow = itemsSnapshot.firstIndex(where: { $0.url == targets[0] }) {
                        tv.scrollRowToVisible(firstRow)
                    }
                    tv.window?.makeFirstResponder(tv)
                }
                clearReveal()
            }
        }
    }

    // MARK: - Custom NSTableView for key events + Quick Look ownership

    final class FileNSTableView: NSTableView {
        var onReturnKey: ((Int) -> Void)?
        weak var coordinator: Coordinator?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, selectedRow >= 0 {
                onReturnKey?(selectedRow)
            } else if event.keyCode == 49 {
                if QLPreviewPanel.sharedPreviewPanelExists(),
                   let panel = QLPreviewPanel.shared(), panel.isVisible {
                    panel.orderOut(nil)
                } else {
                    QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
            true
        }

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = coordinator
            panel.delegate = coordinator
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             NSMenuDelegate, NSTextFieldDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        static let nameColumn = "name"
        static let dateColumn = "date"
        static let sizeColumn = "size"
        static let kindColumn = "kind"

        var items: [FileItem]
        var changeIndicators: [String: ChangeEventType]
        var onOpen: (FileItem) -> Void
        var onSort: (String, Bool) -> Void
        var onSelectionChange: ([FileItem]) -> Void
        var onTrash: () -> Void
        var onRename: (URL, String) -> Bool
        var onNewFolder: () -> Void
        var onSendPathToTerminal: ([URL]) -> Void
        weak var tableView: NSTableView?

        var editingRow: Int = -1

        private static let dotIdentifier = NSUserInterfaceItemIdentifier("changeDot")

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

        init(parent: FileTableView) {
            self.items = parent.items
            self.changeIndicators = parent.changeIndicators
            self.onOpen = parent.onOpen
            self.onSort = parent.onSort
            self.onSelectionChange = parent.onSelectionChange
            self.onTrash = parent.onTrash
            self.onRename = parent.onRename
            self.onNewFolder = parent.onNewFolder
            self.onSendPathToTerminal = parent.onSendPathToTerminal
        }

        // MARK: - DataSource

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < items.count else { return nil }
            return items[row].url as NSURL
        }

        // MARK: - Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                        row: Int) -> NSView? {
            guard row < items.count,
                  let columnId = tableColumn?.identifier.rawValue else { return nil }
            let item = items[row]
            let isName = columnId == Self.nameColumn
            let reuseId = NSUserInterfaceItemIdentifier("cell.\(columnId)")
            let cell = (tableView.makeView(withIdentifier: reuseId, owner: self)
                            as? NSTableCellView)
                ?? Self.makeCell(id: reuseId, withIcon: isName)

            if isName {
                cell.textField?.delegate = self
            }

            switch columnId {
            case Self.nameColumn:
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
                cell.textField?.stringValue = item.name
                let dot = cell.subviews.first {
                    $0.accessibilityIdentifier() == Self.dotIdentifier.rawValue
                }
                let path = item.url.path(percentEncoded: false)
                if let indicatorType = changeIndicators[path] {
                    dot?.isHidden = false
                    dot?.layer?.backgroundColor = indicatorType.nsColor.cgColor
                } else {
                    dot?.isHidden = true
                }
            case Self.dateColumn:
                cell.textField?.stringValue =
                    item.modifiedDate.map { dateFormatter.string(from: $0) } ?? "--"
            case Self.sizeColumn:
                cell.textField?.stringValue =
                    item.size.map { sizeFormatter.string(fromByteCount: $0) } ?? "--"
            case Self.kindColumn:
                cell.textField?.stringValue = item.kind.isEmpty ? "--" : item.kind
            default:
                break
            }
            return cell
        }

        func tableView(_ tableView: NSTableView,
                        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else { return }
            onSort(key, descriptor.ascending)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = tableView else { return }
            let selected = tv.selectedRowIndexes.compactMap { row -> FileItem? in
                row < items.count ? items[row] : nil
            }
            onSelectionChange(selected)

            if QLPreviewPanel.sharedPreviewPanelExists(),
               let panel = QLPreviewPanel.shared(), panel.isVisible {
                panel.reloadData()
            }
        }

        // MARK: - Double Click

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < items.count else { return }
            let item = items[row]
            if item.isDirectory {
                onOpen(item)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }

        // MARK: - Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tv = tableView else { return }
            let clickedRow = tv.clickedRow

            if clickedRow < 0 {
                tv.deselectAll(nil)
                addMenuItem(to: menu, title: "新建文件夹", action: #selector(menuNewFolder(_:)))
                return
            }

            guard clickedRow < items.count else { return }

            if !tv.selectedRowIndexes.contains(clickedRow) {
                tv.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }

            let isMultiple = tv.selectedRowIndexes.count > 1
            let item = items[clickedRow]

            if !isMultiple && item.isDirectory {
                addMenuItem(to: menu, title: "进入文件夹", action: #selector(menuOpen(_:)))
            } else {
                addMenuItem(to: menu, title: "打开", action: #selector(menuOpen(_:)))
            }
            addMenuItem(to: menu, title: "用其他应用打开…", action: #selector(menuOpenWith(_:)))

            menu.addItem(.separator())

            let renameItem = addMenuItem(to: menu, title: "重命名",
                                         action: #selector(menuRename(_:)))
            if isMultiple { renameItem.isEnabled = false }

            addMenuItem(to: menu, title: "移到废纸篓", action: #selector(menuTrash(_:)))

            menu.addItem(.separator())

            addMenuItem(to: menu, title: "在 Finder 中显示",
                        action: #selector(menuRevealInFinder(_:)))
            addMenuItem(to: menu, title: "复制路径", action: #selector(menuCopyPath(_:)))
            addMenuItem(to: menu, title: "发送路径到终端",
                        action: #selector(menuSendPathToTerminal(_:)))

            menu.addItem(.separator())

            addMenuItem(to: menu, title: "新建文件夹", action: #selector(menuNewFolder(_:)))
        }

        @discardableResult
        private func addMenuItem(to menu: NSMenu, title: String,
                                 action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        // MARK: - Menu Actions

        @objc private func menuOpen(_ sender: Any?) {
            guard let tv = tableView else { return }
            if tv.selectedRowIndexes.count <= 1 {
                let row = tv.clickedRow
                guard row >= 0, row < items.count else { return }
                let item = items[row]
                if item.isDirectory {
                    onOpen(item)
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            } else {
                for idx in tv.selectedRowIndexes {
                    guard idx < items.count else { continue }
                    NSWorkspace.shared.open(items[idx].url)
                }
            }
        }

        @objc private func menuOpenWith(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.begin { response in
                guard response == .OK, let appURL = panel.url else { return }
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
            }
        }

        @objc private func menuTrash(_ sender: Any?) { onTrash() }

        @objc private func menuRename(_ sender: Any?) {
            guard let tv = tableView, tv.selectedRow >= 0 else { return }
            beginRename(row: tv.selectedRow)
        }

        @objc private func menuRevealInFinder(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }

        @objc private func menuCopyPath(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            NSPasteboard.general.clearContents()
            let paths = urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            NSPasteboard.general.setString(paths, forType: .string)
        }

        @objc private func menuNewFolder(_ sender: Any?) { onNewFolder() }

        @objc private func menuSendPathToTerminal(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            onSendPathToTerminal(urls)
        }

        private func selectedURLs() -> [URL] {
            guard let tv = tableView else { return [] }
            return tv.selectedRowIndexes.compactMap { idx in
                idx < items.count ? items[idx].url : nil
            }
        }

        // MARK: - Inline Editing

        func beginRename(row: Int) {
            guard let tv = tableView, row >= 0, row < items.count else { return }
            tv.scrollRowToVisible(row)
            let nameColIndex = tv.column(
                withIdentifier: NSUserInterfaceItemIdentifier(Self.nameColumn))
            guard nameColIndex >= 0,
                  let cellView = tv.view(atColumn: nameColIndex, row: row,
                                         makeIfNecessary: true) as? NSTableCellView,
                  let textField = cellView.textField else { return }
            editingRow = row
            textField.isEditable = true
            textField.isSelectable = true
            tv.window?.makeFirstResponder(textField)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if editingRow >= 0, editingRow < items.count {
                    (control as? NSTextField)?.stringValue = items[editingRow].name
                }
                (control as? NSTextField)?.isEditable = false
                (control as? NSTextField)?.isSelectable = false
                editingRow = -1
                tableView?.window?.makeFirstResponder(tableView)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            textField.isEditable = false
            textField.isSelectable = false

            guard editingRow >= 0, editingRow < items.count else {
                editingRow = -1
                return
            }

            let oldItem = items[editingRow]
            editingRow = -1

            if newName.isEmpty || newName == oldItem.name {
                textField.stringValue = oldItem.name
                return
            }

            if !onRename(oldItem.url, newName) {
                textField.stringValue = oldItem.name
            }
        }

        // MARK: - Quick Look

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            selectedURLs().count
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            let urls = selectedURLs()
            guard index < urls.count else { return nil }
            return urls[index] as NSURL
        }

        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard event.type == .keyDown else { return false }
            let kc = event.keyCode
            if kc == 49 {
                panel.orderOut(nil)
                return true
            }
            if kc == 126 || kc == 125 {
                tableView?.keyDown(with: event)
                return true
            }
            return false
        }

        func previewPanel(_ panel: QLPreviewPanel!,
                          sourceFrameOnScreenFor item: any QLPreviewItem) -> NSRect {
            guard let tv = tableView,
                  let url = (item as? NSURL) as URL?,
                  let row = items.firstIndex(where: { $0.url == url }) else { return .zero }
            let nameColIndex = tv.column(
                withIdentifier: NSUserInterfaceItemIdentifier(Self.nameColumn))
            guard nameColIndex >= 0 else { return .zero }
            let cellRect = tv.frameOfCell(atColumn: nameColIndex, row: row)
            let windowRect = tv.convert(cellRect, to: nil)
            return tv.window?.convertToScreen(windowRect) ?? .zero
        }

        // MARK: - Cell Factory

        private static func makeCell(id: NSUserInterfaceItemIdentifier,
                                     withIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = textField
            cell.addSubview(textField)

            if withIcon {
                let dot = NSView()
                dot.translatesAutoresizingMaskIntoConstraints = false
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.setAccessibilityIdentifier(dotIdentifier.rawValue)
                dot.isHidden = true
                cell.addSubview(dot)

                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = imageView
                cell.addSubview(imageView)
                NSLayoutConstraint.activate([
                    dot.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    dot.widthAnchor.constraint(equalToConstant: 6),
                    dot.heightAnchor.constraint(equalToConstant: 6),
                    imageView.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor,
                                                       constant: 4),
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
