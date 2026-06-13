//
//  GhosttyLinkTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/6/13.
//

import Testing
@testable import PathDeck

/// S2 链接冒烟：证明 GhosttyKit 静态库已正确链接、C 符号可从 Swift 调用。
/// 不创建窗口/GPU surface，是 libghostty 嵌入能自动化验证的唯一一层；
/// 渲染 + 键盘回显的 GUI 冒烟由人工在 Xcode 走查。
struct GhosttyLinkTests {
    @Test func libghosttyVersionIsAvailable() {
        let version = GhosttyApp.libghosttyVersion()
        #expect(!version.isEmpty)
    }
}
