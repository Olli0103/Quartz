import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - E2E Appearance Flow Tests

@Suite("E2EAppearanceFlow")
struct E2EAppearanceFlowTests {

    @Test("AppearanceManager full persist/restore cycle")
    @MainActor func persistRestoreCycle() {
        let suiteName = "AppearanceE2E-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Create manager and set values
        let manager = AppearanceManager(defaults: defaults)
        manager.theme = .dark
        manager.editorFontSize = 18
        manager.editorFontFamily = .serif
        manager.pureDarkMode = true
        manager.vibrantTransparency = false
        manager.accentColorHex = 0xFF3B30

        // Create a new manager from same defaults (simulates app relaunch)
        let restored = AppearanceManager(defaults: defaults)
        #expect(restored.theme == .dark)
        #expect(restored.editorFontSize == 18)
        #expect(restored.editorFontFamily == .serif)
        #expect(restored.pureDarkMode == true)
        #expect(restored.vibrantTransparency == false)
        #expect(restored.accentColorHex == 0xFF3B30)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Accent color from hex produces valid Color")
    @MainActor func accentColorHex() {
        let suiteName = "AccentColorE2E-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AppearanceManager(defaults: defaults)

        // Set to known blue
        manager.accentColorHex = 0x007AFF
        #expect(manager.accentColorHex == 0x007AFF)

        // accentColor computed property should resolve
        let color = manager.accentColor
        #expect(type(of: color) == SwiftUI.Color.self)

        // Change to red
        manager.accentColorHex = 0xFF3B30
        #expect(manager.accentColorHex == 0xFF3B30)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
