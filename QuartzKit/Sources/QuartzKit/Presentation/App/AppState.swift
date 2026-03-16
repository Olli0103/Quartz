import SwiftUI

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

    /// Toggled to trigger a new note action from menu commands.
    public var newNoteAction: Bool = false
    /// Toggled to trigger a new folder action from menu commands.
    public var newFolderAction: Bool = false
    /// Toggled to trigger the search overlay from menu commands.
    public var searchAction: Bool = false
    /// Toggled to trigger vault-wide search from menu commands.
    public var globalSearchAction: Bool = false
    /// Toggled to trigger sidebar visibility toggle from menu commands.
    public var toggleSidebarAction: Bool = false
    /// Toggled to trigger daily note creation from menu commands.
    public var dailyNoteAction: Bool = false

    public init() {}
}
