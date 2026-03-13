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

    public init() {}
}
