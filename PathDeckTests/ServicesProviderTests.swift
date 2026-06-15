import Testing
import Foundation
import AppKit
@testable import PathDeck

@MainActor
struct ServicesProviderTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    /// 构造含给定 file URL 的私有命名 pasteboard。
    private func pasteboard(with urls: [URL]) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("PathDeckTest-\(UUID().uuidString)"))
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        return pb
    }

    @Test func openRoutesFolderToOpen() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = ServicesProvider.route(for: .open, pasteboard: pasteboard(with: [dir]))
        #expect(route == .open(dir.standardizedFileURL))
    }

    @Test func terminalRoutesFolderToTerminal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = ServicesProvider.route(for: .terminal, pasteboard: pasteboard(with: [dir]))
        // Finder Services = 用户主动操作，可信，无需确认
        #expect(route == .terminal(dir.standardizedFileURL, requireConfirmation: false))
    }

    @Test func revealRoutesFileToReveal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let route = ServicesProvider.route(for: .reveal, pasteboard: pasteboard(with: [file]))
        #expect(route == .reveal([file.standardizedFileURL]))
    }

    @Test func selectionRoutesAllItemsToReveal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: a.path(percentEncoded: false), contents: nil)
        FileManager.default.createFile(atPath: b.path(percentEncoded: false), contents: nil)
        // 多选保留全部 URL，由 WorkspaceModel.reveal 决定同父目录高亮策略
        let route = ServicesProvider.route(for: .selection, pasteboard: pasteboard(with: [a, b]))
        #expect(route == .reveal([a.standardizedFileURL, b.standardizedFileURL]))
    }

    @Test func openOnFileYieldsNil() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        // open/terminal 只接受文件夹；纯文件应无路由
        #expect(ServicesProvider.route(for: .open, pasteboard: pasteboard(with: [file])) == nil)
        #expect(ServicesProvider.route(for: .terminal, pasteboard: pasteboard(with: [file])) == nil)
    }

    @Test func emptyPasteboardYieldsNil() {
        let pb = NSPasteboard(name: NSPasteboard.Name("PathDeckTest-\(UUID().uuidString)"))
        pb.clearContents()
        #expect(ServicesProvider.route(for: .open, pasteboard: pb) == nil)
    }
}
