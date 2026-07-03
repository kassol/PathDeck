import Foundation

/// Command Palette 的匹配与排序（S37）：subsequence fuzzy，纯函数可单测。
enum CommandPaletteFilter {
    /// subsequence 匹配打分；nil = 不命中。
    /// 每个命中字符：词首 3 分，紧接上一命中 2 分，散点 1 分。大小写不敏感。
    static func score(query: String, title: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let t = Array(title.lowercased())
        var qi = 0
        var total = 0
        var prevMatched = false
        for (i, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                let isWordStart = i == 0 || t[i - 1] == " "
                total += isWordStart ? 3 : (prevMatched ? 2 : 1)
                prevMatched = true
                qi += 1
            } else {
                prevMatched = false
            }
        }
        return qi == q.count ? total : nil
    }

    /// 过滤 + 分数降序（同分保持传入原序）；空 query 原序返回。
    static func rank(query: String, specs: [ShortcutSpec]) -> [ShortcutSpec] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return specs }
        return specs
            .compactMap { spec in
                score(query: trimmed, title: spec.title).map { (spec: spec, score: $0) }
            }
            .enumerated()
            .sorted { a, b in
                a.element.score != b.element.score
                    ? a.element.score > b.element.score
                    : a.offset < b.offset
            }
            .map(\.element.spec)
    }
}
