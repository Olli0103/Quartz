import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Dashboard Tests
//
// Dashboard data contracts for VoiceOver labeling of streak,
// pinned notes, recent notes, and action items.

@Suite("VoiceOverDashboard")
struct VoiceOverDashboardTests {

    @Test("DashboardTaskItem has text and noteTitle for VoiceOver labels")
    func taskItemLabeling() {
        let item = DashboardTaskItem(
            id: UUID(),
            text: "Review PR #42",
            isCompleted: false,
            noteURL: URL(fileURLWithPath: "/vault/tasks.md"),
            noteTitle: "Sprint Tasks",
            lineNumber: 5,
            lineContent: "- [ ] Review PR #42"
        )

        #expect(!item.text.isEmpty, "Task text is the VoiceOver label")
        #expect(!item.noteTitle.isEmpty, "Note title provides context for which note the task belongs to")
        #expect(item.lineNumber > 0, "Line number helps identify task position")
        #expect(!item.isCompleted, "Completion status for VoiceOver announcement")
    }

    @Test("TaskItemParser extracts open tasks from markdown")
    func taskItemParsing() {
        let markdown = """
        # Tasks
        - [ ] First task
        - [x] Completed task
        - [ ] Third task
        """
        let items = TaskItemParser.parseOpenTasks(
            from: markdown,
            noteURL: URL(fileURLWithPath: "/vault/tasks.md"),
            noteTitle: "Tasks"
        )

        #expect(items.count == 2, "Should extract only open (unchecked) tasks")
        #expect(items[0].text.contains("First task"))
        #expect(items[1].text.contains("Third task"))
    }

    @Test("NoteListItem has title and snippet for preview labels")
    func noteListItemLabeling() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/vault/note.md"),
            title: "My Note",
            modifiedAt: Date(),
            fileSize: 1024,
            snippet: "A brief preview of the note content...",
            tags: ["swift", "concurrency"],
            isFavorite: true
        )

        #expect(!item.title.isEmpty, "Title is the primary VoiceOver label")
        #expect(!item.snippet.isEmpty, "Snippet provides secondary description")
        #expect(item.isFavorite, "Favorite status for VoiceOver trait announcement")
        #expect(item.tags.count == 2, "Tags provide additional context")
    }

    @Test("FileNode metadata exposes modifiedAt for recency labels")
    func fileNodeRecency() {
        let now = Date()
        let metadata = FileMetadata(
            createdAt: now.addingTimeInterval(-3600),
            modifiedAt: now,
            fileSize: 512,
            isEncrypted: false,
            cloudStatus: .local,
            hasConflict: false
        )
        let node = FileNode(
            name: "Recent.md",
            url: URL(fileURLWithPath: "/vault/Recent.md"),
            nodeType: .note,
            metadata: metadata
        )

        #expect(node.metadata.modifiedAt == now,
            "Modified date enables recency-based VoiceOver labels")
        #expect(!node.name.isEmpty, "Name is the primary VoiceOver label")
    }

    @Test("SearchResult has title and context for VoiceOver")
    func searchResultLabeling() {
        let result = SearchResult(
            noteURL: URL(fileURLWithPath: "/vault/note.md"),
            title: "SwiftUI Tips",
            score: 15,
            context: "...NavigationSplitView with sidebar...",
            matchedTags: ["swiftui"]
        )

        #expect(!result.title.isEmpty, "Title is the primary label")
        #expect(result.context != nil, "Context snippet helps describe match")
        #expect(result.score > 0, "Score indicates relevance ranking")
    }

    @Test("TaskItemParser handles empty and no-task documents")
    func taskItemParserEdgeCases() {
        let empty = TaskItemParser.parseOpenTasks(
            from: "",
            noteURL: URL(fileURLWithPath: "/vault/empty.md"),
            noteTitle: "Empty"
        )
        #expect(empty.isEmpty, "Empty document should produce no tasks")

        let noTasks = TaskItemParser.parseOpenTasks(
            from: "# Just a heading\n\nSome paragraph text.",
            noteURL: URL(fileURLWithPath: "/vault/prose.md"),
            noteTitle: "Prose"
        )
        #expect(noTasks.isEmpty, "Document without checkboxes should produce no tasks")
    }
}
