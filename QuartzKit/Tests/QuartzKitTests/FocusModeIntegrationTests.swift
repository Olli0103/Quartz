import Testing
import Foundation
@testable import QuartzKit

// MARK: - Focus Mode Integration Tests

@Suite("FocusModeIntegration")
struct FocusModeIntegrationTests {

    @Test("Typewriter mode persists to UserDefaults")
    @MainActor func typewriterModePersistence() {
        let manager = FocusModeManager()

        // Set typewriter mode on (directly, not via toggleTypewriterMode which uses withAnimation)
        manager.isTypewriterModeActive = true
        #expect(manager.isTypewriterModeActive == true)

        // Value persisted to UserDefaults
        let stored = UserDefaults.standard.bool(forKey: "quartz.editor.typewriterModeActive")
        #expect(stored == true)

        // Turn off
        manager.isTypewriterModeActive = false
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
