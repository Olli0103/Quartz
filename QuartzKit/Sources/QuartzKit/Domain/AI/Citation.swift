import Foundation

/// A citation linking a `[Source N]` marker in an AI response to a specific note.
///
/// Built during the retrieval phase (before streaming begins), so citations are
/// known when the stream starts. The UI parses `[Source N]` markers in the
/// response text and maps them to this array.
public struct Citation: Identifiable, Sendable {
    /// The N in `[Source N]`, 1-based.
    public let id: Int
    /// Stable vault note ID (from `VectorEmbeddingService.stableNoteID`).
    public let noteID: UUID
    /// Display name of the cited note.
    public let noteTitle: String
    /// File URL for navigation — resolved lazily on tap via `ContentViewModel.urlForVaultNote(stableID:)`.
    public let noteURL: URL?
    /// First ~200 characters of the matched chunk.
    public let excerpt: String
    /// Cosine similarity score (0.0–1.0).
    public let similarity: Float

    public init(
        id: Int,
        noteID: UUID,
        noteTitle: String,
        noteURL: URL? = nil,
        excerpt: String,
        similarity: Float
    ) {
        self.id = id
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.noteURL = noteURL
        self.excerpt = excerpt
        self.similarity = similarity
    }
}

/// Display-layer vault chat message with structured citations.
///
/// Separate from `ChatMessage` (document chat) because vault messages
/// carry citation arrays that link `[Source N]` markers to specific notes.
public struct VaultChatMessage2: Identifiable, Sendable {
    public let id: UUID
    public let role: AIMessage.Role
    /// Raw markdown content — may contain `[Source N]` markers for AI responses.
    public var content: String
    public let timestamp: Date
    public var isComplete: Bool
    /// Citations populated after stream completes. Empty for user messages.
    public var citations: [Citation]

    public init(
        id: UUID = UUID(),
        role: AIMessage.Role,
        content: String,
        timestamp: Date = Date(),
        isComplete: Bool = true,
        citations: [Citation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isComplete = isComplete
        self.citations = citations
    }
}
