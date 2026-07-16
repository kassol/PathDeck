//
//  PathLinkDetectorTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/16.
//

import Foundation
import Testing
@testable import PathDeck

/// FR-BRIDGE-003 #5/#6：Path Link 检测纯函数。
/// 存在性经 probe 注入，不碰真实文件系统；cwd/home 显式传入。
struct PathLinkDetectorTests {
    private let home = URL(fileURLWithPath: "/Users/dev")

    /// 模拟文件系统：路径 → 是否目录。
    private func probe(_ fs: [String: PathLinkDetector.ProbeResult]) -> (String) -> PathLinkDetector.ProbeResult? {
        { fs[$0] }
    }

    private func detect(_ line: String, at index: Int, cwd: URL? = nil,
                        fs: [String: PathLinkDetector.ProbeResult]) -> PathLink? {
        PathLinkDetector.detect(line: line, index: index, cwd: cwd, home: home, probe: probe(fs))
    }

    // MARK: - 绝对路径（#5）

    @Test func absoluteFilePathAloneIsHit() {
        let link = detect("/tmp/foo.txt", at: 4, fs: ["/tmp/foo.txt": .file])
        #expect(link == PathLink(url: URL(fileURLWithPath: "/tmp/foo.txt"), isDirectory: false))
    }

    @Test func absoluteDirectoryPathIsHitAsDirectory() {
        let link = detect("cd /Users/dev/Projects", at: 10, fs: ["/Users/dev/Projects": .directory])
        #expect(link?.isDirectory == true)
        #expect(link?.url == URL(fileURLWithPath: "/Users/dev/Projects"))
    }

    @Test func tokenInMiddleOfProseIsHit() {
        let line = "error: cannot open /var/log/system.log for reading"
        let link = detect(line, at: 25, fs: ["/var/log/system.log": .file])
        #expect(link?.url.path == "/var/log/system.log")
    }

    @Test func clickOnFirstAndLastCharacterOfTokenIsHit() {
        let line = "see /tmp/a.txt"
        let fs: [String: PathLinkDetector.ProbeResult] = ["/tmp/a.txt": .file]
        #expect(detect(line, at: 4, fs: fs) != nil)   // '/'
        #expect(detect(line, at: 13, fs: fs) != nil)  // 't'
    }

    @Test func trailingPunctuationIsTrimmed() {
        let fs: [String: PathLinkDetector.ProbeResult] = ["/tmp/foo.txt": .file]
        #expect(detect("see /tmp/foo.txt.", at: 8, fs: fs)?.url.path == "/tmp/foo.txt")
        #expect(detect("see /tmp/foo.txt,", at: 8, fs: fs)?.url.path == "/tmp/foo.txt")
        #expect(detect("(see /tmp/foo.txt)", at: 8, fs: fs)?.url.path == "/tmp/foo.txt")
    }

    @Test func leadingWrapperIsTrimmed() {
        let fs: [String: PathLinkDetector.ProbeResult] = ["/tmp/foo.txt": .file]
        #expect(detect("\"/tmp/foo.txt\"", at: 5, fs: fs)?.url.path == "/tmp/foo.txt")
        #expect(detect("(/tmp/foo.txt)", at: 5, fs: fs)?.url.path == "/tmp/foo.txt")
    }

    @Test func extensionDotIsNotOverTrimmed() {
        // 贪心尾部剥离必须逐字符 + 每步查存在性，不能吃掉扩展名的点。
        let fs: [String: PathLinkDetector.ProbeResult] = ["/tmp/foo.txt": .file, "/tmp/foo": .directory]
        #expect(detect("/tmp/foo.txt", at: 2, fs: fs)?.url.path == "/tmp/foo.txt")
    }

    // MARK: - 相对路径与 cwd（#6）

    @Test func relativePathWithKnownCwdIsHit() {
        let link = detect("open README.md", at: 8, cwd: URL(fileURLWithPath: "/proj"),
                          fs: ["/proj/README.md": .file])
        #expect(link?.url.path == "/proj/README.md")
        #expect(link?.isDirectory == false)
    }

