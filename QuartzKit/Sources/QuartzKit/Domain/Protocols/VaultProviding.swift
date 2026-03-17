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

    /// Creates a new note with default frontmatter.
    func createNote(named name: String, in folder: URL) async throws -> NoteDocument

    /// Deletes a note (moves to trash).
    func deleteNote(at url: URL) async throws

    /// Renames a file or folder.
    func rename(at url: URL, to newName: String) async throws -> URL

    /// Creates a new folder.
    func createFolder(named name: String, in parent: URL) async throws -> URL
}
