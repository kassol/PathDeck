import Testing
import Foundation
@testable import PathDeck

struct OutlineDataSourceTests {
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func loadRootReturnsSortedItems() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("dir"), withIntermediateDirectories: false)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        #expect(ds.rootNodes.count == 3)
        // Directories first, then files sorted by name
        #expect(ds.rootNodes[0].item.isDirectory)
        #expect(ds.rootNodes[0].item.name == "dir")
        #expect(ds.rootNodes[1].item.name == "a.txt")
        #expect(ds.rootNodes[2].item.name == "b.txt")
    }

    @Test func loadChildrenCachesAndReturns() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        let dirNode = ds.rootNodes.first { $0.item.isDirectory }!
        let children = ds.loadChildren(for: dirNode)

        #expect(children.count == 1)
        #expect(children[0].item.name == "child.txt")
        #expect(ds.expandedDirectoryURLs.contains(dirNode.item.url))
    }

    @Test func clearChildrenRemovesCacheRecursively() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("parent")
        let nested = sub.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        let parentNode = ds.rootNodes.first { $0.item.name == "parent" }!
        let childNodes = ds.loadChildren(for: parentNode)
        let childDirNode = childNodes.first { $0.item.isDirectory }!
        _ = ds.loadChildren(for: childDirNode)

        #expect(ds.expandedDirectoryURLs.count == 2)

        ds.clearChildren(for: parentNode)
        #expect(ds.expandedDirectoryURLs.isEmpty)
    }

    @Test func reloadChildrenReflectsChanges() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)
        let dirNode = ds.rootNodes.first { $0.item.isDirectory }!
        _ = ds.loadChildren(for: dirNode)

        // Add a new file
        try "".write(to: sub.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let reloaded = ds.reloadChildren(for: dirNode.item.url)
        #expect(reloaded != nil)
        #expect(reloaded!.count == 2)
    }

    @Test func reloadChildrenPrunesDeletedNestedCache() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parent = tmp.appendingPathComponent("parent")
        let child = parent.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "".write(to: child.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        let parentNode = ds.rootNodes.first { $0.item.name == "parent" }!
        let parentChildren = ds.loadChildren(for: parentNode)
        let childNode = parentChildren.first { $0.item.name == "child" }!
        _ = ds.loadChildren(for: childNode)

        #expect(ds.expandedDirectoryURLs.count == 2)

        // Delete child directory
        try FileManager.default.removeItem(at: child)
        _ = ds.reloadChildren(for: parentNode.item.url)

        #expect(!ds.expandedDirectoryURLs.contains(childNode.item.url))
        #expect(ds.expandedDirectoryURLs.count == 1)
    }

    @Test func reloadChildrenReturnsNilForUnexpandedDir() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        #expect(ds.reloadChildren(for: sub) == nil)
    }

    @Test func nodeIdentityPreservedAcrossReload() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)
        let firstNode = ds.rootNodes[0]

        ds.loadRoot(tmp)
        let secondNode = ds.rootNodes[0]

        #expect(firstNode === secondNode)
    }

    @Test func resortAllAppliesNewOrder() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "".write(to: tmp.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        #expect(ds.rootNodes[0].item.name == "a.txt")

        ds.sortAscending = false
        ds.resortAll()

        #expect(ds.rootNodes[0].item.name == "b.txt")
    }

    @Test func numberOfChildrenAndChildAccessors() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)

        #expect(ds.numberOfChildren(of: nil) == 2)

        let dirNode = ds.rootNodes.first { $0.item.isDirectory }!
        #expect(ds.isExpandable(dirNode))
        #expect(ds.numberOfChildren(of: dirNode) == 0)

        _ = ds.loadChildren(for: dirNode)
        #expect(ds.numberOfChildren(of: dirNode) == 1)

        let child = ds.child(index: 0, of: dirNode)
        #expect(child.item.name == "b.txt")
    }

    @Test func refreshRootPreservesExpandedChildren() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)
        try "".write(to: tmp.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)
        let dirNode = ds.rootNodes.first { $0.item.isDirectory }!
        _ = ds.loadChildren(for: dirNode)
        #expect(ds.expandedDirectoryURLs.contains(dirNode.item.url))

        // Add a new file in root — refreshRoot should preserve expanded children
        try "".write(to: tmp.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        ds.refreshRoot(tmp)

        #expect(ds.rootNodes.count == 3)
        #expect(ds.expandedDirectoryURLs.contains(dirNode.item.url))
        #expect(ds.numberOfChildren(of: dirNode) == 1)
    }

    @Test func refreshRootPrunesDeletedDirectoryCache() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.loadRoot(tmp)
        let dirNode = ds.rootNodes.first { $0.item.isDirectory }!
        _ = ds.loadChildren(for: dirNode)
        #expect(ds.expandedDirectoryURLs.count == 1)

        // Delete the directory
        try FileManager.default.removeItem(at: sub)
        ds.refreshRoot(tmp)

        #expect(ds.rootNodes.isEmpty)
        #expect(ds.expandedDirectoryURLs.isEmpty)
    }

    @Test func showHiddenFilters() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "".write(to: tmp.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try "".write(to: tmp.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        let ds = OutlineDataSource()
        ds.showHidden = false
        ds.loadRoot(tmp)
        #expect(ds.rootNodes.count == 1)

        ds.showHidden = true
        ds.loadRoot(tmp)
        #expect(ds.rootNodes.count == 2)
    }
}