    @Test func relativeSubdirPathWithKnownCwdIsHit() {
        let link = detect("modified: src/main.ts", at: 12, cwd: URL(fileURLWithPath: "/proj"),
                          fs: ["/proj/src/main.ts": .file])
        #expect(link?.url.path == "/proj/src/main.ts")
    }

    @Test func dotSlashRelativePathIsHit() {
        let link = detect("./build/out.log", at: 5, cwd: URL(fileURLWithPath: "/proj"),
                          fs: ["/proj/./build/out.log": .file])
        #expect(link?.url.path == "/proj/build/out.log")
    }

    @Test func relativePathWithoutCwdIsMiss() {
        // OSC 7 cwd 未知（无 shell integration / ssh / sudo）：相对路径不触发。
        #expect(detect("open README.md", at: 8, cwd: nil, fs: ["README.md": .file]) == nil)
    }

    @Test func absolutePathStillHitsWithoutCwd() {
        #expect(detect("/tmp/x", at: 2, cwd: nil, fs: ["/tmp/x": .file]) != nil)
    }

    // MARK: - ~ 展开（#6）

    @Test func tildeSlashPathExpandsToHome() {
        let link = detect("cat ~/notes.txt", at: 8, fs: ["/Users/dev/notes.txt": .file])
        #expect(link?.url.path == "/Users/dev/notes.txt")
    }

    @Test func bareTildeIsHomeDirectory() {
        let link = detect("cd ~", at: 3, fs: ["/Users/dev": .directory])
        #expect(link?.isDirectory == true)
        #expect(link?.url.path == "/Users/dev")
    }

    @Test func tildeUserFormIsUnsupported() {
        // ~user 形态不做（home 注入无法解析任意用户）。
        #expect(detect("~root/x", at: 2, fs: ["/var/root/x": .file]) == nil)
    }

    // MARK: - path:line[:col]（#6，ADR-0003：解析保留、不消费）

    @Test func pathLineIsStrippedAndKept() {
        let link = detect("src/main.ts:42", at: 5, cwd: URL(fileURLWithPath: "/proj"),
                          fs: ["/proj/src/main.ts": .file])
        #expect(link?.url.path == "/proj/src/main.ts")
        #expect(link?.line == 42)
        #expect(link?.column == nil)
    }

    @Test func pathLineColumnIsStrippedAndKept() {
        let link = detect("/tmp/foo.txt:42:7", at: 3, fs: ["/tmp/foo.txt": .file])
        #expect(link?.url.path == "/tmp/foo.txt")
        #expect(link?.line == 42)
        #expect(link?.column == 7)
    }

    @Test func literalColonFilenameWinsOverLineParse() {
        // 磁盘上真有 foo.txt:42 时按原样命中，不解析行号。
        let link = detect("/tmp/foo.txt:42", at: 3, fs: ["/tmp/foo.txt:42": .file])
        #expect(link?.url.path == "/tmp/foo.txt:42")
        #expect(link?.line == nil)
    }

    @Test func lineSuffixWithTrailingPunctuationIsHit() {
        let link = detect("(/tmp/foo.txt:42)", at: 4, fs: ["/tmp/foo.txt": .file])
        #expect(link?.url.path == "/tmp/foo.txt")
        #expect(link?.line == 42)
    }

    @Test func nonNumericColonSuffixIsMiss() {
        #expect(detect("/tmp/foo.txt:abc", at: 3, fs: ["/tmp/foo.txt": .file]) == nil)
    }

    // MARK: - 引号包裹含空格路径（#6）

    @Test func doubleQuotedPathWithSpacesIsHit() {
        let line = "saved to \"/tmp/my dir/report.pdf\" ok"
        let link = detect(line, at: 18, fs: ["/tmp/my dir/report.pdf": .file])
        #expect(link?.url.path == "/tmp/my dir/report.pdf")
    }

    @Test func singleQuotedRelativePathWithSpacesIsHit() {
        let link = detect("removed 'my old file.txt'", at: 12, cwd: URL(fileURLWithPath: "/proj"),
                          fs: ["/proj/my old file.txt": .file])
        #expect(link?.url.path == "/proj/my old file.txt")
    }

