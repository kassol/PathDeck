//
//  PathLinkDetectorTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/16.
//

import Foundation
import Testing
@testable import PathDeck

/// FR-BRIDGE-003 #5：Path Link 检测纯函数（本票仅绝对路径）。
/// 存在性经 probe 注入，不碰真实文件系统。
struct PathLinkDetectorTests {
    /// 模拟文件系统：路径 → 是否目录。
    private func probe(_ fs: [String: PathLinkDetector.ProbeResult]) -> (String) -> PathLinkDetector.ProbeResult? {
        { fs[$0] }
    }

    private func detect(_ line: String, at index: Int,
                        fs: [String: PathLinkDetector.ProbeResult]) -> PathLink? {
        PathLinkDetector.detect(line: line, index: index, probe: probe(fs))
    }

    // MARK: - 命中

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

    // MARK: - 不触发

    @Test func nonexistentPathIsMiss() {
        #expect(detect("/tmp/no-such-file", at: 5, fs: [:]) == nil)
    }

    @Test func relativePathIsMissInThisSlice() {
        // 相对路径挂 cwd 属 #6；本票绝对路径 only。
        #expect(detect("open README.md", at: 8, fs: ["README.md": .file]) == nil)
    }

    @Test func tildePathIsMissInThisSlice() {
        #expect(detect("~/notes.txt", at: 3, fs: ["~/notes.txt": .file]) == nil)
    }

    @Test func lineColonSuffixIsMissInThisSlice() {
        // path:line 剥离属 #6；尾部数字不是标点，不参与剥离。
        #expect(detect("/tmp/foo.txt:42", at: 5, fs: ["/tmp/foo.txt": .file]) == nil)
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
        // URL 归 core（#4），本检测器只认以 / 开头的 token。
        #expect(detect("https://example.com/tmp/x", at: 10, fs: ["/tmp/x": .file]) == nil)
    }
}
