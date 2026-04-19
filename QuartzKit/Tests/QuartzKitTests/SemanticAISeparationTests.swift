import Foundation
import Testing
@testable import QuartzKit

@Suite("Semantic similarity and AI concepts separation")
struct SemanticAISeparationTests {

    @Test("Legacy combined setting migrates into separate related-notes and AI-concepts controls")
    func legacySettingsMigrationSplitsCleanly() {
        let suiteName = "SemanticAISeparationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: KnowledgeAnalysisSettings.legacyCombinedAnalysisEnabledKey)

        KnowledgeAnalysisSettings.migrateLegacyDefaultsIfNeeded(defaults: defaults)

        #expect(KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled(defaults: defaults) == false)
        #expect(KnowledgeAnalysisSettings.aiConceptExtractionEnabled(defaults: defaults) == false)

        KnowledgeAnalysisSettings.setRelatedNotesSimilarityEnabled(true, defaults: defaults)
        #expect(KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled(defaults: defaults) == true)
        #expect(KnowledgeAnalysisSettings.aiConceptExtractionEnabled(defaults: defaults) == false)
    }

    @Test("Semantic related-note updates do not mutate AI concept state")
    func semanticUpdatesStayOutOfConceptState() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        await store.updateConcepts(for: noteA, concepts: ["swift", "ios"])
        await store.updateSemanticConnections(for: noteA, related: [noteB])

        let concepts = await store.concepts(for: noteA)
        let related = await store.semanticRelations(for: noteA)

        #expect(concepts == ["swift", "ios"])
        #expect(related == [noteB])
    }

    @Test("AI concept updates do not mutate related-note similarity state")
    func conceptUpdatesStayOutOfSimilarityState() async {
        let store = GraphEdgeStore()
        let noteA = URL(fileURLWithPath: "/vault/a.md")
        let noteB = URL(fileURLWithPath: "/vault/b.md")

        await store.updateSemanticConnections(for: noteA, related: [noteB])
        await store.updateConcepts(for: noteA, concepts: ["swiftui"])

        let related = await store.semanticRelations(for: noteA)
        let concepts = await store.concepts(for: noteA)

        #expect(related == [noteB])
        #expect(concepts == ["swiftui"])
    }

    @Test("Related-note and AI-concept notifications remain distinct")
    func updateNotificationsStayDistinct() {
        #expect(Notification.Name.quartzRelatedNotesUpdated != .quartzConceptsUpdated)
        #expect(Notification.Name.quartzRelatedNotesUpdated != .quartzConceptScanProgress)
    }
}
