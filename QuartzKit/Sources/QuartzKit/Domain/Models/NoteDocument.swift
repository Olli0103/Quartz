import Foundation

/// Canonical note identity for routing, persistence, and editor sessions.
///
/// Quartz uses the note's standardized file URL as the one explicit identity model.
/// A move or rename changes this identity intentionally. Clean external reloads keep it.
public struct CanonicalNoteIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = Self.canonicalFileURL(for: fileURL)
    }

    public var description: String {
        fileURL.path(percentEncoded: false)
    }

    public static func canonicalFileURL(for fileURL: URL) -> URL {
        fileURL.standardizedFileURL
    }
}

/// Represents a single note in the vault.
public struct NoteDocument: Identifiable, Sendable {
    public typealias ID = CanonicalNoteIdentity

    /// Canonical note identity. This is derived from `fileURL` and is the only supported
    /// runtime identity model for editor sessions, routing, persistence, and window flows.
    public var id: CanonicalNoteIdentity { CanonicalNoteIdentity(fileURL: fileURL) }

    /// Canonical file URL for this note. Setters are normalized immediately so every layer
    /// sees the same path representation.
    public var fileURL: URL {
        get { storedFileURL }
        set { storedFileURL = CanonicalNoteIdentity.canonicalFileURL(for: newValue) }
    }
    public var frontmatter: Frontmatter
    public var body: String
    public var canvasData: Data?
    public var isDirty: Bool
    public var lastSyncedAt: Date?

    private var storedFileURL: URL

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        frontmatter: Frontmatter = Frontmatter(),
        body: String = "",
        canvasData: Data? = nil,
        isDirty: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        _ = id // Legacy UUID parameter retained for source compatibility; canonical identity is file URL.
        self.storedFileURL = CanonicalNoteIdentity.canonicalFileURL(for: fileURL)
        self.frontmatter = frontmatter
        self.body = body
        self.canvasData = canvasData
        self.isDirty = isDirty
        self.lastSyncedAt = lastSyncedAt
    }

    /// File name without extension, used as display name.
    public var displayName: String {
        frontmatter.title ?? fileURL.deletingPathExtension().lastPathComponent
    }
}
