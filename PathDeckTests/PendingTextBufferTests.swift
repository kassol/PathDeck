import Testing
@testable import PathDeck

struct PendingTextBufferTests {
    @Test func enqueuePreservesFIFOOrder() {
        var buf = PendingTextBuffer()
        _ = buf.enqueue("a")
        _ = buf.enqueue("b")
        _ = buf.enqueue("c")
        #expect(buf.drain() == ["a", "b", "c"])
        #expect(buf.isEmpty)
    }

    @Test func enqueueOverflowDropsOldestByCount() {
        var buf = PendingTextBuffer(maxCount: 2, maxBytes: .max)
        _ = buf.enqueue("a")
        _ = buf.enqueue("b")
        let result = buf.enqueue("c")
        #expect(result.droppedFromOverflow == ["a"])
        #expect(buf.drain() == ["b", "c"])
    }

    @Test func enqueueOverflowDropsOldestByBytes() {
        var buf = PendingTextBuffer(maxCount: .max, maxBytes: 4)
        _ = buf.enqueue("aa")
        _ = buf.enqueue("bb")
        let result = buf.enqueue("cc")
        #expect(result.droppedFromOverflow == ["aa"])
        #expect(buf.totalBytes <= 4)
        #expect(buf.drain() == ["bb", "cc"])
    }

    @Test func singleTextExceedingMaxBytesStillAccepted() {
        var buf = PendingTextBuffer(maxCount: .max, maxBytes: 4)
        let result = buf.enqueue("aaaaaaaa")  // 8 字节，单条超限
        #expect(result.accepted)
        #expect(result.droppedFromOverflow.isEmpty)
        #expect(buf.drain() == ["aaaaaaaa"])
    }
}
