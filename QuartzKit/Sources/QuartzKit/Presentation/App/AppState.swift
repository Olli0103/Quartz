import SwiftUI

/// Einzelne Command-Action, ausgelöst durch Keyboard Shortcuts oder Menüs.
/// Ein einzelner enum statt 6 Bool-Toggles vermeidet doppelte SwiftUI-View-Updates.
public enum CommandAction: Equatable, Sendable {
    case none
    case newNote
    case newFolder
    case search
    case globalSearch
    case toggleSidebar
    case dailyNote
}

/// Globaler App-State, per Environment in alle Views injiziert.
@Observable
@MainActor
public final class AppState {
    /// Aktuell geöffneter Vault.
    public var currentVault: VaultConfig?

    /// Dateibaum des aktuellen Vaults.
    public var fileTree: [FileNode] = []

    /// Aktuell ausgewählte Notiz im Editor.
    public var selectedNote: NoteDocument?

    /// Ladeindikator.
    public var isLoading: Bool = false

    /// Fehlermeldung für den Nutzer.
    public var errorMessage: String?

    // MARK: - Command Actions (triggered by keyboard shortcuts)

    /// Pending command action triggered by keyboard shortcuts or menus.
    /// Consumers should reset to `.none` after handling.
    public var pendingCommand: CommandAction = .none

    public init() {}
}
