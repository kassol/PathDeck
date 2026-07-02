import Testing
import Foundation
import AppKit
@testable import PathDeck

@MainActor
struct FileEditActionTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeModel(root: URL) -> WorkspaceModel {
        WorkspaceModel(root: root)
    }

    // MARK: - uniqueDestination (tested via pasteFiles)

    @Test func pasteFilesCopyNoConflict() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        defer { try? FileManager.default.removeItem(at: dst) }

        let file = src.appendingPathComponent("hello.txt")
        try Data("content".utf8).write(to: file)

        let model = makeModel(root: dst)
        model.pasteFiles([file], operation: .copy)

        let pasted = dst.appendingPathComponent("hello.txt")
        #expect(FileManager.default.fileExists(atPath: pasted.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func pasteFilesCopyWithConflictAddsCopySuffix() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        defer { try? FileManager.default.removeItem(at: dst) }

        let file = src.appendingPathComponent("doc.txt")
        try Data("original".utf8).write(to: file)
        try Data("existing".utf8).write(to: dst.appendingPathComponent("doc.txt"))

        let model = makeModel(root: dst)
        model.pasteFiles([file], operation: .copy)

        let copy = dst.appendingPathComponent("doc copy.txt")
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func pasteFilesCopyMultipleConflictsIncrement() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        defer { try? FileManager.default.removeItem(at: dst) }

        let file = src.appendingPathComponent("doc.txt")
        try Data("src".utf8).write(to: file)
        try Data("v1".utf8).write(to: dst.appendingPathComponent("doc.txt"))
        try Data("v2".utf8).write(to: dst.appendingPathComponent("doc copy.txt"))

        let model = makeModel(root: dst)
        model.pasteFiles([file], operation: .copy)

        let copy2 = dst.appendingPathComponent("doc copy 2.txt")
        #expect(FileManager.default.fileExists(atPath: copy2.path(percentEncoded: false)))
    }

    @Test func pasteFilesMoveRemovesSource() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        defer { try? FileManager.default.removeItem(at: dst) }

        let file = src.appendingPathComponent("moveme.txt")
        try Data("data".utf8).write(to: file)

        let model = makeModel(root: dst)
        model.pasteFiles([file], operation: .move)

        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(
            atPath: dst.appendingPathComponent("moveme.txt").path(percentEncoded: false)))
    }

    @Test func duplicateItemsCreatesFileCopy() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("report.md")
        try Data("# Report".utf8).write(to: file)

        let model = makeModel(root: tmp)
        model.selectedURLs = [file]
        model.duplicateItems()

        let copy = tmp.appendingPathComponent("report copy.md")
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func duplicateDirectoryCopiesRecursively() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dir = tmp.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        try Data("inner".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let model = makeModel(root: tmp)
        model.selectedURLs = [dir]
        model.duplicateItems()

        let copyDir = tmp.appendingPathComponent("folder copy")
        #expect(FileManager.default.fileExists(atPath: copyDir.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(
            atPath: copyDir.appendingPathComponent("file.txt").path(percentEncoded: false)))
    }

    @Test func pasteFilesUpdatesSelection() throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        defer { try? FileManager.default.removeItem(at: dst) }

        let file = src.appendingPathComponent("sel.txt")
        try Data("x".utf8).write(to: file)

        let model = makeModel(root: dst)
        model.pasteFiles([file], operation: .copy)

        #expect(model.selectedURLs.count == 1)
        #expect(model.selectedURLs.first?.lastPathComponent == "sel.txt")
        #expect(model.revealSelection?.count == 1)
    }

    @Test func uniqueDestinationNoExtension() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dir = tmp.appendingPathComponent("Makefile")
        FileManager.default.createFile(atPath: dir.path, contents: nil)

        let src = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        FileManager.default.createFile(atPath: src.appendingPathComponent("Makefile").path, contents: nil)

        let model = makeModel(root: tmp)
        model.pasteFiles([src.appendingPathComponent("Makefile")], operation: .copy)

        let copy = tmp.appendingPathComponent("Makefile copy")
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    // MARK: - NSPasteboard write (copy: selector logic)

    @Test func copyWritesDualPasteboardTypes() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try Data("code".utf8).write(to: file)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        pb.setString(file.path(percentEncoded: false), forType: .string)

        let readURLs = pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(readURLs?.count == 1)
        #expect(readURLs?.first?.lastPathComponent == "test.swift")

        let readString = pb.string(forType: .string)
        #expect(readString == file.path(percentEncoded: false))
    }
}
