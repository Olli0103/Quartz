import SwiftUI

/// Manages the app's appearance (theme, font size).
///
/// Injected into views via `@Environment` and persists
/// settings in `UserDefaults`.
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

    /// Current theme.
    public var theme: Theme {
        didSet { save() }
    }

    /// Editor font size (scale factor relative to Dynamic Type).
    public var editorFontScale: Double {
        didSet { save() }
    }

    /// Vibrant transparency (glass effect on sidebar/title bar).
    public var vibrantTransparency: Bool {
        didSet { save() }
    }

    /// Accent color as hex (e.g. 0xF2994A for orange).
    public var accentColorHex: UInt {
        didSet { save() }
    }

    /// Resolved accent color for tinting the app.
    public var accentColor: Color {
        Color(hex: accentColorHex)
    }

    // MARK: - Init

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = Self.loadTheme(from: defaults)
        self.editorFontScale = defaults.double(forKey: Keys.editorFontScale).clamped(to: 0.8...2.0, default: 1.0)
        self.vibrantTransparency = defaults.object(forKey: Keys.vibrantTransparency) as? Bool ?? true
        self.accentColorHex = UInt(defaults.integer(forKey: Keys.accentColorHex)).clamped(to: 1...0xFFFFFF, default: 0xF2994A)
    }

    // MARK: - Persistence

    private enum Keys {
        static let theme = "quartz.appearance.theme"
        static let editorFontScale = "quartz.appearance.editorFontScale"
        static let vibrantTransparency = "quartz.appearance.vibrantTransparency"
        static let accentColorHex = "quartz.appearance.accentColorHex"
    }

    private func save() {
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(editorFontScale, forKey: Keys.editorFontScale)
        defaults.set(vibrantTransparency, forKey: Keys.vibrantTransparency)
        defaults.set(Int(accentColorHex), forKey: Keys.accentColorHex)
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

private struct AppearanceManagerKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppearanceManager()
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

private extension UInt {
    func clamped(to range: ClosedRange<UInt>, default defaultValue: UInt) -> UInt {
        if self == 0 { return defaultValue }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
