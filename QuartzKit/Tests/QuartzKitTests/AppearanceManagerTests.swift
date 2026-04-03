import Testing
import Foundation
@testable import QuartzKit

// MARK: - Appearance Manager Tests

/// Verifies defaults and persistence. Consolidated to minimize @Test macro count.

@Suite("AppearanceManager")
struct AppearanceMgrTests {

    @MainActor
    private func isolated() -> AppearanceManager {
        AppearanceManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test("Defaults: theme=system, font=system, size=16, pureDark=false")
    @MainActor func defaults() {
        let m = isolated()
        #expect(m.theme == .system)
        #expect(m.editorFontFamily == .system)
        #expect(m.editorFontSize == 16)
        #expect(m.pureDarkMode == false)
        #expect(m.editorLineSpacing >= 1.0)
    }

    @Test("Persistence round-trips for theme, font, size")
    @MainActor func persistence() {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let m1 = AppearanceManager(defaults: d)
        m1.theme = .dark
        m1.editorFontFamily = .monospaced
        m1.editorFontSize = 20
        let m2 = AppearanceManager(defaults: d)
        #expect(m2.theme == .dark)
        #expect(m2.editorFontFamily == .monospaced)
        #expect(m2.editorFontSize == 20)
    }

    @Test("editorFontScale = size/16, enums have expected case counts")
    @MainActor func computedAndEnums() {
        let m = isolated()
        m.editorFontSize = 24
        #expect(abs(m.editorFontScale - 1.5) < 0.01)
        #expect(AppearanceManager.Theme.allCases.count == 3)
        #expect(AppearanceManager.EditorFontFamily.allCases.count == 4)
    }
}
