import Foundation

/// Service protocol for vault operations on the file system.
///
/// Implementations are actor-isolated to ensure thread-safe file I/O.
public protocol VaultProviding: Actor {
    /// Loads the complete file tree of the vault.
    func loadFileTree(at root: URL) async throws -> [FileNode]

    /// Reads a note from the file system.
    func readNote(at url: URL) async throws -> NoteDocument

    /// Saves a note to the file system.
    func saveNote(_ note: NoteDocument) async throws

    /// Saves a note to the file system, passing the active NSFilePresenter
    /// so NSFileCoordinator skips calling back our own presenter (prevents deadlock).
    func saveNote(_ note: NoteDocument, filePresenter: NSFilePresenter?) async throws

    /// Creates a new note with default frontmatter.
    func createNote(named name: String, in folder: URL) async throws -> NoteDocument

    /// Creates a new note with initial body content (e.g. from voice transcription).
    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument

    /// Deletes a note or folder by moving it into the vault-local hidden trash.
    func deleteNote(at url: URL) async throws

    /// Renames a file or folder.
    func rename(at url: URL, to newName: String) async throws -> URL

    /// Creates a new folder.
    func createFolder(named name: String, in parent: URL) async throws -> URL
}

/// Default implementation: delegates to the no-presenter overload.
/// Existing conformances that don't need presenter support keep working.
public extension VaultProviding {
    func saveNote(_ note: NoteDocument, filePresenter: NSFilePresenter?) async throws {
        try await saveNote(note)
    }
}
