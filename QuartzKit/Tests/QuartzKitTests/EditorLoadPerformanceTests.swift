import Foundation
import Testing
@testable import QuartzKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Editor load performance")
struct EditorLoadPerformanceTests {

    @MainActor
    @Test("Mounted editor stays visible while initial highlight completes in the background")
    func mountedEditorStaysVisibleDuringInitialHighlight() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-load-\(UUID().uuidString)", isDirectory: true)
        let noteURL = rootURL.appendingPathComponent("Large.md")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let body = largeFixture()
        try body.write(to: noteURL, atomically: true, encoding: .utf8)

        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: InspectorStore()
        )
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

        #expect(session.currentText == body)
        guard let metrics = session.lastLoadMetrics else {
            Issue.record("EditorSession did not record load metrics for the open path.")
            return
        }
        #expect(
            metrics.totalVisibleSeconds < 1.0,
            """
            Visible note-open path should return within 1.0s for the representative large note.
            read=\(metrics.readSeconds)s apply=\(metrics.applyStateSeconds)s total=\(metrics.totalVisibleSeconds)s
            """
        )

        #if canImport(UIKit)
        #expect(textView.alpha > 0.99)
        #elseif canImport(AppKit)
        #expect(textView.alphaValue > 0.99)
        #endif

        let rendered = await waitUntil(timeout: .seconds(8)) {
            session.semanticDocument.textLength == (body as NSString).length
        }
        #expect(rendered)
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
