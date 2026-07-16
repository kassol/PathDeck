//
//  GhosttyOpenURLTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/7/16.
//

import Foundation
import Testing
@testable import PathDeck

/// FR-BRIDGE-003 #4：OPEN_URL action 的 URL 解析决策。
/// action 派发本身依赖真实 surface 手势，纯函数只覆盖「哪些字符串允许交系统打开」。
struct GhosttyOpenURLTests {
    @Test func httpsURLIsOpenable() {
        let url = GhosttyApp.openableURL(from: "https://example.com/path?q=1")
        #expect(url?.absoluteString == "https://example.com/path?q=1")
    }

    @Test func mailtoURLIsOpenable() {
        #expect(GhosttyApp.openableURL(from: "mailto:dev@example.com") != nil)
    }

    @Test func fileURLParsesAsFileURL() {
        // 解析层放行 file://；改道决策在 handleAction（isFileURL → Locate，绝不打开），
        // 存在性判定见 PathLinkDetectorTests.linkFromFileURLProbesExistence。
        #expect(GhosttyApp.openableURL(from: "file:///tmp/foo.txt")?.isFileURL == true)
    }

    @Test func schemelessPathIsRejected() {
        #expect(GhosttyApp.openableURL(from: "/tmp/foo.txt") == nil)
    }

    @Test func unparsableStringIsRejected() {
        #expect(GhosttyApp.openableURL(from: "not a url at all") == nil)
    }

    @Test func emptyStringIsRejected() {
        #expect(GhosttyApp.openableURL(from: "") == nil)
    }
}
