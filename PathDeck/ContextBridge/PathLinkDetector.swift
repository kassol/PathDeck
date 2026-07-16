//
//  PathLinkDetector.swift
//  PathDeck
//
//  Created by kassol on 2026/7/16.
//

import Foundation

/// 终端输出中被识别为本地文件或目录引用的文本段（CONTEXT.md「Path Link」）。
/// 解析不出目标或目标不存在的文本段不是 Path Link——存在性检查是构造前提。
nonisolated struct PathLink: Equatable {
    /// 解析后的绝对 file URL（已 standardized）。
    let url: URL
    /// 目标是目录 → Locate 语义为导航进入；文件 → reveal 并选中（ADR-0003）。
    let isDirectory: Bool
}

/// Path Link 检测纯函数（FR-BRIDGE-003 #5：仅绝对路径形态；相对/~/行号/引号包裹见 #6）。
///
/// 输入终端一行文本 + 点击的字符位置，输出命中的 `PathLink` 或 nil。
/// 存在性检查经 `probe` 注入：生产走 `fileSystemProbe`，单测注入假文件系统。
nonisolated enum PathLinkDetector {
    enum ProbeResult {
        case file
        case directory
    }

    /// 常见成对包裹的左半：token 以此开头时剥掉再判定（`(/tmp/x)`、`"/tmp/x"`）。
    private static let leadingWrappers: Set<Character> = ["(", "<", "[", "{", "'", "\"", "`"]
    /// 尾部标点：逐字符剥离、每剥一次做一次存在性检查（防吃掉扩展名的点）。
    private static let trailingPunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", ">", "'", "\"", "`",
    ]

    static func detect(line: String, index: Int,
                       probe: (String) -> ProbeResult?) -> PathLink? {
        let chars = Array(line)
        guard index >= 0, index < chars.count, !chars[index].isWhitespace else { return nil }

        // token = 包含点击位置的最大非空白段。
        var start = index
        while start > 0, !chars[start - 1].isWhitespace { start -= 1 }
        var end = index
        while end + 1 < chars.count, !chars[end + 1].isWhitespace { end += 1 }
        var token = String(chars[start...end])

        while let first = token.first, leadingWrappers.contains(first) {
            token.removeFirst()
        }
        guard token.hasPrefix("/") else { return nil }

        var candidate = token
        while !candidate.isEmpty {
            if let result = probe(candidate) {
                return PathLink(
                    url: URL(fileURLWithPath: candidate).standardizedFileURL,
                    isDirectory: result == .directory
                )
            }
            guard let last = candidate.last, trailingPunctuation.contains(last) else { return nil }
            candidate.removeLast()
        }
        return nil
    }

    /// 生产用存在性探针。
    static func fileSystemProbe(_ path: String) -> ProbeResult? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }
}
