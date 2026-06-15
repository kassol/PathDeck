import Testing
import Foundation
@testable import PathDeck

@MainActor
struct AppRouterTests {

    @Test func requestSetsPending() {
        let router = AppRouter()
        let url = URL(fileURLWithPath: "/tmp")
        router.request(.open(url))
        #expect(router.pending == .open(url))
    }

    @Test func consumeReturnsAndClears() {
        let router = AppRouter()
        let url = URL(fileURLWithPath: "/tmp")
        router.request(.reveal([url]))

        #expect(router.consume() == .reveal([url]))
        #expect(router.pending == nil)
        // 一次性令牌：再次消费返回 nil
        #expect(router.consume() == nil)
    }

    @Test func latestRequestWins() {
        let router = AppRouter()
        router.request(.open(URL(fileURLWithPath: "/tmp/a")))
        router.request(.terminal(URL(fileURLWithPath: "/tmp/b"), requireConfirmation: true))
        #expect(router.pending == .terminal(URL(fileURLWithPath: "/tmp/b"), requireConfirmation: true))
    }

    @Test func consumeOnEmptyReturnsNil() {
        let router = AppRouter()
        #expect(router.consume() == nil)
    }
}
