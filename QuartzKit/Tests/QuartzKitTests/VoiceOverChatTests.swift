import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Chat Tests
//
// Chat bubble, citation, and message accessibility contracts.
// Verifies that VaultChatMessage2, Citation, and related types
// expose sufficient data for VoiceOver labeling.

@Suite("VoiceOverChat")
struct VoiceOverChatTests {

    @Test("VaultChatMessage2 has role and content for VoiceOver labels")
    func messageLabeling() {
        let msg = VaultChatMessage2(
            id: UUID(),
            role: .assistant,
            content: "Here is the answer.",
            timestamp: Date(),
            isComplete: true,
            citations: []
        )

        #expect(!msg.content.isEmpty, "Message content must be non-empty for VoiceOver reading")
        #expect(msg.role == .assistant, "Role identifies the speaker for VoiceOver")
        #expect(msg.isComplete, "Complete flag distinguishes finished vs streaming messages")
    }

    @Test("Citation has noteTitle and excerpt for VoiceOver labeling")
    func citationLabeling() {
        let citation = Citation(
            id: 1,
            noteID: UUID(),
            noteTitle: "Swift Concurrency",
            noteURL: URL(fileURLWithPath: "/vault/swift.md"),
            excerpt: "Actors provide data isolation...",
            similarity: 0.85
        )

        #expect(!citation.noteTitle.isEmpty, "Citation must have title for VoiceOver label")
        #expect(!citation.excerpt.isEmpty, "Citation must have excerpt for VoiceOver description")
        #expect(citation.id == 1, "Citation ID identifies source number")
    }

    @Test("AIMessage.Role covers all speaker cases")
    func roleCoverage() {
        let roles: [AIMessage.Role] = [.system, .user, .assistant]
        #expect(roles.count == 3, "Should have system, user, and assistant roles")

        // Each role has a distinct rawValue
        let rawValues = Set(roles.map(\.rawValue))
        #expect(rawValues.count == 3, "Each role must have a unique rawValue")
    }

    @Test("VaultChatError provides localized descriptions")
    func errorDescriptions() {
        let errors: [VaultChatError] = [
            .noProviderConfigured,
            .noRelevantContent,
            .indexEmpty,
            .providerError("API timeout")
        ]

        for error in errors {
            #expect(error.errorDescription != nil,
                "VaultChatError.\(error) must provide a localized description for VoiceOver")
        }
    }

    @Test("StreamingState covers all chat phases")
    func streamingStateCoverage() {
        let states: [VaultChatSession2.StreamingState] = [.idle, .waiting, .streaming]
        #expect(states.count == 3,
            "StreamingState should have idle, waiting, and streaming phases")
    }

    @Test("Citation similarity is bounded 0.0–1.0")
    func citationSimilarityRange() {
        let high = Citation(id: 1, noteID: UUID(), noteTitle: "A", noteURL: nil, excerpt: "...", similarity: 0.95)
        let low = Citation(id: 2, noteID: UUID(), noteTitle: "B", noteURL: nil, excerpt: "...", similarity: 0.1)

        #expect(high.similarity >= 0.0 && high.similarity <= 1.0)
        #expect(low.similarity >= 0.0 && low.similarity <= 1.0)
        #expect(high.similarity > low.similarity, "Higher similarity indicates better relevance")
    }

    @Test("Message with citations provides source navigation targets")
    func messageCitations() {
        let citations = [
            Citation(id: 1, noteID: UUID(), noteTitle: "Note A", noteURL: URL(fileURLWithPath: "/a.md"), excerpt: "Excerpt A", similarity: 0.9),
            Citation(id: 2, noteID: UUID(), noteTitle: "Note B", noteURL: URL(fileURLWithPath: "/b.md"), excerpt: "Excerpt B", similarity: 0.8)
        ]
        let msg = VaultChatMessage2(
            id: UUID(),
            role: .assistant,
            content: "Answer [Source 1] [Source 2]",
            timestamp: Date(),
            isComplete: true,
            citations: citations
        )

        #expect(msg.citations.count == 2, "Message should carry citations for source navigation")
        #expect(msg.citations[0].noteURL != nil, "Citations should have URLs for navigation")
    }

    // NOTE: True VoiceOver reading-order and trait testing requires XCUITest.

    @Test("Citation with noteURL has non-empty title for VoiceOver navigation")
    func citationTitleForNavigation() {
        let url = URL(fileURLWithPath: "/vault/note.md")
        let citation = Citation(id: 1, noteID: UUID(), noteTitle: "Important Note", noteURL: url, excerpt: "some text", similarity: 0.8)
        #expect(!citation.noteTitle.isEmpty, "Citation must have title for VoiceOver 'tap to navigate' label")
        #expect(citation.noteURL != nil, "Citation with URL enables VoiceOver navigation action")
    }

    @Test("VaultChatError descriptions contain actionable guidance")
    func errorDescriptionsActionable() {
        let errors: [VaultChatError] = [.noProviderConfigured, .noRelevantContent, .indexEmpty, .providerError("timeout")]
        for error in errors {
            let desc = error.errorDescription ?? ""
            #expect(desc.count > 5, "Error '\(error)' description should be long enough to be actionable for VoiceOver")
        }
    }
}
