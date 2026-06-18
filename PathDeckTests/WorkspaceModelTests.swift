import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspaceModelTests {

    @Test func goUpReachesRootAndStops() {
        let model = WorkspaceModel(root: URL(fileURLWithPath: "/Users"))

        model.goUp()
        #expect(model.currentURL.path(percentEncoded: false) == "/")

        model.goUp()
        #expect(model.currentURL.path(percentEncoded: false) == "/")
    }

    // MARK: - Reveal

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeModel() -> WorkspaceModel {
        WorkspaceModel(root: FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test func revealSingleNavigatesToParentAndSelects() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("target.txt")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)

        let model = makeModel()
        model.reveal([file])

        #expect(model.currentURL.lastPathComponent == tmp.lastPathComponent)
        #expect(model.selectedURLs.count == 1)
        #expect(model.selectedURLs.first?.lastPathComponent == "target.txt")
        #expect(model.revealSelection?.count == 1)
        #expect(model.revealSelection?.first?.lastPathComponent == "target.txt")
    }

    @Test func revealMultipleSameParentSelectsAll() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let a = tmp.appendingPathComponent("a.txt")
        let b = tmp.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: a.path(percentEncoded: false), contents: nil)
        FileManager.default.createFile(atPath: b.path(percentEncoded: false), contents: nil)

        let model = makeModel()
        model.reveal([a, b])

        #expect(model.currentURL.lastPathComponent == tmp.lastPathComponent)
        let names = Set(model.selectedURLs.map(\.lastPathComponent))
        #expect(names == ["a.txt", "b.txt"])
        let revealNames = Set(model.revealSelection?.map(\.lastPathComponent) ?? [])
        #expect(revealNames == ["a.txt", "b.txt"])
    }

    @Test func revealMixedParentsKeepsOnlyFirstParentItems() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        let a = tmp.appendingPathComponent("a.txt")
        let other = sub.appendingPathComponent("c.txt")
        FileManager.default.createFile(atPath: a.path(percentEncoded: false), contents: nil)
        FileManager.default.createFile(atPath: other.path(percentEncoded: false), contents: nil)

        let model = makeModel()
        model.reveal([a, other])

        #expect(model.currentURL.lastPathComponent == tmp.lastPathComponent)
        #expect(model.selectedURLs.count == 1)
        #expect(model.selectedURLs.first?.lastPathComponent == "a.txt")
    }

    @Test func revealEmptyIsNoOp() throws {
        let model = makeModel()
        let before = model.currentURL
        model.reveal([])
        #expect(model.currentURL == before)
        #expect(model.selectedURLs.isEmpty)
    }

    // MARK: - Sort

    private static let testItems: [FileItem] = [
        FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false,
                 size: 200, modifiedDate: Date(timeIntervalSince1970: 2000), kind: "Text"),
        FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false,
                 size: 100, modifiedDate: Date(timeIntervalSince1970: 3000), kind: "Text"),
        FileItem(url: URL(fileURLWithPath: "/tmp/sub"), name: "sub", isDirectory: true,
                 size: nil, modifiedDate: Date(timeIntervalSince1970: 1000), kind: "Folder"),
        FileItem(url: URL(fileURLWithPath: "/tmp/z.png"), name: "z.png", isDirectory: false,
                 size: nil, modifiedDate: nil, kind: "Image"),
        FileItem(url: URL(fileURLWithPath: "/tmp/dir2"), name: "dir2", isDirectory: true,
                 size: nil, modifiedDate: Date(timeIntervalSince1970: 4000), kind: "Folder"),
    ]

    @Test func sortByNameAscending() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .name, ascending: true)
        let names = sorted.map(\.name)
        #expect(names == ["dir2", "sub", "a.txt", "b.txt", "z.png"])
    }

    @Test func sortByNameDescending() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .name, ascending: false)
        let names = sorted.map(\.name)
        #expect(names == ["sub", "dir2", "z.png", "b.txt", "a.txt"])
    }

    @Test func sortBySizeNilsAtEnd() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .size, ascending: true)
        let names = sorted.map(\.name)
        // dirs first (both nil size, stable-ish), then files: 100, 200, nil
        #expect(sorted.first!.isDirectory)
        let files = sorted.filter { !$0.isDirectory }
        #expect(files.map(\.name) == ["a.txt", "b.txt", "z.png"])
    }

    @Test func sortByDateDescendingNilsAtEnd() {
        let sorted = WorkspaceModel.sortedItems(Self.testItems, by: .date, ascending: false)
        let files = sorted.filter { !$0.isDirectory }
        #expect(files.last?.name == "z.png") // nil date at end
        #expect(files.first?.name == "a.txt") // most recent date
    }

    @Test func directoriesAlwaysBeforeFiles() {
        for col in [SortColumn.name, .date, .size, .kind] {
            for asc in [true, false] {
                let sorted = WorkspaceModel.sortedItems(Self.testItems, by: col, ascending: asc)
                let types = sorted.map(\.isDirectory)
                let firstFileIndex = types.firstIndex(of: false) ?? types.count
                let lastDirIndex = types.lastIndex(of: true) ?? -1
                #expect(lastDirIndex < firstFileIndex,
                        "dirs must precede files for \(col) \(asc ? "asc" : "desc")")
            }
        }
    }

    // MARK: - New Folder Name

    @Test func newFolderNameEmpty() {
        let name = WorkspaceModel.newFolderName(in: [], baseName: "untitled folder")
        #expect(name == "untitled folder")
    }

    @Test func newFolderNameFirstConflict() {
        let name = WorkspaceModel.newFolderName(in: ["untitled folder"], baseName: "untitled folder")
        #expect(name == "untitled folder 2")
    }

    @Test func newFolderNameMultipleConflicts() {
        let name = WorkspaceModel.newFolderName(in: ["untitled folder", "untitled folder 2", "untitled folder 3"], baseName: "untitled folder")
        #expect(name == "untitled folder 4")
    }

    @Test func newFolderNameGapInSequence() {
        let name = WorkspaceModel.newFolderName(in: ["untitled folder", "untitled folder 3"], baseName: "untitled folder")
        #expect(name == "untitled folder 2")
    }

    // MARK: - Reload preserves expansion

    @Test func reloadPreservesExpandedDirectories() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        let model = WorkspaceModel(root: tmp)
        let dirNode = model.outlineDataSource.rootNodes.first { $0.item.isDirectory }!
        _ = model.outlineDataSource.loadChildren(for: dirNode)
        #expect(!model.outlineDataSource.expandedDirectoryURLs.isEmpty)

        model.reload()
        #expect(!model.outlineDataSource.expandedDirectoryURLs.isEmpty)
    }

    @Test func navigateClearsExpandedDirectories() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try "".write(to: sub.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        let model = WorkspaceModel(root: tmp)
        let dirNode = model.outlineDataSource.rootNodes.first { $0.item.isDirectory }!
        _ = model.outlineDataSource.loadChildren(for: dirNode)
        #expect(!model.outlineDataSource.expandedDirectoryURLs.isEmpty)

        model.navigate(to: sub)
        #expect(model.outlineDataSource.expandedDirectoryURLs.isEmpty)
    }
}
