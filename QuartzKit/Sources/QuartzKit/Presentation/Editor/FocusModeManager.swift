import SwiftUI

/// Verwaltet den Focus- und Typewriter-Modus.
///
/// - **Focus Mode:** Alle UI-Elemente (Sidebar, Toolbar, Status Bar) werden ausgeblendet.
/// - **Typewriter Mode:** Die aktive Zeile bleibt vertikal zentriert,
///   umgebende Zeilen werden abgedunkelt.
@Observable
@MainActor
public final class FocusModeManager {
    /// Focus Mode: Blendet alle UI-Elemente aus.
    public var isFocusModeActive: Bool = false

    /// Typewriter Mode: Aktive Zeile bleibt zentriert.
    public var isTypewriterModeActive: Bool = false

    /// Opacity für nicht-aktive Zeilen im Typewriter Mode.
    public var dimmedLineOpacity: Double = 0.3

    public init() {}

    /// Toggled Focus Mode.
    public func toggleFocusMode() {
        withAnimation(QuartzAnimation.content) {
            isFocusModeActive.toggle()
        }
    }

    /// Toggled Typewriter Mode.
    public func toggleTypewriterMode() {
        withAnimation(QuartzAnimation.content) {
            isTypewriterModeActive.toggle()
        }
    }
}

// MARK: - SwiftUI Environment

private struct FocusModeManagerKey: EnvironmentKey {
    // SAFETY: Default only accessed from main actor in SwiftUI's
    // environment resolution. Swift 6 EnvironmentKey workaround.
    nonisolated(unsafe) static let defaultValue = FocusModeManager()
}

extension EnvironmentValues {
    public var focusModeManager: FocusModeManager {
        get { self[FocusModeManagerKey.self] }
        set { self[FocusModeManagerKey.self] = newValue }
    }
}

// MARK: - Focus Mode Modifier

/// ViewModifier der UI-Elemente im Focus Mode ein/ausblendet.
public struct FocusModeModifier: ViewModifier {
    @Environment(\.focusModeManager) private var focusMode

    public func body(content: Content) -> some View {
        content
            .opacity(focusMode.isFocusModeActive ? 0 : 1)
            .allowsHitTesting(!focusMode.isFocusModeActive)
            .animation(QuartzAnimation.content, value: focusMode.isFocusModeActive)
    }
}

public extension View {
    /// Blendet diese View im Focus Mode aus.
    func hidesInFocusMode() -> some View {
        modifier(FocusModeModifier())
    }
}
