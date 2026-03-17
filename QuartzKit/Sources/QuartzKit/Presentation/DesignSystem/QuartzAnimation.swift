import SwiftUI

/// Zentrale Animation-Konstanten für konsistente Timing-Werte in der gesamten App.
///
/// Statt überall eigene `.spring(response:dampingFraction:)` Werte zu verwenden,
/// nutzen wir diese vordefinierten Animationen.
public enum QuartzAnimation {
    // MARK: - Standard Springs

    /// Schnelle, knackige Interaktion (Buttons, Toggles, Selections).
    /// response: 0.3, dampingFraction: 0.8
    public static let standard: Animation = .spring(response: 0.3, dampingFraction: 0.8)

    /// Schnelle Bounce-Animation für kleine Elemente (Icon-Buttons, Badges).
    /// response: 0.25, dampingFraction: 0.5
    public static let bounce: Animation = .spring(response: 0.25, dampingFraction: 0.5)

    /// Sanfte Interaktion mit etwas mehr Bewegung (Tag-Auswahl, Card-Selection).
    /// response: 0.3, dampingFraction: 0.6
    public static let soft: Animation = .spring(response: 0.3, dampingFraction: 0.6)

    // MARK: - Content Transitions

    /// Mittelschnelle Animation für Content-Übergänge (Panels, Expand/Collapse).
    /// response: 0.35, dampingFraction: 0.8
    public static let content: Animation = .spring(response: 0.35, dampingFraction: 0.8)

    /// Größere Content-Transitions (Onboarding-Steps, Lock-Screen).
    /// response: 0.35, dampingFraction: 0.85
    public static let smooth: Animation = .spring(response: 0.35, dampingFraction: 0.85)

    // MARK: - Appear Animations

    /// Einblendung (FadeIn, SlideUp).
    /// response: 0.4, dampingFraction: 0.85
    public static let appear: Animation = .spring(response: 0.4, dampingFraction: 0.85)

    /// Staggered-Einblendung für Listen.
    /// response: 0.4, dampingFraction: 0.82
    public static let stagger: Animation = .spring(response: 0.4, dampingFraction: 0.82)

    /// Scale-In für Buttons/Icons.
    /// response: 0.45, dampingFraction: 0.7
    public static let scaleIn: Animation = .spring(response: 0.45, dampingFraction: 0.7)

    /// SlideUp-Einblendung.
    /// response: 0.5, dampingFraction: 0.8
    public static let slideUp: Animation = .spring(response: 0.5, dampingFraction: 0.8)

    /// Onboarding-Step-Transition.
    /// response: 0.5, dampingFraction: 0.85
    public static let onboarding: Animation = .spring(response: 0.5, dampingFraction: 0.85)

    /// Rubber-Band Bounce.
    /// response: 0.5, dampingFraction: 0.55
    public static let rubberBand: Animation = .spring(response: 0.5, dampingFraction: 0.55)

    /// Spin-In Rotation.
    /// response: 0.5, dampingFraction: 0.6
    public static let spinIn: Animation = .spring(response: 0.5, dampingFraction: 0.6)

    // MARK: - Button Press Styles

    /// Standard-Button press.
    /// response: 0.25, dampingFraction: 0.7
    public static let buttonPress: Animation = .spring(response: 0.25, dampingFraction: 0.7)

    /// Card-Button press (subtiler).
    /// response: 0.2, dampingFraction: 0.75
    public static let cardPress: Animation = .spring(response: 0.2, dampingFraction: 0.75)

    // MARK: - Looping

    /// Pulsieren (z.B. Save-Indikator).
    /// response: 0.8, dampingFraction: 0.5
    public static let pulse: Animation = .spring(response: 0.8, dampingFraction: 0.5)

    /// Save-Indikator Puls.
    /// response: 0.6, dampingFraction: 0.5
    public static let savePulse: Animation = .spring(response: 0.6, dampingFraction: 0.5)

    /// Shimmer-Effekt.
    public static let shimmer: Animation = .linear(duration: 1.5)

    // MARK: - Font Scaling

    /// Editor-Font-Size Änderung.
    /// response: 0.3
    public static let fontScale: Animation = .spring(response: 0.3)

    // MARK: - Error/Status

    /// Fehler-/Status-Meldungen.
    /// response: 0.4, dampingFraction: 0.8
    public static let status: Animation = .spring(response: 0.4, dampingFraction: 0.8)
}
