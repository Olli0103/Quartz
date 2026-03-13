#if canImport(WidgetKit) && canImport(AppIntents)
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
                Label("Quick Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("Quick Note")
        .description("Create a new note instantly.")
    }

    public init() {}
}

/// Intent für den Control Center Button.
@available(iOS 18.0, macOS 15.0, *)
public struct QuickNoteControlIntent: ControlConfigurationIntent {
    public static var title: LocalizedStringResource = "Quick Note"
    public static var description = IntentDescription("Opens Quartz for a quick note.")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        // App öffnet sich automatisch, Deep-Link zu Quick Note Mode
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
                Label("Daily Note", systemImage: "calendar")
            }
        }
        .displayName("Daily Note")
        .description("Open or create today's daily note.")
    }

    public init() {}
}

/// Intent für den Daily Note Control Center Button.
@available(iOS 18.0, macOS 15.0, *)
public struct DailyNoteControlIntent: ControlConfigurationIntent {
    public static var title: LocalizedStringResource = "Daily Note"
    public static var description = IntentDescription("Opens today's daily note.")
    public static var openAppWhenRun: Bool = true
    public static var isDiscoverable: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        return .result()
    }
}
#endif
