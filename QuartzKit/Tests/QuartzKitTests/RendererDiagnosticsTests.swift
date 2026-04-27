import Foundation
import Testing
@testable import QuartzKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Renderer diagnostics")
struct RendererDiagnosticsTests {
    @Test("Renderer diagnostics records events when enabled")
    func recordsEventsWhenEnabled() async {
        let store = RendererDiagnosticsStore(capacity: 10)

        await store.record(RendererDiagnosticEvent(
            name: "textDidChange",
            noteBasename: "Note.md",
            metadata: ["newTextLength": "42"]
        ))

        let snapshot = await store.snapshot(enabled: true)
        #expect(snapshot.enabled)
        #expect(snapshot.lastEvents.contains { $0.name == "textDidChange" })
    }

    @Test("Renderer diagnostics does not record when disabled")
    func doesNotRecordWhenDisabled() async {
        let store = RendererDiagnosticsStore(capacity: 10)

        let snapshot = await store.snapshot(enabled: false)
        #expect(!snapshot.enabled)
        #expect(snapshot.lastEvents.isEmpty)
    }

    @Test("Renderer diagnostics ring buffer stays bounded")
    func ringBufferStaysBounded() async {
        let store = RendererDiagnosticsStore(capacity: 3)

        for index in 0..<8 {
            await store.record(RendererDiagnosticEvent(name: "event.\(index)"))
        }

        let snapshot = await store.snapshot(enabled: true)
        #expect(snapshot.lastEvents.count == 3)
        #expect(snapshot.lastEvents.first?.name == "event.5")
        #expect(snapshot.lastEvents.last?.name == "event.7")
    }

    @Test("Corruption detector fires for invalid span and unsafe typing attributes")
    func corruptionDetectorFiresForInvalidSpanAndUnsafeTypingAttributes() async throws {
        let font = testFont()
        let invalidSpan = HighlightSpan(
            range: NSRange(location: 100, length: 12),
            font: font,
            color: nil,
            traits: FontTraits(bold: false, italic: false),
            backgroundColor: nil,
            strikethrough: false,
            tableRowStyle: .bodyEven
        )
        let markdown = "# Heading\n\nBody"
        let semantic = EditorSemanticDocument.build(markdown: markdown, spans: [invalidSpan])

        let signals = RendererDiagnostics.detectCorruptionSignals(
            spans: [invalidSpan],
            semanticDocument: semantic,
            markdown: markdown,
            noteBasename: "Note.md",
            editedRange: NSRange(location: 1, length: 0),
            textRevision: 2,
            renderGeneration: 1
        )
        #expect(signals.contains { $0.name == "corruption.spanOutOfBounds" })

        let unsafeKeys = RendererDiagnostics.unsafeTypingAttributeKeys(in: [
            .kern: 4,
            .quartzTableRowStyle: QuartzTableRowStyle.header.rawValue,
            .link: URL(string: "https://example.com") as Any
        ])
        #expect(unsafeKeys.contains(NSAttributedString.Key.kern.rawValue))
        #expect(unsafeKeys.contains(NSAttributedString.Key.quartzTableRowStyle.rawValue))
        #expect(unsafeKeys.contains(NSAttributedString.Key.link.rawValue))
    }

    @Test("Renderer diagnostics redacts full note content metadata")
    func redactsFullNoteContentMetadata() async {
        let secret = "Do not leak this complete note body"
        let event = RendererDiagnosticEvent(
            name: "textDidChange",
            metadata: [
                "fullText": secret,
                "newTextLength": "34"
            ]
        )

        #expect(event.metadata["fullText"] == "<redacted>")
        #expect(event.metadata["newTextLength"] == "34")
        #expect(!String(describing: event).contains(secret))
    }

    @Test("Span checksum mismatch for identical text emits warning")
    func spanChecksumMismatchForIdenticalTextEmitsWarning() async {
        let store = RendererDiagnosticsStore(capacity: 10)

        await store.record(RendererDiagnosticEvent(
            name: "save.renderSnapshot",
            noteBasename: "Note.md",
            metadata: ["textChecksum": "abc", "spanChecksum": "one"]
        ))
        await store.record(RendererDiagnosticEvent(
            name: "reopen.renderSnapshot",
            noteBasename: "Note.md",
            metadata: ["textChecksum": "abc", "spanChecksum": "two"]
        ))

        let snapshot = await store.snapshot(enabled: true)
        #expect(snapshot.corruptionSignals.contains { $0.name == "corruption.loadReopenSpanChecksumMismatch" })
    }
}

private func testFont() -> PlatformFont {
    #if canImport(UIKit)
    UIFont.systemFont(ofSize: 14)
    #elseif canImport(AppKit)
    NSFont.systemFont(ofSize: 14)
    #endif
}
