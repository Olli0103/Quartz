#if canImport(WidgetKit) && canImport(AppIntents) && os(iOS)
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Control Center Widget (iOS 18+)

/// Control Center Widget für schnelle Notiz-Erstellung.
///
/// Zeigt einen Button im Control Center, der beim Tippen
/// eine neue Quick Note erstellt oder die App öffnet.
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

/// Intent für den Control Center Button.
@available(iOS 18.0, macOS 15.0, *)
public struct QuickNoteControlIntent: ControlConfigurationIntent {
    public static var title: LocalizedStringResource = "Quick Note"
    public static var description = IntentDescription(String(localized: "Opens Quartz for a quick note.", bundle: .module))
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        // Store deep-link target so the app opens Quick Note mode on launch.
        UserDefaults(suiteName: "group.app.quartz.shared")?
            .set("quartz://new", forKey: "pendingDeepLink")
        return .result()
    }
}

// MARK: - Daily Note Control Widget

/// Control Center Widget für die tägliche Notiz.
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

/// Intent für den Daily Note Control Center Button.
@available(iOS 18.0, macOS 15.0, *)
public struct DailyNoteControlIntent: ControlConfigurationIntent {
    public static var title: LocalizedStringResource = "Daily Note"
    public static var description = IntentDescription(String(localized: "Opens today's daily note.", bundle: .module))
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.app.quartz.shared")?
            .set("quartz://daily", forKey: "pendingDeepLink")
        return .result()
    }
}
#endif
