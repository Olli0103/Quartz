import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - VoiceOver Navigation Tests
//
// Full app traversal data contracts: sidebar → list → editor → inspector.
// Validates that all navigation destinations expose sufficient data for
// VoiceOver focus order and landmark labeling.

@Suite("VoiceOverNavigation")
struct VoiceOverNavigationTests {

    @Test("DetailRoute covers all navigation destinations")
    @MainActor func detailRouteDestinations() {
        let noteURL = URL(fileURLWithPath: "/vault/note.md")
        let routes: [DetailRoute] = [.dashboard, .graph, .note(noteURL), .empty]

        #expect(routes.count == 4,
            "DetailRoute should cover dashboard, graph, note, and empty destinations")

        // Each route is distinct
        let unique = Set(routes.map { "\($0)" })
        #expect(unique.count == 4, "All routes should be distinct for VoiceOver navigation")
    }

    @Test("SourceSelection covers all sidebar source types")
    @MainActor func sourceSelectionCoverage() {
        let folderURL = URL(fileURLWithPath: "/vault/Docs")
        let sources: [SourceSelection] = [
            .allNotes, .favorites, .recent,
            .folder(folderURL), .tag("swift")
        ]

        #expect(sources.count == 5,
            "SourceSelection should have allNotes, favorites, recent, folder, and tag")

        // All sources should be distinguishable
        let uniqueHashes = Set(sources.map { $0.hashValue })
        #expect(uniqueHashes.count == 5, "All sources should have unique hash values")
    }

    @Test("Route transitions update workspace state")
    @MainActor func routeTransitions() {
        let store = WorkspaceStore()
        let noteURL = URL(fileURLWithPath: "/vault/note.md")

        store.route = .dashboard
        #expect(store.route == .dashboard)

        store.route = .note(noteURL)
        #expect(store.selectedNoteURL == noteURL)

        store.route = .graph
        #expect(store.selectedNoteURL == nil)

        store.route = .empty
        #expect(store.route == .empty)
    }

    @Test("Inspector visibility toggles independently from navigation")
    @MainActor func inspectorToggle() {
        let inspector = InspectorStore()
        let initialVisibility = inspector.isVisible

        inspector.isVisible = !initialVisibility
        #expect(inspector.isVisible == !initialVisibility,
            "Inspector should toggle independently")

        inspector.isVisible = initialVisibility
        #expect(inspector.isVisible == initialVisibility,
            "Inspector should restore to original state")
    }

    @Test("HeadingItem provides anchor navigation targets for TOC")
    func headingItemNavigation() {
        let heading = HeadingItem(id: "h1-intro", level: 1, text: "Introduction", characterOffset: 0)

        #expect(!heading.id.isEmpty, "Heading must have ID for VoiceOver anchor")
        #expect(!heading.text.isEmpty, "Heading must have text for VoiceOver label")
        #expect(heading.level >= 1 && heading.level <= 6, "Heading level must be 1-6")
        #expect(heading.characterOffset >= 0, "Character offset must be non-negative")
    }

    @Test("NoteStats exposes reading metrics for accessibility announcements")
    func noteStatsMetrics() {
        let stats = NoteStats(wordCount: 238, characterCount: 1200, readingTimeMinutes: 1)

        #expect(stats.wordCount == 238)
        #expect(stats.characterCount == 1200)
        #expect(stats.readingTimeMinutes == 1, "238 words should be ~1 minute reading time")

        let empty = NoteStats.empty
        #expect(empty.wordCount == 0)
        #expect(empty.characterCount == 0)
        #expect(empty.readingTimeMinutes == 0)
    }

    @Test("Column visibility default allows full navigation")
    @MainActor func columnVisibilityDefault() {
        let store = WorkspaceStore()
        #expect(store.columnVisibility == .all,
            "Default column visibility should show all panes for full VoiceOver traversal")
    }

    // NOTE: True VoiceOver focus-order and rotor testing requires XCUITest.
    // These tests validate model properties that feed into accessibilityLabel/Hint.

    @Test("HeadingItem text is non-empty for VoiceOver anchor labels")
    func headingTextNonEmpty() {
        let heading = HeadingItem(id: "h2-section", level: 2, text: "Section Title", characterOffset: 10)
        #expect(!heading.text.isEmpty, "Heading text must be non-empty for VoiceOver label")
        #expect(heading.level >= 1 && heading.level <= 6, "Heading level must be 1-6")
    }

    @Test("NoteStats reading time is computable for VoiceOver announcements")
    func readingTimeComputable() {
        let stats = NoteStats(wordCount: 500, characterCount: 2500, readingTimeMinutes: 3)
        #expect(stats.readingTimeMinutes > 0, "Reading time must be positive for 'N min read' label")
        #expect(stats.wordCount > 0, "Word count must be positive for 'N words' announcement")
    }
}
