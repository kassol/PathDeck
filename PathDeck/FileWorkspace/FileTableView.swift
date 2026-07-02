import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct FileTableView: NSViewRepresentable {
    var items: [FileItem]
    var outlineDataSource: OutlineDataSource
    var isSearching: Bool
    /// FSWatcher dirty 信号，非 nil 时触发精确 reload。
    var dirtyDirectories: Set<String>?
    var pendingRenameURL: URL?
    var revealSelection: [URL]?
    var onOpen: (FileItem) -> Void
    var onSort: (String, Bool) -> Void
    var onSelectionChange: ([FileItem]) -> Void
    var onTrash: () -> Void
    var onRename: (URL, String) -> Bool
    var onNewFolder: () -> Void
    var onClearPendingRename: () -> Void
    var onClearRevealSelection: () -> Void
    var onClearDirtyDirectories: () -> Void
    var onSendPathToTerminal: ([URL]) -> Void
    var onExpandCollapse: () -> Void
    var onPasteFiles: ([URL], PasteOperation) -> Void
    var onDuplicate: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = FileNSOutlineView()
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsMultipleSelection = true
        outlineView.rowHeight = 22
        outlineView.style = .inset
        outlineView.indentationPerLevel = 16
        outlineView.autosaveExpandedItems = false
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        let coordinator = context.coordinator
        outlineView.onReturnKey = { [weak coordinator] row in
            coordinator?.beginRename(row: row)
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        menu.autoenablesItems = false
        outlineView.menu = menu

        let columns: [(id: String, title: String, width: CGFloat, minWidth: CGFloat)] = [
            (Coordinator.nameColumn, String(localized: "Name"), 280, 120),
            (Coordinator.dateColumn, String(localized: "Date Modified"), 170, 100),
            (Coordinator.sizeColumn, String(localized: "Size"), 90, 60),
            (Coordinator.kindColumn, String(localized: "Kind"), 150, 60),
        ]
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.minWidth
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            outlineView.addTableColumn(column)
        }
        outlineView.outlineTableColumn = outlineView.tableColumns.first
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        outlineView.sortDescriptors = [NSSortDescriptor(key: Coordinator.nameColumn, ascending: true)]
        outlineView.setAccessibilityIdentifier("fileTable")
        outlineView.coordinator = context.coordinator
        context.coordinator.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let itemsChanged = coord.flatItems != items
        let searchingChanged = coord.isSearching != isSearching
        coord.flatItems = items
        coord.outlineDataSource = outlineDataSource
        coord.isSearching = isSearching
        coord.onOpen = onOpen
        coord.onSort = onSort
        coord.onSelectionChange = onSelectionChange
        coord.onTrash = onTrash
        coord.onRename = onRename
        coord.onNewFolder = onNewFolder
        coord.onSendPathToTerminal = onSendPathToTerminal
        coord.onExpandCollapse = onExpandCollapse
        coord.onPasteFiles = onPasteFiles
        coord.onDuplicate = onDuplicate

        guard let ov = nsView.documentView as? NSOutlineView else { return }

        if let dirtyDirs = dirtyDirectories, !dirtyDirs.isEmpty {
            if coord.isSearching {
                ov.reloadItem(nil, reloadChildren: true)
            } else {
                for dirPath in dirtyDirs {
                    let url = URL(fileURLWithPath: dirPath)
                    if let node = coord.findNodeByURL(url) {
                        ov.reloadItem(node, reloadChildren: true)
                    } else {
                        ov.reloadItem(nil, reloadChildren: true)
                    }
                }
            }
            let clearDirty = onClearDirtyDirectories
            DispatchQueue.main.async { clearDirty() }
        } else if coord.editingRow < 0, (itemsChanged || searchingChanged) {
            ov.reloadItem(nil, reloadChildren: true)
        }

        if let pendingURL = pendingRenameURL {
            let clearPending = onClearPendingRename
            DispatchQueue.main.async {
                let row = ov.row(forItem: coord.findNodeByURL(pendingURL))
                if row >= 0 {
                    ov.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    ov.scrollRowToVisible(row)
                    coord.beginRename(row: row)
                }
                clearPending()
            }
        }

        if let targets = revealSelection, !targets.isEmpty {
            let clearReveal = onClearRevealSelection
            DispatchQueue.main.async {
                let rows = IndexSet(targets.compactMap { url in
                    let row = ov.row(forItem: coord.findNodeByURL(url))
                    return row >= 0 ? row : nil
                })
                if !rows.isEmpty {
                    ov.selectRowIndexes(rows, byExtendingSelection: false)
                    if let firstRow = rows.first {
                        ov.scrollRowToVisible(firstRow)
                    }
                    ov.window?.makeFirstResponder(ov)
                }
                clearReveal()
            }
        }
    }

    // MARK: - Custom NSOutlineView for key events + Quick Look ownership

    final class FileNSOutlineView: NSOutlineView {
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

        // MARK: - Standard Edit selectors

        @objc func copy(_ sender: Any?) {
            guard let urls = coordinator?.selectedURLs(), !urls.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls.map { $0 as NSURL })
            pb.setString(urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
        }

        @objc func paste(_ sender: Any?) {
            guard let urls = readFileURLsFromPasteboard(), !urls.isEmpty else { return }
            coordinator?.onPasteFiles?(urls, .copy)
        }

        @objc func moveItemHere(_ sender: Any?) {
            guard let urls = readFileURLsFromPasteboard(), !urls.isEmpty else { return }
            coordinator?.onPasteFiles?(urls, .move)
        }

        @objc func duplicate(_ sender: Any?) {
            coordinator?.onDuplicate?()
        }

        override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            switch item.action {
            case #selector(copy(_:)), #selector(duplicate(_:)):
                return selectedRowIndexes.count > 0
            case #selector(paste(_:)), #selector(moveItemHere(_:)):
                return readFileURLsFromPasteboard() != nil
            default:
                return super.validateUserInterfaceItem(item)
            }
        }

        func readFileURLsFromPasteboard() -> [URL]? {
            let urls = NSPasteboard.general.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
            return urls?.isEmpty == false ? urls : nil
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

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
                             NSMenuDelegate, NSTextFieldDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        static let nameColumn = "name"
        static let dateColumn = "date"
        static let sizeColumn = "size"
        static let kindColumn = "kind"

        var flatItems: [FileItem]
        var outlineDataSource: OutlineDataSource
        var isSearching: Bool
        var onOpen: (FileItem) -> Void
        var onSort: (String, Bool) -> Void
        var onSelectionChange: ([FileItem]) -> Void
        var onTrash: () -> Void
        var onRename: (URL, String) -> Bool
        var onNewFolder: () -> Void
        var onSendPathToTerminal: ([URL]) -> Void
        var onExpandCollapse: () -> Void
        var onPasteFiles: (([URL], PasteOperation) -> Void)?
        var onDuplicate: (() -> Void)?
        weak var outlineView: NSOutlineView?

        var editingRow: Int = -1

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
            self.flatItems = parent.items
            self.outlineDataSource = parent.outlineDataSource
            self.isSearching = parent.isSearching
            self.onOpen = parent.onOpen
            self.onSort = parent.onSort
            self.onSelectionChange = parent.onSelectionChange
            self.onTrash = parent.onTrash
            self.onRename = parent.onRename
            self.onNewFolder = parent.onNewFolder
            self.onSendPathToTerminal = parent.onSendPathToTerminal
            self.onExpandCollapse = parent.onExpandCollapse
        }

        // MARK: - Node lookup helpers

        func findNodeByURL(_ url: URL) -> FileNode? {
            func search(nodes: [FileNode]) -> FileNode? {
                for node in nodes {
                    if node.item.url == url { return node }
                    if let children = outlineDataSource.expandedDirectoryURLs.contains(node.item.url)
                        ? childrenForNode(node) : nil {
                        if let found = search(nodes: children) { return found }
                    }
                }
                return nil
            }
            return search(nodes: outlineDataSource.rootNodes)
        }

        private func childrenForNode(_ node: FileNode) -> [FileNode]? {
            let count = outlineDataSource.numberOfChildren(of: node)
            guard count > 0 else { return nil }
            return (0..<count).map { outlineDataSource.child(index: $0, of: node) }
        }

        private func itemForRow(_ row: Int) -> FileItem? {
            guard row >= 0, let ov = outlineView else { return nil }
            if isSearching {
                return row < flatItems.count ? flatItems[row] : nil
            }
            return (ov.item(atRow: row) as? FileNode)?.item
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if isSearching { return item == nil ? flatItems.count : 0 }
            return self.outlineDataSource.numberOfChildren(of: item as? FileNode)
        }

        private static let flatPlaceholder = FlatFileNode(item: FileItem(
            url: URL(fileURLWithPath: "/.pathdeck-placeholder"),
            name: "", isDirectory: false, size: nil, modifiedDate: nil, kind: ""))

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if isSearching {
                guard index < flatItems.count else { return Self.flatPlaceholder }
                return FlatFileNode(item: flatItems[index])
            }
            return self.outlineDataSource.child(index: index, of: item as? FileNode)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if isSearching { return false }
            guard let node = item as? FileNode else { return false }
            return self.outlineDataSource.isExpandable(node)
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            if let node = item as? FileNode {
                return node.item.url as NSURL
            }
            if let flat = item as? FlatFileNode {
                return flat.item.url as NSURL
            }
            return nil
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?,
                          item: Any) -> NSView? {
            guard let columnId = tableColumn?.identifier.rawValue else { return nil }
            let fileItem: FileItem
            if let node = item as? FileNode {
                fileItem = node.item
            } else if let flat = item as? FlatFileNode {
                fileItem = flat.item
            } else {
                return nil
            }

            let isName = columnId == Self.nameColumn
            let reuseId = NSUserInterfaceItemIdentifier("cell.\(columnId)")
            let cell = (outlineView.makeView(withIdentifier: reuseId, owner: self)
                            as? NSTableCellView)
                ?? Self.makeCell(id: reuseId, withIcon: isName)

            if isName {
                cell.textField?.delegate = self
            }

            switch columnId {
            case Self.nameColumn:
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: fileItem.url.path)
                cell.textField?.stringValue = fileItem.name
            case Self.dateColumn:
                cell.textField?.stringValue =
                    fileItem.modifiedDate.map { dateFormatter.string(from: $0) } ?? "--"
            case Self.sizeColumn:
                cell.textField?.stringValue =
                    fileItem.size.map { sizeFormatter.string(fromByteCount: $0) } ?? "--"
            case Self.kindColumn:
                cell.textField?.stringValue = fileItem.kind.isEmpty ? "--" : fileItem.kind
            default:
                break
            }
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView,
                          sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key else { return }
            onSort(key, descriptor.ascending)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let ov = outlineView else { return }
            let selected = ov.selectedRowIndexes.compactMap { row -> FileItem? in
                itemForRow(row)
            }
            onSelectionChange(selected)

            if QLPreviewPanel.sharedPreviewPanelExists(),
               let panel = QLPreviewPanel.shared(), panel.isVisible {
                panel.reloadData()
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
            guard let node = item as? FileNode else { return false }
            _ = self.outlineDataSource.loadChildren(for: node)
            return true
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            onExpandCollapse()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            outlineDataSource.clearChildren(for: node)
            onExpandCollapse()
        }

        // MARK: - Double Click

        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = itemForRow(row) else { return }
            if item.isDirectory {
                onOpen(item)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }

        // MARK: - Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let ov = outlineView else { return }
            let clickedRow = ov.clickedRow

            if clickedRow < 0 {
                ov.deselectAll(nil)
                let canPaste = (ov as? FileNSOutlineView)?.readFileURLsFromPasteboard() != nil
                let pasteItem = addMenuItem(to: menu, title: String(localized: "Paste"),
                                            action: #selector(menuPaste(_:)))
                pasteItem.isEnabled = canPaste
                menu.addItem(.separator())
                addMenuItem(to: menu, title: String(localized: "New Folder"), action: #selector(menuNewFolder(_:)))
                return
            }

            guard let item = itemForRow(clickedRow) else { return }

            if !ov.selectedRowIndexes.contains(clickedRow) {
                ov.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }

            let isMultiple = ov.selectedRowIndexes.count > 1

            if !isMultiple && item.isDirectory {
                addMenuItem(to: menu, title: String(localized: "Open Folder"), action: #selector(menuOpen(_:)))
            } else {
                addMenuItem(to: menu, title: String(localized: "Open"), action: #selector(menuOpen(_:)))
            }
            addMenuItem(to: menu, title: String(localized: "Open With…"), action: #selector(menuOpenWith(_:)))

            menu.addItem(.separator())

            let renameItem = addMenuItem(to: menu, title: String(localized: "Rename"),
                                         action: #selector(menuRename(_:)))
            if isMultiple { renameItem.isEnabled = false }

            addMenuItem(to: menu, title: String(localized: "Move to Trash"), action: #selector(menuTrash(_:)))

            menu.addItem(.separator())

            addMenuItem(to: menu, title: String(localized: "Copy Path"), action: #selector(menuCopyPath(_:)))
            addMenuItem(to: menu, title: String(localized: "Duplicate"), action: #selector(menuDuplicate(_:)))
            addMenuItem(to: menu, title: String(localized: "Send Path to Terminal"),
                        action: #selector(menuSendPathToTerminal(_:)))

            menu.addItem(.separator())

            addMenuItem(to: menu, title: String(localized: "New Folder"), action: #selector(menuNewFolder(_:)))
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
            guard let ov = outlineView else { return }
            if ov.selectedRowIndexes.count <= 1 {
                let row = ov.clickedRow
                guard row >= 0, let item = itemForRow(row) else { return }
                if item.isDirectory {
                    onOpen(item)
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            } else {
                for idx in ov.selectedRowIndexes {
                    guard let item = itemForRow(idx) else { continue }
                    NSWorkspace.shared.open(item.url)
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
            guard let ov = outlineView, ov.selectedRow >= 0 else { return }
            beginRename(row: ov.selectedRow)
        }

        @objc private func menuCopyPath(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            NSPasteboard.general.clearContents()
            let paths = urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            NSPasteboard.general.setString(paths, forType: .string)
        }

        @objc private func menuNewFolder(_ sender: Any?) { onNewFolder() }

        @objc private func menuDuplicate(_ sender: Any?) { onDuplicate?() }

        @objc private func menuPaste(_ sender: Any?) {
            guard let urls = (outlineView as? FileNSOutlineView)?.readFileURLsFromPasteboard() else { return }
            onPasteFiles?(urls, .copy)
        }

        @objc private func menuSendPathToTerminal(_ sender: Any?) {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            onSendPathToTerminal(urls)
        }

        func selectedURLs() -> [URL] {
            guard let ov = outlineView else { return [] }
            return ov.selectedRowIndexes.compactMap { row in
                itemForRow(row)?.url
            }
        }

        // MARK: - Inline Editing

        func beginRename(row: Int) {
            guard let ov = outlineView, row >= 0, itemForRow(row) != nil else { return }
            ov.scrollRowToVisible(row)
            let nameColIndex = ov.column(
                withIdentifier: NSUserInterfaceItemIdentifier(Self.nameColumn))
            guard nameColIndex >= 0,
                  let cellView = ov.view(atColumn: nameColIndex, row: row,
                                         makeIfNecessary: true) as? NSTableCellView,
                  let textField = cellView.textField else { return }
            editingRow = row
            textField.isEditable = true
            textField.isSelectable = true
            ov.window?.makeFirstResponder(textField)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if let item = itemForRow(editingRow) {
                    (control as? NSTextField)?.stringValue = item.name
                }
                (control as? NSTextField)?.isEditable = false
                (control as? NSTextField)?.isSelectable = false
                editingRow = -1
                outlineView?.window?.makeFirstResponder(outlineView)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            textField.isEditable = false
            textField.isSelectable = false

            guard let oldItem = itemForRow(editingRow) else {
                editingRow = -1
                return
            }

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
                outlineView?.keyDown(with: event)
                return true
            }
            return false
        }

        func previewPanel(_ panel: QLPreviewPanel!,
                          sourceFrameOnScreenFor item: any QLPreviewItem) -> NSRect {
            guard let ov = outlineView,
                  let url = (item as? NSURL) as URL? else { return .zero }
            let node = findNodeByURL(url)
            let row = node != nil ? ov.row(forItem: node) : -1
            guard row >= 0 else { return .zero }
            let nameColIndex = ov.column(
                withIdentifier: NSUserInterfaceItemIdentifier(Self.nameColumn))
            guard nameColIndex >= 0 else { return .zero }
            let cellRect = ov.frameOfCell(atColumn: nameColIndex, row: row)
            let windowRect = ov.convert(cellRect, to: nil)
            return ov.window?.convertToScreen(windowRect) ?? .zero
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
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = imageView
                cell.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
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

/// 搜索模式下的 flat item 包装（不参与 outline 层级）。
final class FlatFileNode: NSObject {
    let item: FileItem
    init(item: FileItem) { self.item = item }
    override var hash: Int { item.url.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FlatFileNode else { return false }
        return item.url == other.item.url
    }
}
