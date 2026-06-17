import Testing
import Foundation
import AppKit
@testable import PathDeck

@MainActor
struct WorkspaceModelFileOpsTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeModel(root: URL) -> WorkspaceModel {
        WorkspaceModel(root: root)
    }

    // MARK: - Navigation

    @Test func enterDirectoryChangesCurrentURL() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        let model = makeModel(root: tmp)
        let item = FileItem(url: sub, name: "sub", isDirectory: true,
                            size: nil, modifiedDate: nil, kind: "Folder")
        model.enter(item)

        #expect(model.currentURL.standardizedFileURL == sub.standardizedFileURL)
    }

    @Test func enterFileDoesNothing() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)

        let model = makeModel(root: tmp)
        let original = model.currentURL
        let item = FileItem(url: file, name: "a.txt", isDirectory: false,
                            size: 0, modifiedDate: nil, kind: "Text")
        model.enter(item)

        #expect(model.currentURL == original)
    }

    @Test func navigateToURLChangesCurrentURL() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sub = tmp.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)

        let model = makeModel(root: tmp)
        model.navigate(to: sub)

        #expect(model.currentURL.standardizedFileURL == sub.standardizedFileURL)
    }

    // MARK: - Path Segments

    @Test func pathSegmentsFromHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let model = makeModel(root: home)
        let segments = model.pathSegments
        #expect(segments.count == 1)
        #expect(segments[0].name == "~")
    }

    @Test func pathSegmentsFromSubdir() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sub = home.appendingPathComponent("Documents")
        let model = makeModel(root: sub)
        let segments = model.pathSegments
        #expect(segments.count >= 2)
        #expect(segments[0].name == "~")
        #expect(segments.last?.name == "Documents")
    }

    @Test func pathSegmentsFromRoot() {
        let model = makeModel(root: URL(fileURLWithPath: "/"))
        let segments = model.pathSegments
        #expect(segments.count == 1)
        #expect(segments[0].name == "/")
    }

    // MARK: - Toggle Hidden

    @Test func toggleHiddenFlipsState() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        #expect(model.showHidden == false)
        model.toggleHidden()
        #expect(model.showHidden == true)
        model.toggleHidden()
        #expect(model.showHidden == false)
    }

    @Test func hiddenFilesVisibleWhenToggled() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent(".hidden").path, contents: nil)
        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("visible.txt").path, contents: nil)

        let model = makeModel(root: tmp)
        let countBefore = model.items.count
        model.toggleHidden()
        let countAfter = model.items.count
        #expect(countAfter > countBefore)
        #expect(model.items.contains(where: { $0.name == ".hidden" }))
    }

    // MARK: - Apply Sort

    @Test func applySortChangesColumn() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        #expect(model.sortColumn == .name)
        model.applySort(column: "date", ascending: false)
        #expect(model.sortColumn == .date)
        #expect(model.sortAscending == false)
    }

    @Test func applySortInvalidColumnIgnored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        model.applySort(column: "nonexistent", ascending: true)
        #expect(model.sortColumn == .name)
    }

    // MARK: - Trash

    @Test func trashItemsRemovesFile() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("doomed.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("hi".utf8))

        let model = makeModel(root: tmp)
        #expect(model.items.contains(where: { $0.name == "doomed.txt" }))

        model.selectedURLs = [file]
        model.trashItems()

        #expect(!model.items.contains(where: { $0.name == "doomed.txt" }))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func trashItemsEmptySelectionNoOp() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("safe.txt").path, contents: nil)

        let model = makeModel(root: tmp)
        let countBefore = model.items.count
        model.selectedURLs = []
        model.trashItems()

        #expect(model.items.count == countBefore)
    }

    // MARK: - Rename

    @Test func renameItemSuccess() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("old.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("data".utf8))

        let model = makeModel(root: tmp)
        let result = model.renameItem(from: file, to: "new.txt")

        #expect(result == true)
        #expect(FileManager.default.fileExists(
            atPath: tmp.appendingPathComponent("new.txt").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.items.contains(where: { $0.name == "new.txt" }))
    }

    @Test func renameItemConflictReturnsFalse() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("a.txt").path, contents: nil)
        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("b.txt").path, contents: nil)

        let model = makeModel(root: tmp)
        let result = model.renameItem(
            from: tmp.appendingPathComponent("a.txt"), to: "b.txt")

        #expect(result == false)
        #expect(FileManager.default.fileExists(
            atPath: tmp.appendingPathComponent("a.txt").path))
    }

    // MARK: - New Folder

    @Test func newFolderCreatesDirectory() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        model.newFolder()

        #expect(model.items.contains(where: { $0.name == "未命名文件夹" && $0.isDirectory }))
        #expect(FileManager.default.fileExists(
            atPath: tmp.appendingPathComponent("未命名文件夹").path))
    }

    @Test func newFolderSetsPendingRenameURL() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        model.newFolder()

        #expect(model.pendingRenameURL != nil)
        #expect(model.pendingRenameURL?.lastPathComponent == "未命名文件夹")
        #expect(model.selectedURLs.count == 1)
    }

    @Test func newFolderIncrementsOnConflict() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        model.newFolder()
        model.newFolder()

        #expect(model.items.contains(where: { $0.name == "未命名文件夹" }))
        #expect(model.items.contains(where: { $0.name == "未命名文件夹 2" }))
    }

    // MARK: - Copy Path

    @Test func copyCurrentPathWritesToPasteboard() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        model.copyCurrentPath()

        let pasted = NSPasteboard.general.string(forType: .string)
        #expect(pasted == tmp.path(percentEncoded: false))
    }

    // MARK: - Reload

    @Test func reloadPicksUpNewFiles() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let model = makeModel(root: tmp)
        #expect(model.items.isEmpty)

        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("new.txt").path, contents: nil)
        model.reload()

        #expect(model.items.contains(where: { $0.name == "new.txt" }))
    }
}
