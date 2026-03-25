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

        print("[FolderManagementUseCase] move: \(sourceURL.path) -> \(destinationFolder.path)")
        print("[FolderManagementUseCase] destination: \(destination.path)")

        // Validate source exists
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            print("[FolderManagementUseCase] ERROR: source not found")
            throw FileSystemError.fileNotFound(sourceURL)
        }

        // Validate destination folder exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationFolder.path(percentEncoded: false), isDirectory: &isDir),
              isDir.boolValue else {
            print("[FolderManagementUseCase] ERROR: destination folder not found or not a directory")
            throw FileSystemError.fileNotFound(destinationFolder)
        }

        // Check if destination already exists
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            print("[FolderManagementUseCase] ERROR: destination already exists")
            throw FileSystemError.fileAlreadyExists(destination)
        }

        // Validate destination is inside the same parent hierarchy (prevent path traversal).
        // Resolve symlinks to prevent bypass via symbolic link chains.
        guard destination.resolvingSymlinksInPath().standardizedFileURL.path()
                .hasPrefix(destinationFolder.resolvingSymlinksInPath().standardizedFileURL.path()) else {
            print("[FolderManagementUseCase] ERROR: path traversal detected")
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
                print("[FolderManagementUseCase] moveItem: \(actualSource.path) -> \(actualDest.path)")
                try FileManager.default.moveItem(at: actualSource, to: actualDest)
                print("[FolderManagementUseCase] moveItem succeeded")
            } catch {
                print("[FolderManagementUseCase] moveItem failed: \(error)")
                moveError = error
            }
        }

        if let error = coordinatorError ?? moveError {
            print("[FolderManagementUseCase] coordination error: \(error)")
            throw error
        }

        return destination
    }

    /// Deletes a folder (moves to Trash on macOS).
    public func deleteFolder(at url: URL) async throws {
        try await vaultProvider.deleteNote(at: url)
    }
}
