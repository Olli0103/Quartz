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
        let fileName = sourceURL.lastPathComponent
        let destination = destinationFolder.appending(path: fileName)

        // Validate destination is inside the same parent hierarchy (prevent path traversal)
        guard destination.standardizedFileURL.path()
                .hasPrefix(destinationFolder.standardizedFileURL.path()) else {
            throw FileSystemError.invalidName(fileName)
        }

        // Use file coordination for iCloud-safe moves
        var coordinatorError: NSError?
        var moveError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: sourceURL, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinatorError
        ) { actualSource, actualDest in
            do {
                try FileManager.default.moveItem(at: actualSource, to: actualDest)
            } catch {
                moveError = error
            }
        }

        if let error = coordinatorError ?? moveError {
            throw error
        }

        return destination
    }

    /// Löscht einen Ordner (verschiebt in den Papierkorb auf macOS).
    public func deleteFolder(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
