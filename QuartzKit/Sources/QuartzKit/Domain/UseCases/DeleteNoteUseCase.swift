import Foundation

/// Use Case: Löscht eine Notiz aus dem Vault.
public struct DeleteNoteUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Löscht die Notiz an der angegebenen URL (verschiebt in den Papierkorb auf macOS).
    public func execute(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
