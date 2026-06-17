import Foundation

/// NSOutlineView 的引用类型包装，保持 item identity 跨 reload 稳定。
final class FileNode: NSObject {
    var item: FileItem

    init(_ item: FileItem) {
        self.item = item
    }

    override var hash: Int { item.url.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileNode else { return false }
        return item.url == other.item.url
    }
}

/// 管理 NSOutlineView 的层级数据：根目录 flat 列表 + 已展开目录的子项缓存。
/// 不持有 view，纯数据层，方便单测。
final class OutlineDataSource {
    private(set) var rootNodes: [FileNode] = []
    /// url → 已加载的子 node 列表。nil = 未展开，[] = 空目录。
    private var childrenCache: [URL: [FileNode]] = [:]
    /// url → FileNode 实例池，跨 reload 复用同 URL 的 node。
    private var nodePool: [URL: FileNode] = [:]

    var sortColumn: SortColumn = .name
    var sortAscending: Bool = true
    var showHidden: Bool = false

    /// 首次加载或导航切换目录时调用——清空全部展开状态。
    func loadRoot(_ directory: URL) {
        let rawItems = (try? DirectoryLister.list(directory, includeHidden: showHidden)) ?? []
        let sorted = WorkspaceModel.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        rootNodes = sorted.map { reuseOrCreate($0) }
        childrenCache.removeAll()
        prunePool()
    }

    /// 仅刷新根层列表，保留仍存在的已展开子目录缓存，裁剪已删除目录的缓存。
    func refreshRoot(_ directory: URL) {
        let rawItems = (try? DirectoryLister.list(directory, includeHidden: showHidden)) ?? []
        let sorted = WorkspaceModel.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        rootNodes = sorted.map { reuseOrCreate($0) }

        let currentDirURLs = Set(rootNodes.filter(\.item.isDirectory).map(\.item.url))
        for cachedURL in Array(childrenCache.keys) {
            if !isAncestorPresent(cachedURL, in: currentDirURLs) {
                clearChildrenRecursive(for: cachedURL)
            }
        }
        prunePool()
    }

    func loadChildren(for node: FileNode) -> [FileNode] {
        if let cached = childrenCache[node.item.url] { return cached }
        let rawItems = (try? DirectoryLister.list(node.item.url, includeHidden: showHidden)) ?? []
        let sorted = WorkspaceModel.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        let nodes = sorted.map { reuseOrCreate($0) }
        childrenCache[node.item.url] = nodes
        return nodes
    }

    func clearChildren(for node: FileNode) {
        clearChildrenRecursive(for: node.item.url)
        prunePool()
    }

    /// FSWatcher 命中已展开目录时，重新加载该层子项。返回 nil 表示该目录未展开。
    func reloadChildren(for directoryURL: URL) -> [FileNode]? {
        guard let oldChildren = childrenCache[directoryURL] else { return nil }
        let rawItems = (try? DirectoryLister.list(directoryURL, includeHidden: showHidden)) ?? []
        let sorted = WorkspaceModel.sortedItems(rawItems, by: sortColumn, ascending: sortAscending)
        let nodes = sorted.map { reuseOrCreate($0) }

        let newDirURLs = Set(nodes.filter(\.item.isDirectory).map(\.item.url))
        for old in oldChildren where old.item.isDirectory {
            if !newDirURLs.contains(old.item.url) {
                clearChildrenRecursive(for: old.item.url)
            }
        }

        childrenCache[directoryURL] = nodes
        prunePool()
        return nodes
    }

    var expandedDirectoryURLs: Set<URL> {
        Set(childrenCache.keys)
    }

    // MARK: - NSOutlineViewDataSource helpers

    func numberOfChildren(of node: FileNode?) -> Int {
        if let node {
            return childrenCache[node.item.url]?.count ?? 0
        }
        return rootNodes.count
    }

    func child(index: Int, of node: FileNode?) -> FileNode {
        if let node {
            return childrenCache[node.item.url]![index]
        }
        return rootNodes[index]
    }

    func isExpandable(_ node: FileNode) -> Bool {
        node.item.isDirectory
    }

    /// 对所有层级重新排序（根 + 已展开子目录）。
    func resortAll() {
        rootNodes = WorkspaceModel.sortedItems(rootNodes.map(\.item), by: sortColumn, ascending: sortAscending)
            .map { reuseOrCreate($0) }
        for (url, nodes) in childrenCache {
            childrenCache[url] = WorkspaceModel.sortedItems(nodes.map(\.item), by: sortColumn, ascending: sortAscending)
                .map { reuseOrCreate($0) }
        }
    }

    // MARK: - Internal

    private func reuseOrCreate(_ item: FileItem) -> FileNode {
        if let existing = nodePool[item.url] {
            existing.item = item
            return existing
        }
        let node = FileNode(item)
        nodePool[item.url] = node
        return node
    }

    /// 检查 cachedURL 是否是 rootDirURLs 中某个目录本身或其后代。
    private func isAncestorPresent(_ cachedURL: URL, in rootDirURLs: Set<URL>) -> Bool {
        if rootDirURLs.contains(cachedURL) { return true }
        for rootURL in rootDirURLs {
            let rootPath = rootURL.path(percentEncoded: false)
            let cachedPath = cachedURL.path(percentEncoded: false)
            if cachedPath.hasPrefix(rootPath + "/") { return true }
        }
        return false
    }

    private func clearChildrenRecursive(for url: URL) {
        guard let children = childrenCache.removeValue(forKey: url) else { return }
        for child in children where child.item.isDirectory {
            clearChildrenRecursive(for: child.item.url)
        }
    }

    private func prunePool() {
        var liveURLs = Set(rootNodes.map(\.item.url))
        for nodes in childrenCache.values {
            liveURLs.formUnion(nodes.map(\.item.url))
        }
        for url in nodePool.keys where !liveURLs.contains(url) {
            nodePool.removeValue(forKey: url)
        }
    }
}
