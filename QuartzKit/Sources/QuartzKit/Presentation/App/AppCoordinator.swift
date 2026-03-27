import SwiftUI

// MARK: - Sheet Routing

/// Every sheet the app can present — mutually exclusive.
///
/// Using a single `Identifiable` enum with `.sheet(item:)` replaces the
/// fragile chain of 10+ `.sheet(isPresented:)` modifiers. SwiftUI guarantees
/// only one `item`-based sheet is active at a time, and setting the binding
/// to `nil` dismisses it.
///
/// Platform-specific cases (e.g. `.knowledgeGraph`) exist on all platforms
/// but the view builder returns `EmptyView()` on unsupported platforms.
public enum AppSheet: Identifiable {
    case onboarding
    case vaultPicker
    case settings
    case search
    case knowledgeGraph
    case voiceNote
    case meetingMinutes
    case vaultChat(session: VaultChatSession)
    case vaultChat2(session: VaultChatSession2)
    case conflictResolver

    public var id: String {
        switch self {
        case .onboarding: "onboarding"
        case .vaultPicker: "vaultPicker"
        case .settings: "settings"
        case .search: "search"
        case .knowledgeGraph: "knowledgeGraph"
        case .voiceNote: "voiceNote"
        case .meetingMinutes: "meetingMinutes"
        case .vaultChat: "vaultChat"
        case .vaultChat2: "vaultChat2"
        case .conflictResolver: "conflictResolver"
        }
    }
}

// MARK: - Alert Routing

/// Every alert the app can present.
///
/// Groups related state together so it can't desync. For example,
/// `newNote` bundles the parent URL and suggested name into a single value
/// instead of spreading them across three `@State` variables.
public enum AppAlert: Identifiable {
    case newNote(parent: URL, suggestedName: String)
    case newFolder(parent: URL)

    public var id: String {
        switch self {
        case .newNote: "newNote"
        case .newFolder: "newFolder"
        }
    }
}

// MARK: - App Coordinator

/// Centralized routing state for sheets, alerts, and app-level lifecycle.
///
/// Replaces the ~15 scattered `@State` booleans that lived in `ContentView`.
/// ContentView becomes a thin layout shell that reads from this coordinator.
///
/// **Pattern:** `@Observable` + `@MainActor` per Master Plan §4.
/// **Anti-pattern avoided:** Boolean explosion, `inout`-heavy command handler.
@Observable
@MainActor
public final class AppCoordinator {

    // MARK: - Sheet State

    /// The currently presented sheet, or `nil` if none is active.
    /// Only one sheet can be active at a time (SwiftUI constraint).
    public var activeSheet: AppSheet?

    // MARK: - Command Palette

    /// Whether the command palette overlay is visible.
    /// NOT a sheet — it's a ZStack overlay that coexists with other UI.
    public var isCommandPaletteVisible: Bool = false

    // MARK: - Alert State

    /// The currently presented alert, or `nil` if none is active.
    public var activeAlert: AppAlert?

    // MARK: - Lifecycle (non-modal)

    /// macOS global hotkey manager. Not a modal — lifecycle-scoped.
    #if os(macOS)
    public var quickNoteManager: QuickNoteManager?
    #endif

    /// Available app update info from GitHub Releases.
    public var availableUpdate: UpdateChecker.ReleaseInfo?

    // MARK: - Init

    public init() {}

    // MARK: - Convenience Presenters

    /// Presents the new-note alert with a date-based default name.
    public func presentNewNote(in parent: URL) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH-mm"
        activeAlert = .newNote(
            parent: parent,
            suggestedName: "Note \(df.string(from: Date()))"
        )
    }

    /// Presents the new-folder alert.
    public func presentNewFolder(in parent: URL) {
        activeAlert = .newFolder(parent: parent)
    }
}
