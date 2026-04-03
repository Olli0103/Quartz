#if canImport(WidgetKit)
import Testing
import Foundation
import WidgetKit
@testable import QuartzKit

// MARK: - Widget Entry Model Tests

@Suite("Widget")
struct WidgetTests {

    @Test("Widget entry types have correct placeholder values and conform to TimelineEntry")
    func widgetEntryModels() {
        // LatestNoteEntry
        let latest = LatestNoteEntry(
            date: Date(),
            noteTitle: "My Note",
            notePreview: "Preview text",
            noteURL: URL(fileURLWithPath: "/vault/note.md")
        )
        #expect(latest.noteTitle == "My Note")
        #expect(latest.notePreview == "Preview text")
        #expect(latest.noteURL != nil)

        // Placeholder
        let placeholder = LatestNoteEntry.placeholder
        #expect(!placeholder.noteTitle.isEmpty)
        #expect(placeholder.noteURL == nil)

        // QuickCaptureEntry
        let capture = QuickCaptureEntry(date: Date())
        #expect(capture.date <= Date())

        // PinnedNotesEntry
        let pinned = PinnedNotesEntry(
            date: Date(),
            notes: [
                PinnedNote(title: "Pinned", icon: "doc.text")
            ]
        )
        #expect(pinned.notes.count == 1)
        #expect(pinned.notes.first?.title == "Pinned")

        // RecentNotesEntry
        let recent = RecentNotesEntry(
            date: Date(),
            notes: [
                RecentNoteItem(id: "1", title: "Recent", relativePath: "Recent.md", modified: Date())
            ]
        )
        #expect(recent.notes.count == 1)

        // WritingStreakEntry
        let streak = WritingStreakEntry(
            date: Date(),
            streakDays: 7,
            totalNotes: 42,
            todayWordCount: 500
        )
        #expect(streak.streakDays == 7)
        #expect(streak.totalNotes == 42)
        #expect(streak.todayWordCount == 500)
    }
}
#endif
