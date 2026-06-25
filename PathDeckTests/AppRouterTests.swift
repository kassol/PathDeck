import Testing
import Foundation
@testable import PathDeck

@MainActor
struct AppRouterTests {

    @Test func requestEnqueues() {
        let router = AppRouter()
        let url = URL(fileURLWithPath: "/tmp")
        router.request(.open(url))
        #expect(router.pending == [.open(url)])
    }

    @Test func consumeReturnsAndRemovesHead() {
        let router = AppRouter()
        let url = URL(fileURLWithPath: "/tmp")
        router.request(.reveal([url]))

        #expect(router.consume() == .reveal([url]))
        #expect(router.pending.isEmpty)
        #expect(router.consume() == nil)
    }

    @Test func requestsAreFIFO() {
        let router = AppRouter()
        let a = URL(fileURLWithPath: "/tmp/a")
        let b = URL(fileURLWithPath: "/tmp/b")
        router.request(.open(a))
        router.request(.terminal(b, requireConfirmation: true))

        #expect(router.consume() == .open(a))
        #expect(router.consume() == .terminal(b, requireConfirmation: true))
        #expect(router.consume() == nil)
    }

    @Test func multipleOpensPreservedForMultiFolderOpenWith() {
        // Finder 多选文件夹 Open With PathDeck → 一次投递 N 条 .open，全部要被打开/激活。
        let router = AppRouter()
        let urls = (1...3).map { URL(fileURLWithPath: "/tmp/\($0)") }
        for url in urls { router.request(.open(url)) }

        let drained = (0..<urls.count).compactMap { _ in router.consume() }
        #expect(drained == urls.map { .open($0) })
        #expect(router.pending.isEmpty)
    }

    @Test func consumeOnEmptyReturnsNil() {
        let router = AppRouter()
        #expect(router.consume() == nil)
    }
}
