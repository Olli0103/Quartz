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
    /// Use `switchVault(to:)` to properly release security-scoped resources.
    public var currentVault: VaultConfig?

    /// Switches to a new vault, releasing the security-scoped resource of the previous one.
    public func switchVault(to newVault: VaultConfig?) {
        // Release previous vault's security-scoped resource
        if let previous = currentVault, previous.rootURL != newVault?.rootURL {
            previous.rootURL.stopAccessingSecurityScopedResource()
        }
        currentVault = newVault
    }

    /// Aktuell ausgewählte Notiz im Editor (set via deep linking).
    public var selectedNote: NoteDocument?

    /// Fehlermeldung für den Nutzer (zeigt den ersten Eintrag der Queue).
    public var errorMessage: String? {
        get { errorQueue.first }
        set {
            if let msg = newValue {
                errorQueue.append(msg)
            } else {
                // Dismiss current error; show next in queue
                if !errorQueue.isEmpty { errorQueue.removeFirst() }
            }
        }
    }

    /// Queue of pending error messages.
    private var errorQueue: [String] = []

    /// Dismiss current error and advance to next in queue.
    public func dismissCurrentError() {
        guard !errorQueue.isEmpty else { return }
        errorQueue.removeFirst()
    }

    // MARK: - Command Actions (triggered by keyboard shortcuts)

    /// Pending command action triggered by keyboard shortcuts or menus.
    /// Consumers should reset to `.none` after handling.
    public var pendingCommand: CommandAction = .none

    public init() {}
}
