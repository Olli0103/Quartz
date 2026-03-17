import Foundation

/// Use case: Creates a new note in the vault.
public struct CreateNoteUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Creates a new note with the given name in the specified folder.
    public func execute(name: String, in folder: URL) async throws -> NoteDocument {
        try await vaultProvider.createNote(named: name, in: folder)
    }
}
