import Foundation

/// Use case for folder operations in the vault.
public struct FolderManagementUseCase: Sendable {
    private let vaultProvider: any VaultProviding

    public init(vaultProvider: any VaultProviding) {
        self.vaultProvider = vaultProvider
    }

    /// Creates a new folder.
    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        try await vaultProvider.createFolder(named: name, in: parent)
    }

    /// Renames a file or folder.
    public func rename(at url: URL, to newName: String) async throws -> URL {
        try await vaultProvider.rename(at: url, to: newName)
    }

    /// Moves a file or folder.
    public func move(at sourceURL: URL, to destinationFolder: URL) async throws -> URL {
        let fileName = sourceURL.lastPathComponent
        let destination = destinationFolder.appending(path: fileName)

        // Validate destination is inside the same parent hierarchy (prevent path traversal).
        // Resolve symlinks to prevent bypass via symbolic link chains.
        guard destination.resolvingSymlinksInPath().standardizedFileURL.path()
                .hasPrefix(destinationFolder.resolvingSymlinksInPath().standardizedFileURL.path()) else {
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

    /// Deletes a folder (moves to Trash on macOS).
    public func deleteFolder(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
