//
//  WorkspaceModelTests.swift
//  PathDeckTests
//
//  Created by kassol on 2026/6/13.
//

import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspaceModelTests {

    /// 回归测试：上溯到根 `/` 后必须停住，不得继续变成 `/..` 等畸形路径。
    @Test func goUpReachesRootAndStops() {
        let model = WorkspaceModel(root: URL(fileURLWithPath: "/Users"))

        model.goUp()
        #expect(model.currentURL.path(percentEncoded: false) == "/")

        model.goUp()   // 已在根，应无操作
        #expect(model.currentURL.path(percentEncoded: false) == "/")
    }
}
