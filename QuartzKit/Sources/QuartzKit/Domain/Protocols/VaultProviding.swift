import Foundation

/// Service-Protocol für Vault-Operationen auf dem Dateisystem.
///
/// Implementierungen sind als Actor isoliert, um thread-sichere File-I/O zu gewährleisten.
public protocol VaultProviding: Actor {
    /// Lädt den kompletten Dateibaum des Vaults.
    func loadFileTree(at root: URL) async throws -> [FileNode]

    /// Liest eine Notiz vom Dateisystem.
    func readNote(at url: URL) async throws -> NoteDocument

    /// Speichert eine Notiz auf das Dateisystem.
    func saveNote(_ note: NoteDocument) async throws

    /// Erstellt eine neue Notiz mit Default-Frontmatter.
    func createNote(named name: String, in folder: URL) async throws -> NoteDocument

    /// Löscht eine Notiz (verschiebt in den Papierkorb).
    func deleteNote(at url: URL) async throws

    /// Benennt eine Datei oder einen Ordner um.
    func rename(at url: URL, to newName: String) async throws -> URL

    /// Erstellt einen neuen Ordner.
    func createFolder(named name: String, in parent: URL) async throws -> URL
}
