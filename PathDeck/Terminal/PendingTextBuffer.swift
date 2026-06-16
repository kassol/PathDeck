import Foundation

/// 终端 surface 就绪前暂存待注入文本的纯值类型（S19）。
///
/// FIFO 持有 `writeText` 文本，待 `onSurfaceReady` 后顺序 flush。
/// 加条数 / 字节上限防御异常灌入导致无界增长：超限从队头丢最旧，
/// 但单条超限仍接受（不丢用户唯一输入）。不依赖 Dispatch / UUID，便于单测。
struct PendingTextBuffer {
    static let defaultMaxCount = 64
    static let defaultMaxBytes = 256 * 1024

    let maxCount: Int
    let maxBytes: Int

    private var texts: [String] = []
    private(set) var totalBytes = 0

    init(maxCount: Int = defaultMaxCount, maxBytes: Int = defaultMaxBytes) {
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    var isEmpty: Bool { texts.isEmpty }
    var count: Int { texts.count }

    /// 追加文本，返回因溢出从队头丢弃的最旧条目。
    mutating func enqueue(_ text: String) -> EnqueueResult {
        texts.append(text)
        totalBytes += text.utf8.count

        var dropped: [String] = []
        // 超条数即丢；超字节也丢，但至少保留最新这一条。
        while texts.count > maxCount || (totalBytes > maxBytes && texts.count > 1) {
            let old = texts.removeFirst()
            totalBytes -= old.utf8.count
            dropped.append(old)
        }
        return EnqueueResult(accepted: true, droppedFromOverflow: dropped)
    }

    /// 返回全部文本并清空。
    mutating func drain() -> [String] {
        let result = texts
        texts.removeAll()
        totalBytes = 0
        return result
    }
}

struct EnqueueResult {
    let accepted: Bool
    let droppedFromOverflow: [String]
}

/// `createSurface` 的失败出口，供 `onSurfaceFailed` 携带与单测断言。
enum SurfaceFailureReason: String {
    case appNotInitialized
    case surfaceNewReturnedNil
}

/// pending 文本被丢弃的原因，经 `onPendingDropped` 暴露给调用方。
enum PendingDropReason: Equatable {
    case surfaceCreationFailed
    case timeout
    case overflow
}
