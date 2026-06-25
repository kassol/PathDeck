import Foundation
import Observation

/// 外部入口（URL Scheme / Finder Services / 文件夹「打开方式」）归一中介。
///
/// 三类入口的处理器都活在 SwiftUI view tree 之外（`AppDelegate.application(_:open:)` 与
/// `@objc` 的 `ServicesProvider`），拿不到具体 workspace 引用。
/// 此单例是「外部入口 → WorkspaceManager」的唯一桥：处理器 enqueue `Route`，`AppDelegate.drainPendingRoutes`
/// 用 `withObservationTracking` 持续 drain 并经 `WorkspaceManager` 匹配 cwd 激活已有 window 或新建合入。
/// `pending` 是 FIFO 队列（不是单值令牌）——Finder 选中多个文件夹 Open With 会一次投递多条 .open，
/// 每条都需要打开/激活，不能后覆盖前。
/// 唯一消费者是 AppDelegate，WorkspaceRootView 不消费 router.pending。
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

    private(set) var pending: [Route] = []

    /// 生产用单例走 ``shared``；非私有以便单测构造隔离实例，避免污染全局令牌。
    init() {}

    /// 由 `AppDelegate` / `ServicesProvider` 调用，enqueue 一条路由请求。
    func request(_ route: Route) {
        pending.append(route)
    }

    /// `AppDelegate.drainPendingRoutes` 消费首项（FIFO），无待处理路由返回 nil。
    @discardableResult
    func consume() -> Route? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}
