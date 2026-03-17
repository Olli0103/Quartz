import SwiftUI

/// Verwaltet das Erscheinungsbild der App (Theme, Schriftgröße).
///
/// Wird per `@Environment` in Views injiziert und persistiert
/// Einstellungen in `UserDefaults`.
@Observable
@MainActor
public final class AppearanceManager {
    // MARK: - Theme

    public enum Theme: String, CaseIterable, Codable, Sendable {
        case system
        case light
        case dark

        public var displayName: String {
            switch self {
            case .system: String(localized: "System", bundle: .module)
            case .light: String(localized: "Light", bundle: .module)
            case .dark: String(localized: "Dark", bundle: .module)
            }
        }

        public var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Aktuelles Theme.
    public var theme: Theme {
        didSet { save() }
    }

    /// Editor-Schriftgröße (Skalierungsfaktor relativ zu Dynamic Type).
    public var editorFontScale: Double {
        didSet { save() }
    }

    // MARK: - Init

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = Self.loadTheme(from: defaults)
        self.editorFontScale = defaults.double(forKey: Keys.editorFontScale).clamped(to: 0.8...2.0, default: 1.0)
    }

    // MARK: - Persistence

    private enum Keys {
        static let theme = "quartz.appearance.theme"
        static let editorFontScale = "quartz.appearance.editorFontScale"
    }

    private func save() {
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(editorFontScale, forKey: Keys.editorFontScale)
    }

    private static func loadTheme(from defaults: UserDefaults) -> Theme {
        guard let raw = defaults.string(forKey: Keys.theme),
              let theme = Theme(rawValue: raw) else {
            return .system
        }
        return theme
    }
}

// MARK: - SwiftUI Environment

private struct AppearanceManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = AppearanceManager()
}

extension EnvironmentValues {
    public var appearanceManager: AppearanceManager {
        get { self[AppearanceManagerKey.self] }
        set { self[AppearanceManagerKey.self] = newValue }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        if self == 0 { return defaultValue }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
