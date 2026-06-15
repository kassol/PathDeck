import Testing
import Foundation
@testable import PathDeck

@MainActor
struct URLSchemeHandlerTests {

    private func makeTempDir(_ name: String = "dir") throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    /// 用 `URLComponents` 构造 `pathdeck://<action>?path=<dir>`，让查询参数走真实 percent-encoding。
    private func url(action: String, path: String) -> URL {
        var comp = URLComponents()
        comp.scheme = "pathdeck"
        comp.host = action
        comp.queryItems = [URLQueryItem(name: "path", value: path)]
        return comp.url!
    }

    private func expected(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    // MARK: - 合法

    @Test func parsesOpenForDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = URLSchemeHandler.route(for: url(action: "open",
                                                    path: dir.path(percentEncoded: false)))
        #expect(route == .open(expected(dir.path(percentEncoded: false))))
    }

    @Test func parsesTerminalForDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = URLSchemeHandler.route(for: url(action: "terminal",
                                                    path: dir.path(percentEncoded: false)))
        // URL Scheme = 外部不可信，terminal 须标记需确认（PRD 1214）
        #expect(route == .terminal(expected(dir.path(percentEncoded: false)),
                                   requireConfirmation: true))
    }

    @Test func parsesRevealForExistingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let route = URLSchemeHandler.route(for: url(action: "reveal",
                                                    path: file.path(percentEncoded: false)))
        #expect(route == .reveal([expected(file.path(percentEncoded: false))]))
    }

    @Test func handlesSpacesAndUnicodePath() throws {
        let dir = try makeTempDir("我的 文件夹 test")
        defer { try? FileManager.default.removeItem(at: dir) }
        let route = URLSchemeHandler.route(for: url(action: "open",
                                                    path: dir.path(percentEncoded: false)))
        #expect(route == .open(expected(dir.path(percentEncoded: false))))
    }

    // MARK: - 非法（一律 nil）

    @Test func rejectsWrongScheme() {
        let u = URL(string: "https://open?path=/tmp")!
        #expect(URLSchemeHandler.route(for: u) == nil)
    }

    @Test func rejectsUnknownAction() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(URLSchemeHandler.route(for: url(action: "delete",
                                                path: dir.path(percentEncoded: false))) == nil)
    }

    @Test func rejectsRelativePath() {
        #expect(URLSchemeHandler.route(for: url(action: "open", path: "relative/dir")) == nil)
    }

    @Test func rejectsMissingPathQuery() {
        let u = URL(string: "pathdeck://open")!
        #expect(URLSchemeHandler.route(for: u) == nil)
    }

    @Test func rejectsNonexistentPath() {
        let route = URLSchemeHandler.route(for: url(action: "open",
                                                    path: "/tmp/pathdeck-does-not-exist-\(UUID().uuidString)"))
        #expect(route == nil)
    }

    @Test func rejectsOpenOnFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        // open/terminal 要求目录；指向文件须拒绝
        #expect(URLSchemeHandler.route(for: url(action: "open",
                                                path: file.path(percentEncoded: false))) == nil)
        #expect(URLSchemeHandler.route(for: url(action: "terminal",
                                                path: file.path(percentEncoded: false))) == nil)
    }
}
