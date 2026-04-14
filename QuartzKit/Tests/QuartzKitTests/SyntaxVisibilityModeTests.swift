import Testing
import Foundation
@testable import QuartzKit

// MARK: - SyntaxVisibilityMode Tests

@Suite("SyntaxVisibilityMode")
struct SyntaxVisibilityModeTests {

    @Test("All modes have unique raw values")
    func uniqueRawValues() {
        let rawValues = SyntaxVisibilityMode.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == SyntaxVisibilityMode.allCases.count)
    }

    @Test("Three modes defined")
    func threeModesExist() {
        #expect(SyntaxVisibilityMode.allCases.count == 3)
        #expect(SyntaxVisibilityMode.allCases.contains(.full))
        #expect(SyntaxVisibilityMode.allCases.contains(.gentleFade))
        #expect(SyntaxVisibilityMode.allCases.contains(.hiddenUntilCaret))
    }

    @Test("Raw values are human-readable")
    func rawValuesReadable() {
        #expect(SyntaxVisibilityMode.full.rawValue == "full")
        #expect(SyntaxVisibilityMode.gentleFade.rawValue == "gentleFade")
        #expect(SyntaxVisibilityMode.hiddenUntilCaret.rawValue == "hiddenUntilCaret")
    }

    @Test("Round-trip from raw value")
    func roundTrip() {
        for mode in SyntaxVisibilityMode.allCases {
            let restored = SyntaxVisibilityMode(rawValue: mode.rawValue)
            #expect(restored == mode)
        }
    }
}

// MARK: - AppearanceManager Persistence Tests

@Suite("AppearanceManager — Syntax Visibility Persistence")
struct AppearanceManagerSyntaxVisibilityTests {

    @Test("Default syntax visibility mode is .hiddenUntilCaret")
    @MainActor func defaultMode() {
        let defaults = UserDefaults(suiteName: "test.syntaxVisibility.default")!
        defaults.removePersistentDomain(forName: "test.syntaxVisibility.default")
        let manager = AppearanceManager(defaults: defaults)
        #expect(manager.syntaxVisibilityMode == .hiddenUntilCaret)
    }

    @Test("Syntax visibility mode persists across instances")
    @MainActor func persistence() {
        let suiteName = "test.syntaxVisibility.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Set a non-default mode
        let manager1 = AppearanceManager(defaults: defaults)
        manager1.syntaxVisibilityMode = .gentleFade

        // Create a new manager with the same defaults
        let manager2 = AppearanceManager(defaults: defaults)
        #expect(manager2.syntaxVisibilityMode == .gentleFade)

        // Clean up
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("All modes persist correctly")
    @MainActor func allModesPersist() {
        let suiteName = "test.syntaxVisibility.allModes"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        for mode in SyntaxVisibilityMode.allCases {
            let manager = AppearanceManager(defaults: defaults)
            manager.syntaxVisibilityMode = mode

            let restored = AppearanceManager(defaults: defaults)
            #expect(restored.syntaxVisibilityMode == mode, "Mode \(mode.rawValue) should persist")
        }

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Invalid stored value defaults to .hiddenUntilCaret")
    @MainActor func invalidValueDefaultsToHiddenUntilCaret() {
        let suiteName = "test.syntaxVisibility.invalid"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Write an invalid raw value
        defaults.set("nonexistent_mode", forKey: "quartz.appearance.syntaxVisibilityMode")

        let manager = AppearanceManager(defaults: defaults)
        #expect(manager.syntaxVisibilityMode == .hiddenUntilCaret)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - EditorSession integration tested via full editor tests (requires VaultProvider setup)
