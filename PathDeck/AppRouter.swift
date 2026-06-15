import Foundation
import Observation

/// 外部入口（URL Scheme / Finder Services / 文件夹「打开方式」）归一中介。
///
/// 三类入口的处理器都活在 `ContentView` 的 `@State model` 之外
/// （`AppDelegate.application(_:open:)` 与 `@objc` 的 `ServicesProvider`），拿不到 model。
/// 此单例是「model 外 → model」的唯一桥：处理器投递 `Route`，`ContentView` 消费后驱动导航。
/// `pending` 为一次性令牌，消费即置 nil，避免窗口重建时重放历史路由。
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Route: Equatable {
        case open(URL)         // 导航到目录
        case reveal([URL])     // 导航到首项父目录并高亮选择集（单项即长度 1）
        // 导航到目录并在底部新建终端。requireConfirmation 由产生方按来源可信度决定：
        // URL Scheme（外部 deep-link，不可信）置 true → 开 shell 前弹确认（PRD 1214）；
        // Finder Services「Open Terminal Here」（用户主动右键，可信）置 false。
        case terminal(URL, requireConfirmation: Bool)
    }

    private(set) var pending: Route?

    /// 生产用单例走 ``shared``；非私有以便单测构造隔离实例，避免污染全局令牌。
    init() {}

    /// 由 `AppDelegate` / `ServicesProvider` 调用，投递一条路由请求。
    func request(_ route: Route) {
        pending = route
    }

    /// `ContentView` 消费后置 nil（一次性令牌）。无待处理路由返回 nil。
    @discardableResult
    func consume() -> Route? {
        defer { pending = nil }
        return pending
    }
}
