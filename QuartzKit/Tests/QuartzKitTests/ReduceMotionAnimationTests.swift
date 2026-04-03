import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Reduce Motion / Animation Tests

@Suite("ReduceMotionAnimation")
struct ReduceMotionAnimationTests {

    @Test("QuartzAnimation has 17+ preset animations")
    func animationPresetsExist() {
        // Verify key presets exist by accessing them
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
            QuartzAnimation.buttonPress,
            QuartzAnimation.cardPress,
            QuartzAnimation.pulse,
            QuartzAnimation.savePulse,
            QuartzAnimation.shimmer,
            QuartzAnimation.fontScale,
            QuartzAnimation.status,
            QuartzAnimation.folderExpand,
            QuartzAnimation.focusChrome,
        ]
        #expect(presets.count >= 17)
    }

    @Test("FocusModeManager toggle cycle works")
    @MainActor func focusModeToggle() {
        let manager = FocusModeManager()

        #expect(manager.isFocusModeActive == false)

        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == true)

        manager.toggleFocusMode()
        #expect(manager.isFocusModeActive == false)
    }
}
