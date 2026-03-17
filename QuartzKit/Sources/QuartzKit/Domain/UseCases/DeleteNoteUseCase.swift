import Foundation

/// Use case: Deletes a note from the vault.
public struct DeleteNoteUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Deletes the note at the specified URL (moves to trash on macOS).
    public func execute(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
