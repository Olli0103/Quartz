import SwiftUI

/// Manages the app's appearance (theme, font, spacing, dark mode).
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

    // MARK: - Editor Font Family

    public enum EditorFontFamily: String, CaseIterable, Codable, Sendable {
        case system      // SF Pro
        case serif       // New York
        case monospaced  // SF Mono
        case rounded     // SF Rounded

        public var displayName: String {
            switch self {
            case .system:     String(localized: "System", bundle: .module)
            case .serif:      String(localized: "Serif", bundle: .module)
            case .monospaced: String(localized: "Monospaced", bundle: .module)
            case .rounded:    String(localized: "Rounded", bundle: .module)
            }
        }
    }

    // MARK: - Properties

    public var theme: Theme {
        didSet { save() }
    }

    /// Editor font family (System, Serif, Monospaced, Rounded).
    public var editorFontFamily: EditorFontFamily {
        didSet { save() }
    }

    /// Editor font size in points (12–24).
    public var editorFontSize: CGFloat {
        didSet { save() }
    }

    /// Editor font scale — computed from editorFontSize for backward compatibility.
    public var editorFontScale: Double {
        get { Double(editorFontSize) / 16.0 }
        set { editorFontSize = CGFloat(newValue * 16.0).clamped(to: 12...24, default: 16) }
    }

    /// Line height multiplier (1.0–2.5).
    public var editorLineSpacing: CGFloat {
        didSet { save() }
    }

    /// Maximum text column width in points (400–1200).
    public var editorMaxWidth: CGFloat {
        didSet { save() }
    }

    /// True black background in dark mode (for OLED displays).
    public var pureDarkMode: Bool {
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

    /// Whether to show the dashboard when no note is selected (macOS only).
    public var showDashboardOnLaunch: Bool {
        didSet { save() }
    }

    /// How syntax delimiters (`**`, `#`, `` ` ``) are displayed in the editor.
    public var syntaxVisibilityMode: SyntaxVisibilityMode {
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
        self.editorFontFamily = Self.loadFontFamily(from: defaults)
        self.editorFontSize = defaults.double(forKey: Keys.editorFontSize).clamped(to: 12...24, default: 16)
        self.editorLineSpacing = defaults.double(forKey: Keys.editorLineSpacing).clamped(to: 1.0...2.5, default: 1.5)
        self.editorMaxWidth = defaults.double(forKey: Keys.editorMaxWidth).clamped(to: 400...1200, default: 720)
        self.pureDarkMode = defaults.object(forKey: Keys.pureDarkMode) as? Bool ?? false
        self.vibrantTransparency = defaults.object(forKey: Keys.vibrantTransparency) as? Bool ?? true
        self.accentColorHex = UInt(defaults.integer(forKey: Keys.accentColorHex)).clamped(to: 1...0xFFFFFF, default: 0xF2994A)
        self.showDashboardOnLaunch = defaults.object(forKey: Keys.showDashboardOnLaunch) as? Bool ?? true
        self.syntaxVisibilityMode = Self.loadSyntaxVisibilityMode(from: defaults)

        // Migration: if editorFontSize was never set but editorFontScale was, derive size
        if defaults.object(forKey: Keys.editorFontSize) == nil {
            let oldScale = defaults.double(forKey: Keys.editorFontScale)
            if oldScale > 0 {
                self.editorFontSize = round(16 * oldScale).clamped(to: 12...24, default: 16)
            }
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let theme = "quartz.appearance.theme"
        static let editorFontScale = "quartz.appearance.editorFontScale"
        static let editorFontFamily = "quartz.appearance.editorFontFamily"
        static let editorFontSize = "quartz.appearance.editorFontSize"
        static let editorLineSpacing = "quartz.appearance.editorLineSpacing"
        static let editorMaxWidth = "quartz.appearance.editorMaxWidth"
        static let pureDarkMode = "quartz.appearance.pureDarkMode"
        static let vibrantTransparency = "quartz.appearance.vibrantTransparency"
        static let accentColorHex = "quartz.appearance.accentColorHex"
        static let showDashboardOnLaunch = "quartz.appearance.showDashboardOnLaunch"
        static let syntaxVisibilityMode = "quartz.appearance.syntaxVisibilityMode"
    }

    private func save() {
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(editorFontFamily.rawValue, forKey: Keys.editorFontFamily)
        defaults.set(Double(editorFontSize), forKey: Keys.editorFontSize)
        defaults.set(editorFontScale, forKey: Keys.editorFontScale)
        defaults.set(Double(editorLineSpacing), forKey: Keys.editorLineSpacing)
        defaults.set(Double(editorMaxWidth), forKey: Keys.editorMaxWidth)
        defaults.set(pureDarkMode, forKey: Keys.pureDarkMode)
        defaults.set(vibrantTransparency, forKey: Keys.vibrantTransparency)
        defaults.set(Int(accentColorHex), forKey: Keys.accentColorHex)
        defaults.set(showDashboardOnLaunch, forKey: Keys.showDashboardOnLaunch)
        defaults.set(syntaxVisibilityMode.rawValue, forKey: Keys.syntaxVisibilityMode)
    }

    private static func loadTheme(from defaults: UserDefaults) -> Theme {
        guard let raw = defaults.string(forKey: Keys.theme),
              let theme = Theme(rawValue: raw) else {
            return .system
        }
        return theme
    }

    private static func loadFontFamily(from defaults: UserDefaults) -> EditorFontFamily {
        guard let raw = defaults.string(forKey: Keys.editorFontFamily),
              let family = EditorFontFamily(rawValue: raw) else {
            return .system
        }
        return family
    }

    private static func loadSyntaxVisibilityMode(from defaults: UserDefaults) -> SyntaxVisibilityMode {
        guard let raw = defaults.string(forKey: Keys.syntaxVisibilityMode),
              let mode = SyntaxVisibilityMode(rawValue: raw) else {
            return .hiddenUntilCaret
        }
        return mode
    }
}

// MARK: - SwiftUI Environment

private struct AppearanceManagerKey: EnvironmentKey {
    static var defaultValue: AppearanceManager {
        MainActor.assumeIsolated { AppearanceManager() }
    }
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

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, default defaultValue: CGFloat) -> CGFloat {
        if self == 0 { return defaultValue }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
