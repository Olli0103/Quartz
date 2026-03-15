import Foundation

/// Use Case für Ordner-Operationen im Vault.
public struct FolderManagementUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Erstellt einen neuen Ordner.
    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        try await vaultProvider.createFolder(named: name, in: parent)
    }

    /// Benennt eine Datei oder einen Ordner um.
    public func rename(at url: URL, to newName: String) async throws -> URL {
        try await vaultProvider.rename(at: url, to: newName)
    }

    /// Verschiebt eine Datei oder einen Ordner.
    public func move(at sourceURL: URL, to destinationFolder: URL) async throws -> URL {
        let source = sourceURL
        let destFolder = destinationFolder
        return try await Task.detached(priority: .userInitiated) {
            let fileName = source.lastPathComponent
            let destination = destFolder.appending(path: fileName)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }.value
    }

    /// Löscht einen Ordner (verschiebt in den Papierkorb auf macOS).
    public func deleteFolder(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
