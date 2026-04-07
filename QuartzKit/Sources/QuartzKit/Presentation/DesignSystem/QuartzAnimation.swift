import SwiftUI

/// Central animation constants for consistent timing values throughout the app.
///
/// Tactile feedback for primary actions lives in ``QuartzFeedback``.
///
/// Uses modern iOS 17+ `.bouncy` and `.smooth` where appropriate for fluid,
/// interruptible physics. Falls back to spring for compatibility.
public enum QuartzAnimation {
    // MARK: - Standard Springs (Interruptible, Fluid)

    /// Fast, snappy interaction (Buttons, Toggles, Selections).
    /// Uses .snappy for interruptible, velocity-tracked feel.
    public static let standard: Animation = .snappy

    /// Fast bounce animation for small elements (Icon-Buttons, Badges).
    /// Uses .bouncy for playful, responsive feedback.
    public static let bounce: Animation = .bouncy(duration: 0.35)

    /// Soft interaction with a bit more motion (Tag selection, Card-Selection).
    public static let soft: Animation = .smooth(duration: 0.35)

    // MARK: - Content Transitions (Fluid, Interruptible)

    /// Medium-speed animation for content transitions (Panels, Expand/Collapse).
    /// Uses .smooth for fluid, non-bouncy transitions.
    public static let content: Animation = .smooth(duration: 0.4)

    /// Larger content transitions (Onboarding-Steps, Lock-Screen).
    /// Slightly longer for deliberate feel.
    public static let smooth: Animation = .smooth(duration: 0.45)

    // MARK: - Appear Animations (Bouncy, Fluid)

    /// Appear animation (FadeIn, SlideUp).
    public static let appear: Animation = .smooth(duration: 0.45)

    /// Staggered appear animation for lists.
    public static let stagger: Animation = .bouncy(duration: 0.4)

    /// Scale-In for Buttons/Icons.
    public static let scaleIn: Animation = .bouncy(duration: 0.4)

    /// SlideUp appear animation.
    public static let slideUp: Animation = .smooth(duration: 0.5)

    /// Onboarding-Step-Transition.
    public static let onboarding: Animation = .smooth(duration: 0.5)

    /// Rubber-Band Bounce.
    public static let rubberBand: Animation = .bouncy(duration: 0.5, extraBounce: 0.3)

    /// Spin-In Rotation.
    public static let spinIn: Animation = .bouncy(duration: 0.45)

    // MARK: - Button Press Styles

    /// Standard-Button press.
    /// response: 0.25, dampingFraction: 0.7
    public static let buttonPress: Animation = .spring(response: 0.25, dampingFraction: 0.7)

    /// Card-Button press (more subtle).
    /// response: 0.2, dampingFraction: 0.75
    public static let cardPress: Animation = .spring(response: 0.2, dampingFraction: 0.75)

    // MARK: - Looping

    /// Pulsing (e.g. save indicator).
    /// response: 0.8, dampingFraction: 0.5
    public static let pulse: Animation = .spring(response: 0.8, dampingFraction: 0.5)

    /// Save indicator pulse.
    /// response: 0.6, dampingFraction: 0.5
    public static let savePulse: Animation = .spring(response: 0.6, dampingFraction: 0.5)

    /// Shimmer effect.
    public static let shimmer: Animation = .easeInOut(duration: 1.5)

    // MARK: - Font Scaling

    /// Editor font size change.
    /// response: 0.3
    public static let fontScale: Animation = .spring(response: 0.3)

    // MARK: - Error/Status

    /// Error/status messages.
    /// response: 0.4, dampingFraction: 0.8
    public static let status: Animation = .spring(response: 0.4, dampingFraction: 0.8)

    // MARK: - Phase-style state transitions (interruptible)

    /// Sidebar folder disclosure expand/collapse — smooth, not flashy.
    public static let folderExpand: Animation = .smooth(duration: 0.32)

    /// Preview vs edit mode toggle (toolbar + content swap) — snappy, restrained.
    public static let previewEditToggle: Animation = .snappy(duration: 0.28)

    /// Focus mode button and hint chrome — light spring.
    public static let focusChrome: Animation = .spring(response: 0.3, dampingFraction: 0.86)
}
