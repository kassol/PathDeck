import Testing
import Foundation
@testable import PathDeck

struct IgnoreRulesTests {
    @Test func exactMatch() {
        #expect(IgnoreRules.shouldIgnore(fileName: ".DS_Store"))
        #expect(IgnoreRules.shouldIgnore(fileName: ".git"))
        #expect(IgnoreRules.shouldIgnore(fileName: "node_modules"))
    }

    @Test func wildcardMatch() {
        #expect(IgnoreRules.shouldIgnore(fileName: "session.swp"))
        #expect(IgnoreRules.shouldIgnore(fileName: "backup.swo"))
    }

    @Test func normalFileNotIgnored() {
        #expect(!IgnoreRules.shouldIgnore(fileName: "main.swift"))
        #expect(!IgnoreRules.shouldIgnore(fileName: "README.md"))
        #expect(!IgnoreRules.shouldIgnore(fileName: "package.json"))
    }

    @Test func caseInsensitive() {
        #expect(IgnoreRules.shouldIgnore(fileName: ".ds_store"))
        #expect(IgnoreRules.shouldIgnore(fileName: ".DS_STORE"))
        #expect(IgnoreRules.shouldIgnore(fileName: ".Git"))
    }

    @Test func userPatternsApplied() {
        let key = "ChangeJournalIgnorePatterns"
        let original = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        UserDefaults.standard.set(["*.log", "temp_*"], forKey: key)
        #expect(IgnoreRules.shouldIgnore(fileName: "app.log"))
        #expect(IgnoreRules.shouldIgnore(fileName: "temp_file"))
        #expect(!IgnoreRules.shouldIgnore(fileName: "main.swift"))
    }

    @Test func emptyPatternsNoFilter() {
        let key = "ChangeJournalIgnorePatterns"
        let original = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        UserDefaults.standard.set([] as [String], forKey: key)
        #expect(!IgnoreRules.shouldIgnore(fileName: "main.swift"))
        #expect(IgnoreRules.shouldIgnore(fileName: ".DS_Store"))
    }
}
