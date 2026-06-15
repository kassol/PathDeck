import Foundation

enum DiffLineType: Sendable {
    case added, deleted, unchanged
}

struct DiffLine: Identifiable, Sendable {
    let id: Int
    let type: DiffLineType
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum DiffEngine {
    static func diff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.isEmpty ? [] : old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.isEmpty ? [] : new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let edits = myersDiff(old: oldLines, new: newLines)
        return buildDiffLines(edits: edits)
    }

    private enum Edit {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    private static func myersDiff(old: [String], new: [String]) -> [Edit] {
        let n = old.count
        let m = new.count

        if n == 0 && m == 0 { return [] }
        if n == 0 { return new.map { .insert($0) } }
        if m == 0 { return old.map { .delete($0) } }

        let offset = m + n
        let size = 2 * offset + 1
        var v = [Int](repeating: 0, count: size)
        var trace: [[Int]] = []

        outer: for d in 0...(n + m) {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                let kIdx = k + offset
                var x: Int
                if k == -d || (k != d && v[kIdx - 1] < v[kIdx + 1]) {
                    x = v[kIdx + 1]
                } else {
                    x = v[kIdx - 1] + 1
                }
                var y = x - k
                while x < n && y < m && old[x] == new[y] {
                    x += 1
                    y += 1
                }
                v[kIdx] = x
                if x >= n && y >= m { break outer }
            }
        }

        var edits: [Edit] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, to: 0, by: -1) {
            let vd = trace[d]
            let k = x - y
            let kIdx = k + offset

            let prevK: Int
            if k == -d || (k != d && vd[kIdx - 1] < vd[kIdx + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }
            let prevX = vd[prevK + offset]
            let prevY = prevX - prevK

            while x > prevX && y > prevY {
                x -= 1; y -= 1
                edits.append(.equal(old[x]))
            }
            if x == prevX && y > prevY {
                y -= 1
                edits.append(.insert(new[y]))
            } else if y == prevY && x > prevX {
                x -= 1
                edits.append(.delete(old[x]))
            }
        }
        while x > 0 && y > 0 {
            x -= 1; y -= 1
            edits.append(.equal(old[x]))
        }

        edits.reverse()
        return edits
    }

    private static func buildDiffLines(edits: [Edit]) -> [DiffLine] {
        var result: [DiffLine] = []
        var oldNum = 1
        var newNum = 1
        var seq = 0

        for edit in edits {
            switch edit {
            case .equal(let text):
                result.append(DiffLine(id: seq, type: .unchanged, text: text, oldLineNumber: oldNum, newLineNumber: newNum))
                oldNum += 1; newNum += 1
            case .delete(let text):
                result.append(DiffLine(id: seq, type: .deleted, text: text, oldLineNumber: oldNum, newLineNumber: nil))
                oldNum += 1
            case .insert(let text):
                result.append(DiffLine(id: seq, type: .added, text: text, oldLineNumber: nil, newLineNumber: newNum))
                newNum += 1
            }
            seq += 1
        }
        return result
    }
}
