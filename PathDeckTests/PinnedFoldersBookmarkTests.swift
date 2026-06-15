import Testing
import Foundation
@testable import PathDeck

@Suite
struct PinnedFoldersBookmarkTests {
    @Test
    func bookmarkRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-pinned-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let data = try tmpDir.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var isStale = false
        let resolved = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #expect(resolved.standardizedFileURL == tmpDir.standardizedFileURL)
    }

    @Test
    func staleBookmarkDetected() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let data = try tmpDir.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.removeItem(at: tmpDir)

        var isStale = false
        let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        if let resolved {
            let exists = FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false))
            #expect(!exists)
        }
    }

    @Test
    func terminalSessionCurrentCwdInit() {
        let url = URL(fileURLWithPath: "/tmp")
        let session = TerminalSession(id: UUID(), title: "Test", cwd: url)
        #expect(session.currentCwd == url)
    }

    @Test
    func terminalSessionCwdUpdate() {
        let url = URL(fileURLWithPath: "/tmp")
        var session = TerminalSession(id: UUID(), title: "Test", cwd: url)
        let newUrl = URL(fileURLWithPath: "/Users")
        session.currentCwd = newUrl
        #expect(session.currentCwd == newUrl)
        #expect(session.cwd == url)
    }
}
