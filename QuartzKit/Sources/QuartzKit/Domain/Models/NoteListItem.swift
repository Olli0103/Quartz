import Foundation

/// Lightweight projection of a markdown note for the middle column list.
///
/// Contains only the data needed to render a preview row — never the full body.
/// The preview cache (`NotePreviewRepository`) stores all fields except `isFavorite`,
/// which is resolved at query time from `FavoriteNoteStorage`.
///
/// Cache invalidation uses `modifiedAt` + `fileSize` as a fingerprint:
/// if both match the cached entry, the file is unchanged and re-extraction is skipped.
public struct NoteListItem: Identifiable, Hashable, Sendable {

    /// Stable identity — the standardized file URL.
    public var id: URL { url }

    /// Absolute file URL.
    public let url: URL

    /// Display title. From frontmatter `title:` if present, else first H1 heading, else filename.
    public let title: String

    /// File modification date (from filesystem metadata).
    public let modifiedAt: Date

    /// File size in bytes (used for fingerprint — skip re-index if size+mtime unchanged).
    public let fileSize: Int64

    /// 2-3 line plain text snippet, stripped of markdown syntax and frontmatter.
    /// Empty string if the note has no body content.
    public let snippet: String

    /// Tags extracted from frontmatter. Empty array if none.
    public let tags: [String]

    /// Whether this note is in the user's favorites.
    /// Resolved at query time from `FavoriteNoteStorage`, not stored in the preview cache.
    public var isFavorite: Bool

    public init(
        url: URL,
        title: String,
        modifiedAt: Date,
        fileSize: Int64,
        snippet: String,
        tags: [String],
        isFavorite: Bool = false
    ) {
        self.url = url
        self.title = title
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.snippet = snippet
        self.tags = tags
        self.isFavorite = isFavorite
    }
}
