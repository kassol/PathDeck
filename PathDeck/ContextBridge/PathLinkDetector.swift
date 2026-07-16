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
    /// 解析后的绝对 file URL（已 standardized，行列号已剥离）。
    let url: URL
    /// 目标是目录 → Locate 语义为导航进入；文件 → reveal 并选中（ADR-0003）。
    let isDirectory: Bool
    /// `path:line[:col]` 解析出的行列号：进模型、当前无消费方（ADR-0003）。
    let line: Int?
    let column: Int?

    init(url: URL, isDirectory: Bool, line: Int? = nil, column: Int? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.line = line
        self.column = column
    }
}

/// Path Link 检测纯函数（FR-BRIDGE-003 #5 绝对路径 + #6 语法全集）。
///
/// 识别形态：绝对路径 / 相对路径（仅 `cwd` 已知，挂 OSC 7 上报值）/ `~` 展开 /
/// `path:line[:col]`（剥离后查存在，行列号保留）/ 引号包裹含空格路径 / `file://` URL。
/// 非目标：Windows 反斜杠路径（相对解析 + 存在性检查天然 miss）。
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

    static func detect(line: String, index: Int, cwd: URL?,
                       home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       probe: (String) -> ProbeResult?) -> PathLink? {
        let chars = Array(line)
        guard index >= 0, index < chars.count else { return nil }

        // 引号候选优先（含空格路径唯一入口）；prose 撇号会造出假引号区，落空必须回退 token 检测。
        if let quoted = quotedSpanContent(chars: chars, containing: index),
           let link = resolveToken(quoted, cwd: cwd, home: home, probe: probe) {
            return link
        }

        guard !chars[index].isWhitespace else { return nil }

        // token = 包含点击位置的最大非空白段。
        var start = index
        while start > 0, !chars[start - 1].isWhitespace { start -= 1 }
        var end = index
        while end + 1 < chars.count, !chars[end + 1].isWhitespace { end += 1 }
        var token = String(chars[start...end])

        while let first = token.first, leadingWrappers.contains(first) {
            token.removeFirst()
        }
        return resolveToken(token, cwd: cwd, home: home, probe: probe)
    }

    /// OPEN_URL 改道入口（OSC 8 href / core 检测到的 file:// URL）：存在才构成 PathLink。
    static func link(fromFileURL url: URL, probe: (String) -> ProbeResult?) -> PathLink? {
        guard url.isFileURL else { return nil }
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty, let result = probe(path) else { return nil }
        return PathLink(url: URL(fileURLWithPath: path).standardizedFileURL,
                        isDirectory: result == .directory)
    }

    /// 生产用存在性探针。
    static func fileSystemProbe(_ path: String) -> ProbeResult? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }

    // MARK: - 内部

    /// 点击位置所在的引号区内容（`'` / `"` 成对，顺序扫描、同符闭合）；无闭合不成区。
    private static func quotedSpanContent(chars: [Character], containing index: Int) -> String? {
        var openQuote: Character?
        var spanStart = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let quote = openQuote {
                if c == quote {
                    if index > spanStart, index <= i {
                        return String(chars[(spanStart + 1)..<i])
                    }
                    openQuote = nil
                }
            } else if c == "'" || c == "\"" {
                openQuote = c
                spanStart = i
            }
            i += 1
        }
        return nil
    }

    /// token → 绝对路径字符串（按形态解析），再进候选存在性循环。
    private static func resolveToken(_ token: String, cwd: URL?, home: URL,
                                     probe: (String) -> ProbeResult?) -> PathLink? {
        guard !token.isEmpty else { return nil }
        let absolute: String
        if token.hasPrefix("file://") {
            let remainder = String(token.dropFirst("file://".count))
            guard remainder.hasPrefix("/") else { return nil }
            absolute = remainder.removingPercentEncoding ?? remainder
        } else if token == "~" {
            absolute = home.path(percentEncoded: false)
        } else if token.hasPrefix("~/") {
            absolute = home.path(percentEncoded: false) + "/" + String(token.dropFirst(2))
        } else if token.hasPrefix("~") {
            return nil // ~user 形态不支持
        } else if token.hasPrefix("/") {
            absolute = token
        } else {
            // 相对路径只挂 OSC 7 上报的 cwd；未知不触发。
            guard let cwd else { return nil }
            absolute = cwd.path(percentEncoded: false) + "/" + token
        }
        return probeCandidates(absolute, probe: probe)
    }

    /// 候选存在性循环：原样 → 剥一层 `:数字`（line）→ 剥两层（line:col）；
    /// 全落空则剥一个尾部标点重来。字面命中优先于行号解析（`foo.txt:42` 真存在时按原样）。
    private static func probeCandidates(_ path: String,
                                        probe: (String) -> ProbeResult?) -> PathLink? {
        var candidate = path
        while !candidate.isEmpty {
            if let result = probe(candidate) {
                return makeLink(candidate, result)
            }
            if let (lineBase, lineNumber) = splitTrailingNumber(candidate) {
                if let result = probe(lineBase) {
                    return makeLink(lineBase, result, line: lineNumber)
                }
                if let (colBase, innerLine) = splitTrailingNumber(lineBase),
                   let result = probe(colBase) {
                    return makeLink(colBase, result, line: innerLine, column: lineNumber)
                }
            }
            guard let last = candidate.last, trailingPunctuation.contains(last) else { return nil }
            candidate.removeLast()
        }
        return nil
    }

    private static func makeLink(_ path: String, _ result: ProbeResult,
                                 line: Int? = nil, column: Int? = nil) -> PathLink {
        PathLink(url: URL(fileURLWithPath: path).standardizedFileURL,
                 isDirectory: result == .directory, line: line, column: column)
    }

    /// `base:数字` 拆分（尾部纯 ASCII 数字才算）；拆不出返回 nil。
    private static func splitTrailingNumber(_ s: String) -> (base: String, number: Int)? {
        guard let colon = s.lastIndex(of: ":"), colon != s.startIndex else { return nil }
        let numberPart = s[s.index(after: colon)...]
        guard !numberPart.isEmpty,
              numberPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(numberPart) else { return nil }
        return (String(s[..<colon]), number)
    }
}
