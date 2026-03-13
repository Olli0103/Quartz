import Foundation

/// Repräsentiert eine einzelne Notiz im Vault.
public struct NoteDocument: Identifiable, Sendable {
    public let id: UUID
    public var fileURL: URL
    public var frontmatter: Frontmatter
    public var body: String
    public var canvasData: Data?
    public var isDirty: Bool
    public var lastSyncedAt: Date?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        frontmatter: Frontmatter = Frontmatter(),
        body: String = "",
        canvasData: Data? = nil,
        isDirty: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.frontmatter = frontmatter
        self.body = body
        self.canvasData = canvasData
        self.isDirty = isDirty
        self.lastSyncedAt = lastSyncedAt
    }

    /// Dateiname ohne Erweiterung, als Anzeigename.
    public var displayName: String {
        frontmatter.title ?? fileURL.deletingPathExtension().lastPathComponent
    }
}
