import Testing
import Foundation
@testable import QuartzKit

// MARK: - Quick Note / Share Capture Tests

@Suite("QuickNoteView")
struct QuickNoteViewTests {

    @Test("ShareCaptureUseCase creates Inbox note, SharedItem markdown rendering, CaptureMode variants")
    func captureUseCaseAndModels() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-note-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let useCase = ShareCaptureUseCase()

        // Capture text to inbox
        let inboxURL = try useCase.capture(.text("Quick thought"), in: root, mode: .inbox)
        #expect(inboxURL.lastPathComponent == "Inbox.md")
        let content = try String(contentsOf: inboxURL, encoding: .utf8)
        #expect(content.contains("Quick thought"))
        #expect(content.contains("Inbox"))

        // Capture URL as new note
        let noteURL = try useCase.capture(
            .url(URL(string: "https://example.com")!, title: "Example"),
            in: root,
            mode: .newNote(title: "Bookmark")
        )
        #expect(noteURL.lastPathComponent == "Bookmark.md")
        let noteContent = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(noteContent.contains("example.com"))

        // SharedItem.markdownContent rendering
        let textItem = SharedItem.text("plain text")
        #expect(textItem.markdownContent == "plain text")

        let urlItem = SharedItem.url(URL(string: "https://apple.com")!, title: "Apple")
        #expect(urlItem.markdownContent.contains("[Apple]"))
        #expect(urlItem.markdownContent.contains("apple.com"))

        let mixedItem = SharedItem.mixed(text: "Note", url: URL(string: "https://x.com")!)
        #expect(mixedItem.markdownContent.contains("Note"))
        #expect(mixedItem.markdownContent.contains("x.com"))

        // CaptureMode variants
        switch CaptureMode.inbox {
        case .inbox: break
        default: Issue.record("Expected .inbox")
        }
        switch CaptureMode.newNote(title: "T") {
        case .newNote(let t): #expect(t == "T")
        default: Issue.record("Expected .newNote")
        }
    }
}
