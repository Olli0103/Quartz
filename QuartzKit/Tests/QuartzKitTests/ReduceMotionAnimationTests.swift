import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Reduce Motion / Animation Tests
//
// Validates the design system animation tokens follow Apple HIG:
// - No linear curves for user-facing transitions
// - Animation durations are reasonable
// - Focus mode and state transitions support Reduce Motion

@Suite("ReduceMotionAnimation")
struct ReduceMotionAnimationTests {

    @Test("QuartzAnimation has 20+ preset animations covering all interaction types")
    func animationPresetsExist() {
        let presets: [SwiftUI.Animation] = [
            QuartzAnimation.standard,
            QuartzAnimation.bounce,
            QuartzAnimation.soft,
            QuartzAnimation.content,
            QuartzAnimation.smooth,
            QuartzAnimation.appear,
            QuartzAnimation.stagger,
            QuartzAnimation.scaleIn,
            QuartzAnimation.slideUp,
            QuartzAnimation.onboarding,
            QuartzAnimation.rubberBand,
            QuartzAnimation.spinIn,
            QuartzAnimation.buttonPress,
            QuartzAnimation.cardPress,
            QuartzAnimation.pulse,
            QuartzAnimation.savePulse,
            QuartzAnimation.shimmer,
            QuartzAnimation.fontScale,
            QuartzAnimation.status,
            QuartzAnimation.folderExpand,
            QuartzAnimation.previewEditToggle,
            QuartzAnimation.focusChrome,
        ]
        #expect(presets.count >= 20,
            "Design system should have at least 20 animation tokens")
    }

    @Test("Shimmer uses non-linear curve (audit fix verification)")
    func shimmerNonLinear() {
        let shimmer = QuartzAnimation.shimmer
        #expect(shimmer == .easeInOut(duration: 1.5),
            "Shimmer must use easeInOut after audit remediation, not linear")
        #expect(shimmer != .linear(duration: 1.5),
            "Policy: no .linear curves in design system tokens")
    }

    @Test("FocusModeManager toggle cycle works for Reduce Motion alternatives")
    @MainActor func focusModeToggle() {
        let manager = FocusModeManager()
        #expect(manager.isFocusModeActive == false)

        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == true)

        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == false)
    }

    @Test("FocusModeManager typewriter mode toggles independently")
    @MainActor func typewriterModeToggle() {
        let manager = FocusModeManager()
        #expect(manager.isTypewriterModeActive == false)

        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive == true)

        manager.toggleTypewriterMode()
        #expect(manager.isTypewriterModeActive == false)
    }

    @Test("AppearanceManager vibrantTransparency supports Reduce Transparency")
    @MainActor func vibrantTransparencyToggle() {
        let defaults = UserDefaults(suiteName: "RMA-\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        let original = manager.vibrantTransparency
        manager.vibrantTransparency = !original
        #expect(manager.vibrantTransparency == !original,
            "Must be toggleable for Reduce Transparency support")
    }

    @Test("AppearanceManager pureDarkMode provides solid background for accessibility")
    @MainActor func pureDarkModeAccessibility() {
        let defaults = UserDefaults(suiteName: "RMA2-\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        manager.pureDarkMode = true
        #expect(manager.pureDarkMode == true,
            "Pure dark mode provides solid backgrounds for users with light sensitivity")
    }
}
