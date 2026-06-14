import Foundation

@Observable
final class RecentFolders {
    static let shared = RecentFolders()

    private static let maxCount = 10

    private let defaults: UserDefaults
    private let key: String

    private(set) var items: [URL] = []

    private init() {
        self.defaults = .standard
        self.key = "recentFolders"
        let paths = defaults.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
    }

    init(defaults: UserDefaults, key: String = "recentFolders") {
        self.defaults = defaults
        self.key = key
        let paths = defaults.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        items.removeAll { $0.standardizedFileURL == standardized }
        items.insert(standardized, at: 0)
        if items.count > Self.maxCount {
            items = Array(items.prefix(Self.maxCount))
        }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        let paths = items.map { $0.path(percentEncoded: false) }
        defaults.set(paths, forKey: key)
    }
}
