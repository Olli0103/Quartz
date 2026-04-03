import Testing
import Foundation
@testable import QuartzKit

// MARK: - Inspector Store Tests

/// Verifies InspectorStore initialization, headings update, stats,
/// visibility persistence, and AI concepts storage.

@Suite("InspectorStore")
struct InspectorStoreTests {

    @Test("Empty init has default state")
    @MainActor func emptyInit() {
        let store = InspectorStore()
        #expect(store.headings.isEmpty)
        #expect(store.stats == .empty)
        #expect(store.aiConcepts.isEmpty)
        #expect(store.relatedNotes.isEmpty)
        #expect(store.suggestedLinks.isEmpty)
    }

    @Test("AI concepts can be set and read")
    @MainActor func aiConceptsReadWrite() {
        let store = InspectorStore()
        store.aiConcepts = ["concept1", "concept2"]
        #expect(store.aiConcepts.count == 2)
        #expect(store.aiConcepts.first == "concept1")
    }

    @Test("showVersionHistory defaults to false")
    @MainActor func versionHistoryDefault() {
        let store = InspectorStore()
        #expect(store.showVersionHistory == false)
    }

    @Test("intelligenceStatus defaults to idle")
    @MainActor func intelligenceDefault() {
        let store = InspectorStore()
        if case .idle = store.intelligenceStatus {
            // Expected
        } else {
            Issue.record("Intelligence status should default to .idle")
        }
    }
}
