import SwiftUI

/// Manages focus mode and typewriter mode.
///
/// - **Focus Mode:** All UI elements (sidebar, toolbar, status bar) are hidden.
/// - **Typewriter Mode:** State storage is kept for future wiring, but the product
///   surface does not expose it until live editor behavior exists.
@Observable
@MainActor
public final class FocusModeManager {
    private static let focusKey = "quartz.editor.focusModeActive"
    private static let typewriterKey = "quartz.editor.typewriterModeActive"
    public static let exposesTypewriterModeSetting = false

    /// Focus Mode: Hides all UI elements.
    public var isFocusModeActive: Bool = false {
        didSet { UserDefaults.standard.set(isFocusModeActive, forKey: Self.focusKey) }
    }

    /// Reserved state for a future typewriter implementation.
    public var isTypewriterModeActive: Bool = false {
        didSet { UserDefaults.standard.set(isTypewriterModeActive, forKey: Self.typewriterKey) }
    }

    /// Opacity for inactive lines in typewriter mode.
    public var dimmedLineOpacity: Double = 0.3

    public init() {
        // Focus mode always starts OFF — it's a session-only state, not persisted across launches.
        // Users expect the full 3-pane layout when they open the app.
        isFocusModeActive = false

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.typewriterKey) != nil {
            isTypewriterModeActive = defaults.bool(forKey: Self.typewriterKey)
        }
    }

    /// Toggles focus mode.
    public func toggleFocusMode() {
        withAnimation(QuartzAnimation.content) {
            isFocusModeActive.toggle()
        }
    }

    /// Toggles the reserved typewriter mode state.
    public func toggleTypewriterMode() {
        withAnimation(QuartzAnimation.content) {
            isTypewriterModeActive.toggle()
        }
    }
}

// MARK: - SwiftUI Environment

private struct FocusModeManagerKey: EnvironmentKey {
    static var defaultValue: FocusModeManager {
        MainActor.assumeIsolated { FocusModeManager() }
    }
}

extension EnvironmentValues {
    public var focusModeManager: FocusModeManager {
        get { self[FocusModeManagerKey.self] }
        set { self[FocusModeManagerKey.self] = newValue }
    }
}

// MARK: - Focus Mode Modifier

/// ViewModifier that shows/hides UI elements in focus mode.
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
    /// Hides this view in focus mode.
    func hidesInFocusMode() -> some View {
        modifier(FocusModeModifier())
    }
}
