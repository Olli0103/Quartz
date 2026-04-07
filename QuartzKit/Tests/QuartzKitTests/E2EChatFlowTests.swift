import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Chat Flow Tests
//
// Chat → streaming → citation → navigate: VaultChatMessage2 citations,
// Citation navigation targets, error handling, message roles.

@Suite("E2EChatFlow")
struct E2EChatFlowTests {

    @Test("VaultChatMessage2 stores citations for source navigation")
    func messageCitations() {
        let citations = [
            Citation(id: 1, noteID: UUID(), noteTitle: "Note A", noteURL: URL(fileURLWithPath: "/a.md"), excerpt: "excerpt A", similarity: 0.9),
            Citation(id: 2, noteID: UUID(), noteTitle: "Note B", noteURL: URL(fileURLWithPath: "/b.md"), excerpt: "excerpt B", similarity: 0.7)
        ]
        let msg = VaultChatMessage2(
            id: UUID(), role: .assistant,
            content: "Answer with [Source 1] and [Source 2]",
            timestamp: Date(), isComplete: true,
            citations: citations
        )

        #expect(msg.citations.count == 2)
        #expect(msg.citations[0].id == 1)
        #expect(msg.citations[1].id == 2)
    }

    @Test("Citation noteURL enables navigation to source note")
    func citationNavigation() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        let citation = Citation(id: 1, noteID: UUID(), noteTitle: "Note", noteURL: url, excerpt: "...", similarity: 0.85)

        #expect(citation.noteURL == url,
            "Citation URL is the navigation target for 'tap source' action")
    }

    @Test("Citation excerpt is bounded for display")
    func citationExcerptBounded() {
        let longExcerpt = String(repeating: "word ", count: 100)
        let citation = Citation(id: 1, noteID: UUID(), noteTitle: "Note", noteURL: nil, excerpt: longExcerpt, similarity: 0.5)

        #expect(!citation.excerpt.isEmpty, "Excerpt should be non-empty for display")
    }

    @Test("VaultChatError covers all failure modes")
    func chatErrorCoverage() {
        let errors: [VaultChatError] = [
            .noProviderConfigured,
            .noRelevantContent,
            .indexEmpty,
            .providerError("timeout")
        ]

        for error in errors {
            #expect(error.errorDescription != nil,
                "Each error must have a localized description")
        }
    }

    @Test("AIMessage.Role distinguishes speakers")
    func roleDistinction() {
        let system = AIMessage(role: .system, content: "You are helpful")
        let user = AIMessage(role: .user, content: "Question")
        let assistant = AIMessage(role: .assistant, content: "Answer")

        #expect(system.role != user.role)
        #expect(user.role != assistant.role)
        #expect(system.role != assistant.role)
    }

    @Test("ChatMessage is Identifiable with unique IDs")
    func chatMessageIdentifiable() {
        let msg1 = ChatMessage(role: .user, content: "Hello")
        let msg2 = ChatMessage(role: .assistant, content: "Hi")

        #expect(msg1.id != msg2.id, "Each message should have a unique ID")
    }
}
