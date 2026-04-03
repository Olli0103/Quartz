import Testing
import Foundation
@testable import QuartzKit

// MARK: - Focus Mode Integration Tests

@Suite("FocusModeIntegration")
struct FocusModeIntegrationTests {

    @Test("Typewriter mode persists to UserDefaults")
    @MainActor func typewriterModePersistence() {
        let manager = FocusModeManager()

        // Toggle typewriter mode on
        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive == true)

        // Value persisted to UserDefaults
        let stored = UserDefaults.standard.bool(forKey: "quartz.editor.typewriterModeActive")
        #expect(stored == true)

        // Toggle off
        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive == false)
        let storedOff = UserDefaults.standard.bool(forKey: "quartz.editor.typewriterModeActive")
        #expect(storedOff == false)
    }

    @Test("Focus mode does NOT persist across launches")
    @MainActor func focusModeTransient() {
        let manager = FocusModeManager()

        // Toggle on
        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == true)

        // Create a new instance (simulates relaunch)
        let freshManager = FocusModeManager()
        #expect(freshManager.isFocusModeActive == false)
    }
}
