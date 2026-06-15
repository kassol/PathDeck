import Foundation
import Darwin

struct IgnoreRules {
    static let defaultPatterns: [String] = [
        ".DS_Store", ".git", "node_modules",
        "build", "dist", ".cache",
        "venv", "__pycache__",
        "*.swp", "*.swo", "*.tmp",
        ".Spotlight-V100", ".Trashes", ".fseventsd",
        "*.sb-*", "._*",
    ]

    private static let userDefaultsKey = "ChangeJournalIgnorePatterns"

    static var userPatterns: [String] {
        get { UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    static var allPatterns: [String] {
        defaultPatterns + userPatterns
    }

    static func shouldIgnore(fileName: String) -> Bool {
        allPatterns.contains { pattern in
            fnmatch(pattern, fileName, FNM_CASEFOLD) == 0
        }
    }
}
