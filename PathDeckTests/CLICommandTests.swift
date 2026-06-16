import Testing
import Foundation
@testable import PathDeck

@MainActor
struct CLICommandTests {

    private func makeTempDir(_ name: String = "dir") throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathDeckTests-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeTempFile(in dir: URL, name: String = "file.txt") throws -> URL {
        let file = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        return file
    }

    // MARK: - No args → open cwd

    @Test func noArgsOpensCwd() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck"], cwd: path)
        guard case .command(let action, let url) = parsed else {
            Issue.record("Expected command, got help")
            return
        }
        #expect(action == .open)
        #expect(url.scheme == "pathdeck")
        #expect(url.host == "open")
    }

    // MARK: - Smart routing

    @Test func directoryArgRoutesToOpen() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck", path], cwd: "/tmp")
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .open)
    }

    @Test func fileArgRoutesToReveal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeTempFile(in: dir)
        let parsed = try CLICommand.parse(
            ["pathdeck", file.path(percentEncoded: false)], cwd: "/tmp"
        )
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .reveal)
    }

    @Test func nonexistentPathThrows() throws {
        let path = "/tmp/pathdeck-nonexistent-\(UUID().uuidString)"
        #expect(throws: CLICommand.Failure.self) {
            try CLICommand.parse(["pathdeck", path], cwd: "/tmp")
        }
    }

    // MARK: - Subcommands

    @Test func openSubcommandDefaultsCwd() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck", "open"], cwd: path)
        guard case .command(let action, let url) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .open)
        #expect(url.host == "open")
    }

    @Test func openSubcommandWithPath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck", "open", path], cwd: "/tmp")
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .open)
    }

    @Test func openSubcommandRejectsFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeTempFile(in: dir)
        #expect(throws: CLICommand.Failure.self) {
            try CLICommand.parse(
                ["pathdeck", "open", file.path(percentEncoded: false)], cwd: "/tmp"
            )
        }
    }

    @Test func revealSubcommandWithPath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeTempFile(in: dir)
        let parsed = try CLICommand.parse(
            ["pathdeck", "reveal", file.path(percentEncoded: false)], cwd: "/tmp"
        )
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .reveal)
    }

    @Test func revealSubcommandMissingPathThrows() {
        #expect(throws: CLICommand.Failure.self) {
            try CLICommand.parse(["pathdeck", "reveal"], cwd: "/tmp")
        }
    }

    @Test func terminalSubcommandDefaultsCwd() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck", "terminal"], cwd: path)
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .terminal)
    }

    @Test func terminalSubcommandWithPath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let parsed = try CLICommand.parse(["pathdeck", "terminal", path], cwd: "/tmp")
        guard case .command(let action, _) = parsed else {
            Issue.record("Expected command")
            return
        }
        #expect(action == .terminal)
    }

    @Test func terminalSubcommandRejectsFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeTempFile(in: dir)
        #expect(throws: CLICommand.Failure.self) {
            try CLICommand.parse(
                ["pathdeck", "terminal", file.path(percentEncoded: false)], cwd: "/tmp"
            )
        }
    }

    // MARK: - Help

    @Test func helpFlag() throws {
        let parsed = try CLICommand.parse(["pathdeck", "help"], cwd: "/tmp")
        guard case .help = parsed else {
            Issue.record("Expected help")
            return
        }
    }

    @Test func helpDashH() throws {
        let parsed = try CLICommand.parse(["pathdeck", "-h"], cwd: "/tmp")
        guard case .help = parsed else {
            Issue.record("Expected help")
            return
        }
    }

    @Test func helpDoubleDash() throws {
        let parsed = try CLICommand.parse(["pathdeck", "--help"], cwd: "/tmp")
        guard case .help = parsed else {
            Issue.record("Expected help")
            return
        }
    }

    // MARK: - Path resolution

    @Test func relativePath() throws {
        let resolved = CLICommand.resolvePath("subdir", cwd: "/tmp")
        #expect(resolved == "/tmp/subdir")
    }

    @Test func absolutePathUnchanged() {
        let resolved = CLICommand.resolvePath("/usr/local", cwd: "/tmp")
        #expect(resolved == "/usr/local")
    }

    @Test func tildeExpands() {
        let resolved = CLICommand.resolvePath("~/Desktop", cwd: "/tmp")
        let expected = (("~/Desktop") as NSString).expandingTildeInPath
        #expect(resolved == expected)
    }

    @Test func dotDotNormalized() {
        let resolved = CLICommand.resolvePath("../bar", cwd: "/tmp/foo")
        #expect(resolved == "/tmp/bar")
    }

    // MARK: - URL construction

    @Test func buildURLPercentEncodesSpaces() {
        let url = CLICommand.buildURL(action: .open, path: "/tmp/my folder")
        #expect(url.scheme == "pathdeck")
        #expect(url.host == "open")
        let pathValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "path" })?.value
        #expect(pathValue == "/tmp/my folder")
    }

    @Test func buildURLPercentEncodesChinese() {
        let url = CLICommand.buildURL(action: .reveal, path: "/tmp/文件夹")
        let pathValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "path" })?.value
        #expect(pathValue == "/tmp/文件夹")
    }

    @Test func buildURLPercentEncodesHash() {
        let url = CLICommand.buildURL(action: .open, path: "/tmp/C# project")
        let pathValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "path" })?.value
        #expect(pathValue == "/tmp/C# project")
    }

    // MARK: - URL roundtrip with URLSchemeHandler

    @Test func openURLRoundtripsToSchemeHandler() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let url = CLICommand.buildURL(action: .open, path: path)
        let route = URLSchemeHandler.route(for: url)
        #expect(route == .open(URL(fileURLWithPath: path).standardizedFileURL))
    }

    @Test func revealURLRoundtripsToSchemeHandler() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeTempFile(in: dir)
        let path = file.path(percentEncoded: false)
        let url = CLICommand.buildURL(action: .reveal, path: path)
        let route = URLSchemeHandler.route(for: url)
        #expect(route == .reveal([URL(fileURLWithPath: path).standardizedFileURL]))
    }

    @Test func terminalURLRoundtripsToSchemeHandler() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.path(percentEncoded: false)
        let url = CLICommand.buildURL(action: .terminal, path: path)
        let route = URLSchemeHandler.route(for: url)
        #expect(route == .terminal(
            URL(fileURLWithPath: path).standardizedFileURL,
            requireConfirmation: true
        ))
    }

    // MARK: - Mock filesystem

    @Test func parseWithMockFS() throws {
        let mock: (String) -> (exists: Bool, isDirectory: Bool) = { path in
            if path == "/mock/dir" { return (true, true) }
            if path == "/mock/file.txt" { return (true, false) }
            return (false, false)
        }
        let openResult = try CLICommand.parse(
            ["pathdeck", "/mock/dir"], cwd: "/tmp", fileExists: mock
        )
        guard case .command(.open, _) = openResult else {
            Issue.record("Expected open command")
            return
        }

        let revealResult = try CLICommand.parse(
            ["pathdeck", "/mock/file.txt"], cwd: "/tmp", fileExists: mock
        )
        guard case .command(.reveal, _) = revealResult else {
            Issue.record("Expected reveal command")
            return
        }

        #expect(throws: CLICommand.Failure.self) {
            try CLICommand.parse(
                ["pathdeck", "/mock/nope"], cwd: "/tmp", fileExists: mock
            )
        }
    }
}
