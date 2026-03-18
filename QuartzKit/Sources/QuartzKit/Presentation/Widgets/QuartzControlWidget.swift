#if canImport(WidgetKit) && canImport(AppIntents) && os(iOS)
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Control Center Widget (iOS 18+)

/// Control Center widget for quick note creation.
///
/// Shows a button in Control Center that creates
/// a new Quick Note or opens the app when tapped.
@available(iOS 18.0, *)
public struct QuickNoteControlWidget: ControlWidget {
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.quartz.quicknote") {
            ControlWidgetButton(action: QuickNoteControlIntent()) {
                Label(String(localized: "Quick Note", bundle: .module), systemImage: "square.and.pencil")
            }
        }
        .displayName(String(localized: "Quick Note", bundle: .module))
        .description(String(localized: "Create a new note instantly.", bundle: .module))
    }

    public init() {}
}

/// Intent for the Control Center button.
@available(iOS 18.0, *)
public struct QuickNoteControlIntent: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "Quick Note"
    public static let description = IntentDescription(String(localized: "Opens Quartz for a quick note.", bundle: .module))
    public static let openAppWhenRun: Bool = true
    public static let isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        // Store deep-link target so the app opens Quick Note mode on launch.
        UserDefaults(suiteName: "group.app.quartz.shared")?
            .set("quartz://new", forKey: "pendingDeepLink")
        return .result()
    }
}

// MARK: - Daily Note Control Widget

/// Control Center widget for the daily note.
@available(iOS 18.0, *)
public struct DailyNoteControlWidget: ControlWidget {
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.quartz.dailynote") {
            ControlWidgetButton(action: DailyNoteControlIntent()) {
                Label(String(localized: "Daily Note", bundle: .module), systemImage: "calendar")
            }
        }
        .displayName(String(localized: "Daily Note", bundle: .module))
        .description(String(localized: "Open or create today's daily note.", bundle: .module))
    }

    public init() {}
}

/// Intent for the Daily Note Control Center button.
@available(iOS 18.0, *)
public struct DailyNoteControlIntent: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "Daily Note"
    public static let description = IntentDescription(String(localized: "Opens today's daily note.", bundle: .module))
    public static let openAppWhenRun: Bool = true
    public static let isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.app.quartz.shared")?
            .set("quartz://daily", forKey: "pendingDeepLink")
        return .result()
    }
}
#endif
