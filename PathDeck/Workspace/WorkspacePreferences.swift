import Foundation
import Observation

/// 全局 app 级偏好单实例（@Observable）。所有 NSWindow workspace 共享同一份。
/// 排序、隐藏文件等用户偏好改一处，所有 window 同步生效。
@Observable
final class WorkspacePreferences {
    static let shared = WorkspacePreferences()

    var sortColumn: SortColumn {
        didSet { persistSortColumn() }
    }
    var sortAscending: Bool {
        didSet { persistSortAscending() }
    }
    var showHidden: Bool {
        didSet { persistShowHidden() }
    }
    var bottomPanelHeight: CGFloat {
        didSet { persistBottomPanelHeight() }
    }
    var verticalTabWidth: CGFloat {
        didSet { persistVerticalTabWidth() }
    }
    var isPreviewPaneVisible: Bool {
        didSet { persistPreviewPaneVisible() }
    }

    private let defaults: UserDefaults

    private static let sortColumnKey = "sortColumn"
    private static let sortAscendingKey = "sortAscending"
    private static let showHiddenKey = "showHidden"
    private static let bottomPanelHeightKey = "bottomPanelHeight"
    private static let verticalTabWidthKey = "verticalTabWidth"
    private static let previewPaneVisibleKey = "previewPaneVisible"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Self.sortColumnKey),
           let col = SortColumn(rawValue: raw) {
            sortColumn = col
        } else {
            sortColumn = .name
        }
        sortAscending = defaults.object(forKey: Self.sortAscendingKey) != nil
            ? defaults.bool(forKey: Self.sortAscendingKey) : true
        showHidden = defaults.object(forKey: Self.showHiddenKey) != nil
            ? defaults.bool(forKey: Self.showHiddenKey) : false
        bottomPanelHeight = defaults.object(forKey: Self.bottomPanelHeightKey) != nil
            ? CGFloat(defaults.double(forKey: Self.bottomPanelHeightKey)) : 250
        verticalTabWidth = defaults.object(forKey: Self.verticalTabWidthKey) != nil
            ? CGFloat(defaults.double(forKey: Self.verticalTabWidthKey)) : 140
        isPreviewPaneVisible = defaults.object(forKey: Self.previewPaneVisibleKey) != nil
            ? defaults.bool(forKey: Self.previewPaneVisibleKey) : true
    }

    private func persistSortColumn() { defaults.set(sortColumn.rawValue, forKey: Self.sortColumnKey) }
    private func persistSortAscending() { defaults.set(sortAscending, forKey: Self.sortAscendingKey) }
    private func persistShowHidden() { defaults.set(showHidden, forKey: Self.showHiddenKey) }
    private func persistBottomPanelHeight() { defaults.set(Double(bottomPanelHeight), forKey: Self.bottomPanelHeightKey) }
    private func persistVerticalTabWidth() { defaults.set(Double(verticalTabWidth), forKey: Self.verticalTabWidthKey) }
    private func persistPreviewPaneVisible() { defaults.set(isPreviewPaneVisible, forKey: Self.previewPaneVisibleKey) }
}
