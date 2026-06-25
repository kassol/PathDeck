import Testing
import Foundation
@testable import PathDeck

@MainActor
struct WorkspacePreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "WorkspacePreferencesTests-\(UUID().uuidString)")!
        suite.removePersistentDomain(forName: "WorkspacePreferencesTests-")
        return suite
    }

    @Test
    func defaultValuesWhenEmpty() {
        let prefs = WorkspacePreferences(defaults: makeDefaults())
        #expect(prefs.sortColumn == .name)
        #expect(prefs.sortAscending == true)
        #expect(prefs.showHidden == false)
        #expect(prefs.bottomPanelHeight == 250)
        #expect(prefs.verticalTabWidth == 140)
        #expect(prefs.isPreviewPaneVisible == true)
    }

    @Test
    func sortColumnPersistsOnAssignment() {
        let suite = makeDefaults()
        let prefs = WorkspacePreferences(defaults: suite)
        prefs.sortColumn = .size
        #expect(suite.string(forKey: "sortColumn") == SortColumn.size.rawValue)
    }

    @Test
    func showHiddenPersists() {
        let suite = makeDefaults()
        let prefs = WorkspacePreferences(defaults: suite)
        prefs.showHidden = true
        #expect(suite.bool(forKey: "showHidden") == true)
    }

    @Test
    func bottomPanelHeightPersists() {
        let suite = makeDefaults()
        let prefs = WorkspacePreferences(defaults: suite)
        prefs.bottomPanelHeight = 320
        #expect(suite.double(forKey: "bottomPanelHeight") == 320)
    }

    @Test
    func restoresFromStoredValues() {
        let suite = makeDefaults()
        suite.set(SortColumn.date.rawValue, forKey: "sortColumn")
        suite.set(false, forKey: "sortAscending")
        suite.set(true, forKey: "showHidden")
        suite.set(300.0, forKey: "bottomPanelHeight")
        suite.set(180.0, forKey: "verticalTabWidth")
        suite.set(false, forKey: "previewPaneVisible")
        let prefs = WorkspacePreferences(defaults: suite)
        #expect(prefs.sortColumn == .date)
        #expect(prefs.sortAscending == false)
        #expect(prefs.showHidden == true)
        #expect(prefs.bottomPanelHeight == 300)
        #expect(prefs.verticalTabWidth == 180)
        #expect(prefs.isPreviewPaneVisible == false)
    }
}
