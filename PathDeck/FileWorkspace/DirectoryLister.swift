//
//  DirectoryLister.swift
//  PathDeck
//
//  Created by kassol on 2026/6/13.
//

import Foundation

/// 无状态目录枚举服务。`nonisolated` 以便单测与未来挪到后台线程。
enum DirectoryLister {

    /// 列出 `directory` 一层内容。目录排在文件前，同类按本地化名称排序。
    nonisolated static func list(_ directory: URL, includeHidden: Bool = false) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .nameKey,
        ]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: options
        )

        return urls
            .map { url in
                let values = try? url.resourceValues(forKeys: keys)
                let isDirectory = values?.isDirectory ?? false
                return FileItem(
                    url: url,
                    name: values?.name ?? url.lastPathComponent,
                    isDirectory: isDirectory,
                    size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                    modifiedDate: values?.contentModificationDate,
                    kind: values?.localizedTypeDescription ?? ""
                )
            }
    }
}
