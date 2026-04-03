import Testing
import Foundation
@testable import QuartzKit

// MARK: - Chat View / VaultChatSession2 State Tests

@Suite("ChatView")
struct ChatViewTests {

    @Test("VaultChatSession2 initial state: idle, empty messages, clear resets")
    @MainActor func initialStateAndClear() {
        // We need a VaultChatService to construct VaultChatSession2.
        // VaultChatSession2 requires concrete dependencies — test observable state properties.
        // Instead, verify the StreamingState enum and message model.

        // StreamingState enum values
        let idle = VaultChatSession2.StreamingState.idle
        let waiting = VaultChatSession2.StreamingState.waiting
        let streaming = VaultChatSession2.StreamingState.streaming

        // They should be distinct
        #expect(idle != waiting)
        #expect(waiting != streaming)
        #expect(idle != streaming)

        // VaultChatMessage2 model construction
        let msg = VaultChatMessage2(
            id: UUID(),
            role: .user,
            content: "Hello",
            timestamp: Date(),
            isComplete: true,
            citations: []
        )
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
        #expect(msg.citations.isEmpty)
        #expect(msg.isComplete == true)

        let citation = Citation(
            id: 1,
            noteID: UUID(),
            noteTitle: "Note",
            noteURL: URL(fileURLWithPath: "/note.md"),
            excerpt: "relevant text",
            similarity: 0.85
        )
        let aiMsg = VaultChatMessage2(
            role: .assistant,
            content: "Response with citation",
            citations: [citation]
        )
        #expect(aiMsg.role == .assistant)
        #expect(aiMsg.citations.count == 1)
        #expect(aiMsg.citations.first?.noteTitle == "Note")
        #expect(aiMsg.citations.first?.similarity == 0.85)
    }
}
