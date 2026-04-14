import XCTest
@testable import QuartzKit

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorRealityRoundtripTests: XCTestCase {

    func testCorpusFixturesPreserveAttributedContentAcrossCloseAndReopen() async throws {
        for fixture in EditorRealityFixture.allCases {
            let provider = MockVaultProvider()
            let text = try fixture.load()
            let anchor = fixture.verificationAnchor
            let anchorLocation = (text as NSString).range(of: anchor).location
            XCTAssertNotEqual(anchorLocation, NSNotFound, "Fixture \(fixture.rawValue) must contain anchor '\(anchor)'")

            let url = URL(fileURLWithPath: "/tmp/\(fixture.rawValue).md")
            let note = NoteDocument(
                fileURL: url,
                frontmatter: Frontmatter(title: fixture.rawValue),
                body: text,
                isDirty: false
            )
            await provider.addNote(note)

            let session = EditorSession(
                vaultProvider: provider,
                frontmatterParser: FrontmatterParser(),
                inspectorStore: InspectorStore()
            )
            let textView = makeTextView()
            session.activeTextView = textView
            session.highlighter = MarkdownASTHighlighter(baseFontSize: 14)

            await session.loadNote(at: url)
            try await waitForHighlightPass(on: textView, monitoredLocation: anchorLocation)

            let initialFont = try XCTUnwrap(
                textView.textStorage?.attribute(.font, at: anchorLocation, effectiveRange: nil) as? NSFont,
                "Fixture \(fixture.rawValue) should render an initial font at anchor"
            )
            let initialColor = try XCTUnwrap(
                textView.textStorage?.attribute(.foregroundColor, at: anchorLocation, effectiveRange: nil) as? NSColor,
                "Fixture \(fixture.rawValue) should render an initial color at anchor"
            )

            session.closeNote()
            await session.loadNote(at: url)
            try await waitForHighlightPass(on: textView, monitoredLocation: anchorLocation)

            XCTAssertEqual(session.currentText, text, "Fixture \(fixture.rawValue) should preserve raw markdown text across reopen")

            let reopenedFont = try XCTUnwrap(
                textView.textStorage?.attribute(.font, at: anchorLocation, effectiveRange: nil) as? NSFont,
                "Fixture \(fixture.rawValue) should render a reopened font at anchor"
            )
            let reopenedColor = try XCTUnwrap(
                textView.textStorage?.attribute(.foregroundColor, at: anchorLocation, effectiveRange: nil) as? NSColor,
                "Fixture \(fixture.rawValue) should render a reopened color at anchor"
            )

            XCTAssertEqual(reopenedFont.fontName, initialFont.fontName)
            XCTAssertEqual(reopenedFont.pointSize, initialFont.pointSize, accuracy: 0.01)
            XCTAssertEqual(reopenedColor, initialColor)
        }
    }

    private func makeTextView() -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.allowsUndo = false
        return textView
    }

    private func waitForHighlightPass(on textView: NSTextView, monitoredLocation: Int) async throws {
        for _ in 0..<50 {
            if textView.alphaValue == 1,
               let textStorage = textView.textStorage,
               monitoredLocation < textStorage.length,
               textStorage.attribute(.font, at: monitoredLocation, effectiveRange: nil) != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for highlight pass to complete")
    }
}
#endif
