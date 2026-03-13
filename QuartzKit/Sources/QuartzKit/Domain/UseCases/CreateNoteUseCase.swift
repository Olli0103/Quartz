import Foundation

/// Use Case: Erstellt eine neue Notiz im Vault.
public struct CreateNoteUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Erstellt eine neue Notiz mit dem gegebenen Namen im angegebenen Ordner.
    public func execute(name: String, in folder: URL) async throws -> NoteDocument {
        try await vaultProvider.createNote(named: name, in: folder)
    }
}
