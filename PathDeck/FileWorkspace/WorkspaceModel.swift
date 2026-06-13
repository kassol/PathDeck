//
//  WorkspaceModel.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import Foundation
import Observation

/// 文件工作区状态：当前目录 + 其内容 + 进出导航。默认 MainActor 隔离。
@Observable
final class WorkspaceModel {
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser) {
        currentURL = root
        reload()
    }

    /// 进入子目录；非目录条目忽略。
    func enter(_ item: FileItem) {
        guard item.isDirectory else { return }
        currentURL = item.url
        reload()
    }

    /// 返回上级；已在根（`/`）时无操作。
    /// 注意：`URL("/").deletingLastPathComponent()` 返回 `/..` 而非 `/`，
    /// 故用 path 判断根、并 `standardizedFileURL` 消除 `..`，避免无限上溯到畸形路径。
    func goUp() {
        guard currentURL.path(percentEncoded: false) != "/" else { return }
        currentURL = currentURL.deletingLastPathComponent().standardizedFileURL
        reload()
    }

    /// 重新枚举当前目录。失败时（如权限不足）暂显示空列表，错误态 UI 留后续切片。
    func reload() {
        items = (try? DirectoryLister.list(currentURL)) ?? []
    }
}