    @Test func clickOnSpaceInsideQuotedPathIsHit() {
        let line = "\"/tmp/my dir\""
        let link = detect(line, at: 8, fs: ["/tmp/my dir": .directory])  // 空格处
        #expect(link?.isDirectory == true)
    }

    @Test func quotedLineNumberSuffixIsHit() {
        let link = detect("\"/tmp/my dir/a.ts:7\"", at: 8, fs: ["/tmp/my dir/a.ts": .file])
        #expect(link?.line == 7)
    }

    @Test func apostropheInProseFallsBackToTokenDetection() {
        // 撇号被误判为引号区时，引号候选落空须回退空白 token 检测。
        let line = "don't miss /tmp/x today's run"
        let link = detect(line, at: 13, fs: ["/tmp/x": .file])
        #expect(link?.url.path == "/tmp/x")
    }

    @Test func quotedNonPathIsMiss() {
        #expect(detect("\"hello world\"", at: 3, fs: [:]) == nil)
    }

    // MARK: - file://（#6，按本地路径走 Locate）

    @Test func fileURLTokenIsHit() {
        let link = detect("file:///tmp/foo.txt", at: 10, fs: ["/tmp/foo.txt": .file])
        #expect(link?.url.path == "/tmp/foo.txt")
    }

    @Test func percentEncodedFileURLIsDecoded() {
        let link = detect("file:///tmp/a%20b.txt", at: 10, fs: ["/tmp/a b.txt": .file])
        #expect(link?.url.path == "/tmp/a b.txt")
    }

    @Test func nonexistentFileURLIsMiss() {
        #expect(detect("file:///tmp/nope", at: 10, fs: [:]) == nil)
    }

    @Test func linkFromFileURLProbesExistence() {
        // OPEN_URL 改道入口（OSC 8 href 场景）：存在才构成 PathLink。
        let hit = PathLinkDetector.link(fromFileURL: URL(string: "file:///tmp/a%20b.txt")!,
                                        probe: probe(["/tmp/a b.txt": .file]))
        #expect(hit?.url.path == "/tmp/a b.txt")
        #expect(hit?.isDirectory == false)
        let miss = PathLinkDetector.link(fromFileURL: URL(string: "file:///tmp/nope")!,
                                         probe: probe([:]))
        #expect(miss == nil)
        let notFile = PathLinkDetector.link(fromFileURL: URL(string: "https://example.com")!,
                                            probe: probe([:]))
        #expect(notFile == nil)
    }

    // MARK: - 不触发

    @Test func nonexistentPathIsMiss() {
        #expect(detect("/tmp/no-such-file", at: 5, fs: [:]) == nil)
    }

    @Test func windowsBackslashPathIsMiss() {
        // PRD 非目标：Windows 反斜杠路径。
        let fs: [String: PathLinkDetector.ProbeResult] = ["C:\\Users\\x": .file]
        #expect(detect("C:\\Users\\x", at: 3, cwd: nil, fs: fs) == nil)
        #expect(detect("\\\\server\\share", at: 3, cwd: nil, fs: [:]) == nil)
    }

    @Test func clickOnWhitespaceIsMiss() {
        #expect(detect("a /tmp/x b", at: 1, fs: ["/tmp/x": .file]) == nil)
    }

    @Test func clickOutsideLineIsMiss() {
        let fs: [String: PathLinkDetector.ProbeResult] = ["/tmp/x": .file]
        #expect(detect("/tmp/x", at: -1, fs: fs) == nil)
        #expect(detect("/tmp/x", at: 6, fs: fs) == nil)
        #expect(detect("", at: 0, fs: fs) == nil)
    }

    @Test func clickOnNeighboringTokenIsMiss() {
        // 点击相邻词不得命中路径 token。
        #expect(detect("cat /tmp/x done", at: 12, fs: ["/tmp/x": .file]) == nil)
    }

    @Test func urlTokenIsMiss() {
        // http(s) URL 归 core（#4）；file:// 以外的 scheme 不进本检测器。
        #expect(detect("https://example.com/tmp/x", at: 10, fs: ["/tmp/x": .file]) == nil)
    }
}
