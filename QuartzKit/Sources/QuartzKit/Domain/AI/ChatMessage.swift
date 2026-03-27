import Foundation

/// Display-layer chat message model with mutable content for streaming updates.
///
/// Separate from `AIMessage` (the wire-format model) because:
/// - `content` must be `var` so the streaming loop can append tokens
/// - `isComplete` tracks whether the AI has finished generating
/// - `role` is restricted to `.user` / `.assistant` (no `.system` in the UI)
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: AIMessage.Role
    public var content: String
    public let timestamp: Date
    public var isComplete: Bool

    public init(
        id: UUID = UUID(),
        role: AIMessage.Role,
        content: String,
        timestamp: Date = Date(),
        isComplete: Bool = true
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isComplete = isComplete
    }
}
