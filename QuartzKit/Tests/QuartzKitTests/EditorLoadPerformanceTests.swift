import Foundation
import Testing
@testable import QuartzKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Editor load performance")
struct EditorLoadPerformance {

    @MainActor
    @Test("Mounted editor stays visible while initial highlight completes in the background")
    func mountedEditorStaysVisibleDuringInitialHighlight() async throws {
        await RendererDiagnostics.resetForTesting()
        await SubsystemDiagnostics.resetForTesting()

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-load-\(UUID().uuidString)", isDirectory: true)
        let noteURL = rootURL.appendingPathComponent("Large.md")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let body = largeFixture()
        try body.write(to: noteURL, atomically: true, encoding: .utf8)

        let parser = FrontmatterParser()
        let provider = EditorLoadMockVaultProvider(
            note: NoteDocument(
                fileURL: noteURL,
                frontmatter: Frontmatter(title: "Large"),
                body: body,
                isDirty: false,
                lastSyncedAt: Date()
            )
        )
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: InspectorStore()
        )
        defer { session.closeNote() }
        session.vaultRootURL = rootURL
        let contentManager = MarkdownTextKit2Stack.makeContentManager()
        let (_, container) = MarkdownTextKit2Stack.wireTextKit2(contentManager: contentManager)
        session.contentManager = contentManager
        session.highlighter = MarkdownASTHighlighter(baseFontSize: 14)
        session.highlighterBaseFontSize = 14

        #if canImport(UIKit)
        let textView = MarkdownEditorUITextView(frame: .zero, textContainer: container)
        session.bindActiveTextView(textView)
        #elseif canImport(AppKit)
        let textView = MarkdownEditorNSTextView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            textContainer: container
        )
        session.bindActiveTextView(textView)
        #endif

        await session.loadNote(at: noteURL)

        #expect(
            session.currentText == body,
            "EditorSession currentText should be populated synchronously by loadNote before semantic highlight finishes."
        )
        #if canImport(UIKit)
        #expect(
            textView.text == body,
            "Mounted UIKit editor should contain the note body immediately after loadNote returns."
        )
        #elseif canImport(AppKit)
        #expect(
            textView.string == body,
            "Mounted AppKit editor should contain the note body immediately after loadNote returns."
        )
        #endif
        guard let metrics = session.lastLoadMetrics else {
            Issue.record("EditorSession did not record load metrics for the open path.")
            return
        }
        #expect(
            metrics.applyStateSeconds < 0.25,
            """
            Editor base render should apply within 250ms once the note body is available.
            read=\(metrics.readSeconds)s apply=\(metrics.applyStateSeconds)s total=\(metrics.totalVisibleSeconds)s
            """
        )

        #if canImport(UIKit)
        #expect(textView.alpha > 0.99, "Mounted UIKit editor should remain visible during initial highlight.")
        #elseif canImport(AppKit)
        #expect(textView.alphaValue > 0.99, "Mounted AppKit editor should remain visible during initial highlight.")
        #endif

        let rendered = await waitUntil(timeout: .seconds(8)) {
            session.semanticDocument.textLength == (body as NSString).length
        }
        #expect(
            rendered,
            "Initial semantic highlight should complete asynchronously. semanticLength=\(session.semanticDocument.textLength) bodyLength=\((body as NSString).length)"
        )

        session.closeNote()
        await RendererDiagnostics.resetForTesting()
        await SubsystemDiagnostics.resetForTesting()
    }

    private func largeFixture() -> String {
        var text = "# Large Note\n\n"
        for index in 0..<180 {
            text += "## Section \(index)\n"
            text += "Paragraph \(index) with **bold**, *italic*, `inline code`, and [[Wiki Link \(index)]].\n\n"
            text += "- Bullet A\n- Bullet B\n- Bullet C\n\n"
            text += "| A | B | C |\n|---|---|---|\n| \(index) | data | value |\n\n"
        }
        return text
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(25),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await MainActor.run(body: condition) {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return await MainActor.run(body: condition)
    }
}

private actor EditorLoadMockVaultProvider: VaultProviding {
    private var note: NoteDocument

    init(note: NoteDocument) {
        self.note = note
    }

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        [
            FileNode(
                name: note.fileURL.lastPathComponent,
                url: note.fileURL,
                nodeType: .note,
                frontmatter: note.frontmatter
            )
        ]
    }

    func readNote(at url: URL) async throws -> NoteDocument {
        guard CanonicalNoteIdentity.canonicalFileURL(for: url) == CanonicalNoteIdentity.canonicalFileURL(for: note.fileURL) else {
            throw FileSystemError.fileNotFound(url)
        }
        return note
    }

    func saveNote(_ note: NoteDocument) async throws {
        self.note = note
    }

    func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        try await createNote(named: name, in: folder, initialContent: "")
    }

    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        let url = folder.appending(path: "\(name).md")
        let created = NoteDocument(
            fileURL: url,
            frontmatter: Frontmatter(title: name),
            body: initialContent,
            isDirty: false,
            lastSyncedAt: Date()
        )
        note = created
        return created
    }

    func deleteNote(at url: URL) async throws {}

    func rename(at url: URL, to newName: String) async throws -> URL {
        let renamedURL = url.deletingLastPathComponent().appending(path: newName)
        note.fileURL = renamedURL
        return renamedURL
    }

    func createFolder(named name: String, in parent: URL) async throws -> URL {
        parent.appending(path: name, directoryHint: .isDirectory)
    }
}
