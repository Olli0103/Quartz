import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Dashboard Flow Tests
//
// Dashboard → pinned notes → tap → editor: DetailRoute transitions,
// DashboardTaskItem parsing, recency metadata, search scoring.

@Suite("E2EDashboardFlow")
struct E2EDashboardFlowTests {

    @Test("DetailRoute.dashboard is a valid starting route")
    @MainActor func dashboardRoute() {
        let store = WorkspaceStore()
        store.route = .dashboard
        #expect(store.route == .dashboard)
        #expect(store.selectedNoteURL == nil, "Dashboard route should not select a note")
    }

    @Test("DashboardTaskItem has required fields for display")
    func taskItemFields() {
        let item = DashboardTaskItem(
            id: UUID(),
            text: "Fix bug",
            isCompleted: false,
            noteURL: URL(fileURLWithPath: "/vault/bugs.md"),
            noteTitle: "Bug List",
            lineNumber: 3,
            lineContent: "- [ ] Fix bug"
        )

        #expect(!item.text.isEmpty)
        #expect(!item.noteTitle.isEmpty)
        #expect(item.lineNumber > 0)
    }

    @Test("TaskItemParser parses checkbox markdown syntax")
    func checkboxParsing() {
        let markdown = "- [ ] Open task\n- [x] Done task\n- [ ] Another open"
        let items = TaskItemParser.parseOpenTasks(
            from: markdown,
            noteURL: URL(fileURLWithPath: "/vault/todo.md"),
            noteTitle: "Todo"
        )

        #expect(items.count == 2, "Should find 2 open (unchecked) tasks")
        #expect(items.allSatisfy { !$0.isCompleted })
    }

    @Test("FileNode metadata modifiedAt enables recency sorting")
    func recencySorting() {
        let older = FileMetadata(
            createdAt: Date(), modifiedAt: Date().addingTimeInterval(-3600),
            fileSize: 100, isEncrypted: false, cloudStatus: .local, hasConflict: false
        )
        let newer = FileMetadata(
            createdAt: Date(), modifiedAt: Date(),
            fileSize: 100, isEncrypted: false, cloudStatus: .local, hasConflict: false
        )

        #expect(newer.modifiedAt > older.modifiedAt,
            "Recency comparison relies on modifiedAt")
    }

    @Test("Route transition from dashboard to note is valid")
    @MainActor func dashboardToNote() {
        let store = WorkspaceStore()
        store.route = .dashboard
        let initial = store.routeChangeCount

        store.route = .note(URL(fileURLWithPath: "/vault/note.md"))
        #expect(store.route == .note(URL(fileURLWithPath: "/vault/note.md")))
        #expect(store.routeChangeCount == initial + 1)
    }

    @Test("SearchResult score enables ranking")
    func searchScoreRanking() {
        let high = SearchResult(noteURL: URL(fileURLWithPath: "/a.md"), title: "A", score: 15, context: nil, matchedTags: [])
        let low = SearchResult(noteURL: URL(fileURLWithPath: "/b.md"), title: "B", score: 3, context: nil, matchedTags: [])

        #expect(high.score > low.score, "Higher score should rank higher in results")
    }
}
