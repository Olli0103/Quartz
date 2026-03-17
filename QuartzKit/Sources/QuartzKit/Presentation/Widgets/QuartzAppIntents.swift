#if canImport(AppIntents)
import AppIntents

// MARK: - Create Note Intent

/// AppIntent: Create a new note via Siri Shortcuts.
@available(iOS 16.0, macOS 13.0, *)
public struct CreateNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Note"
    public static let description: IntentDescription = "Creates a new note in your Quartz vault."
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Title")
    public var noteTitle: String

    @Parameter(title: "Content", default: "")
    public var noteContent: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let useCase = ShareCaptureUseCase()

        // Uses the default vault (in the real app via UserDefaults/AppGroup)
        guard let vaultRoot = defaultVaultURL() else {
            return .result(dialog: IntentDialog(String(localized: "No vault configured. Please open Quartz first.", bundle: .module)))
        }

        let item: SharedItem = .text(noteContent)
        _ = try useCase.capture(item, in: vaultRoot, mode: .newNote(title: noteTitle))

        return .result(dialog: IntentDialog(String(localized: "Note '\(noteTitle)' created!", bundle: .module)))
    }
}

// MARK: - Open Note Intent

/// AppIntent: Open a note via Siri Shortcuts.
@available(iOS 16.0, macOS 13.0, *)
public struct OpenNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Note"
    public static let description: IntentDescription = "Opens a note in Quartz."
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Note Name")
    public var noteName: String

    public init() {}

    public func perform() async throws -> some IntentResult {
        // The app opens automatically (openAppWhenRun = true)
        // Deep link handling occurs in the app
        return .result()
    }
}

// MARK: - Daily Note Intent

/// AppIntent: Create or open today's daily note.
@available(iOS 16.0, macOS 13.0, *)
public struct DailyNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Daily Note"
    public static let description: IntentDescription = "Creates or opens today's daily note."
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let vaultRoot = defaultVaultURL() else {
            return .result(dialog: IntentDialog(String(localized: "No vault configured.", bundle: .module)))
        }

        let templateService = VaultTemplateService()
        let url = try await templateService.createDailyNote(in: vaultRoot)
        return .result(dialog: IntentDialog(String(localized: "Daily note ready: \(url.lastPathComponent)", bundle: .module)))
    }
}

// MARK: - App Shortcuts Provider

/// Registers App Shortcuts for Spotlight and Siri.
@available(iOS 16.0, macOS 13.0, *)
public struct QuartzShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("New Note", bundle: .atURL(Bundle.module.bundleURL)),
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: DailyNoteIntent(),
            phrases: [
                "Open daily note in \(.applicationName)",
                "Today's note in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Daily Note", bundle: .atURL(Bundle.module.bundleURL)),
            systemImageName: "calendar"
        )
    }
}

// MARK: - Helpers

private func defaultVaultURL() -> URL? {
    // In the real app: Read from UserDefaults (AppGroup)
    UserDefaults(suiteName: "group.app.quartz.shared")?.url(forKey: "defaultVaultRoot")
}
#endif
