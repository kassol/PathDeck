//
//  FileItem.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import Foundation

/// 文件浏览列表中的单个条目（文件或目录）。值类型，不持有图标等可变资源。
struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// 目录为 nil。
    let size: Int64?
    let modifiedDate: Date?
    /// 本地化类型描述，如「文件夹」「PDF 文稿」。
    let kind: String

    var id: URL { url }
}
