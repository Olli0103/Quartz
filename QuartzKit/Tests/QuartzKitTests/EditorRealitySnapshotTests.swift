import XCTest
import SwiftUI
@testable import QuartzKit
import SnapshotTesting

#if canImport(AppKit)
import AppKit

@MainActor
final class EditorRealitySnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: Self.snapshotRecordMode()) {
            super.invokeTest()
        }
    }

    private nonisolated static func snapshotRecordMode() -> SnapshotTestingConfiguration.Record {
        if ProcessInfo.processInfo.environment["QUARTZ_RECORD_EDITOR_SNAPSHOTS"] == "1" {
            return .all
        }
        if UserDefaults.standard.bool(forKey: "QUARTZ_RECORD_EDITOR_SNAPSHOTS") {
            return .all
        }
        if FileManager.default.fileExists(atPath: "/tmp/quartz_record_editor_snapshots.flag") {
            return .all
        }
        return .never
    }

    private var platformSuffix: String { "macOS" }

    func testHeadingParagraphFullSyntaxSnapshot() async throws {
        let session = try await makeLoadedSession(fixture: .headingParagraphDrift)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .full
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_HeadingParagraph_Full_\(platformSuffix)"
        )
    }

    func testExistingLongMarkdownSnapshotOnInitialOpen() async throws {
        let session = try await makeLoadedSession(fixture: .existingLongHeadingRender)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .full,
            canvasSize: CGSize(width: 900, height: 520)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_ExistingLongHeading_Open_\(platformSuffix)"
        )
    }

    func testExistingLongMarkdownSnapshotAfterReopen() async throws {
        let session = try await makeLoadedSession(fixture: .existingLongHeadingRender)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .full,
            preparation: { session in
                guard let url = session.note?.fileURL else {
                    XCTFail("Expected mounted session to keep an active note before reopen")
                    return
                }
                session.closeNote()
                await session.loadNote(at: url)
            },
            canvasSize: CGSize(width: 900, height: 520)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_ExistingLongHeading_Reopen_\(platformSuffix)"
        )
    }

    func testExistingLongMarkdownSnapshotAfterHealingEdit() async throws {
        let session = try await makeLoadedSession(fixture: .existingLongHeadingRender)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .full,
            preparation: { session in
                try await self.performHealingEdit(on: session, headingLine: "## Architecture Overview")
            },
            canvasSize: CGSize(width: 900, height: 520)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_ExistingLongHeading_PostEdit_\(platformSuffix)"
        )
    }

    func testStateRoundtripFullSyntaxSnapshot() async throws {
        let session = try await makeLoadedSession(fixture: .editorStateRoundtrip)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .full
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_StateRoundtrip_Full_\(platformSuffix)"
        )
    }

    func testConcealmentSnapshotWhenCaretIsOffMarkdownLine() async throws {
        let fixture = try EditorRealityFixture.concealmentBoundaries.load()
        let caretLocation = (fixture as NSString).range(of: "Second line plain.").location
        XCTAssertNotEqual(caretLocation, NSNotFound)

        let session = try await makeLoadedSession(fixture: .concealmentBoundaries)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: NSRange(location: caretLocation, length: 0)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_Concealment_OffLine_\(platformSuffix)"
        )
    }

    func testConcealmentSnapshotWhenCaretIsOnMarkdownLine() async throws {
        let fixture = try EditorRealityFixture.concealmentBoundaries.load()
        let caretLocation = (fixture as NSString).range(of: "bold").location
        XCTAssertNotEqual(caretLocation, NSNotFound)

        let session = try await makeLoadedSession(fixture: .concealmentBoundaries)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: NSRange(location: caretLocation, length: 0)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_Concealment_OnLine_\(platformSuffix)"
        )
    }

    func testConcealmentSnapshotWhenCaretIsInPlainTextOnMarkdownLine() async throws {
        let fixture = try EditorRealityFixture.concealmentBoundaries.load()
        let caretLocation = (fixture as NSString).range(of: "Paragraph").location
        XCTAssertNotEqual(caretLocation, NSNotFound)

        let session = try await makeLoadedSession(fixture: .concealmentBoundaries)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: NSRange(location: caretLocation, length: 0)
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_Concealment_PlainTextSameLine_\(platformSuffix)"
        )
    }

    func testSelectionOnLaterParagraphDoesNotCorruptHeadingSnapshot() async throws {
        let fixture = try EditorRealityFixture.multilineFormattingToolbar.load()
        let selection = (fixture as NSString).range(of: "How are you?")
        XCTAssertNotEqual(selection.location, NSNotFound)

        let session = try await makeLoadedSession(fixture: .multilineFormattingToolbar)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: selection
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_MultilineFormatting_Selection_\(platformSuffix)"
        )
    }

    func testBoldFormattingOnLaterParagraphKeepsHeadingStableSnapshot() async throws {
        let fixture = try EditorRealityFixture.multilineFormattingToolbar.load()
        let selection = (fixture as NSString).range(of: "How are you?")
        XCTAssertNotEqual(selection.location, NSNotFound)

        let session = try await makeLoadedSession(fixture: .multilineFormattingToolbar)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: selection,
            preparation: { session in
                session.applyFormatting(.bold)
            }
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_MultilineFormatting_Bold_\(platformSuffix)"
        )
    }

    func testLinkFormattingOnLaterParagraphKeepsHeadingStableSnapshot() async throws {
        let fixture = try EditorRealityFixture.multilineFormattingToolbar.load()
        let selection = (fixture as NSString).range(of: "How are you?")
        XCTAssertNotEqual(selection.location, NSNotFound)

        let session = try await makeLoadedSession(fixture: .multilineFormattingToolbar)
        let image = try await makeEditorSnapshotImage(
            session: session,
            syntaxVisibilityMode: .hiddenUntilCaret,
            selection: selection,
            preparation: { session in
                session.applyFormatting(.link)
            }
        )

        assertSnapshot(
            of: image,
            as: .image,
            named: "EditorReality_MultilineFormatting_Link_\(platformSuffix)"
        )
    }

    private func makeLoadedSession(
        fixture: EditorRealityFixture
    ) async throws -> EditorSession {
        let provider = MockVaultProvider()
        let text = try fixture.load()
        let url = URL(fileURLWithPath: "/tmp/\(fixture.rawValue)-snapshot.md")
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
        await session.loadNote(at: url)
        return session
    }

    private func makeEditorSnapshotImage(
        session: EditorSession,
        syntaxVisibilityMode: SyntaxVisibilityMode,
        selection: NSRange? = nil,
        preparation: (@MainActor (EditorSession) async throws -> Void)? = nil,
        colorScheme: ColorScheme = .light,
        canvasSize: CGSize = CGSize(width: 820, height: 420)
    ) async throws -> NSImage {
        let rootView = ZStack {
            Color(nsColor: .textBackgroundColor)
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: EditorTypography.defaultFontFamily,
                editorLineSpacing: EditorTypography.defaultLineSpacingMultiplier,
                editorMaxWidth: EditorTypography.defaultMaxWidth,
                syntaxVisibilityMode: syntaxVisibilityMode
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(colorScheme)

        let scale: CGFloat = 2
        let hostingView = NSHostingView(rootView: rootView)
        let container = NSView(frame: NSRect(origin: .zero, size: canvasSize))
        let window = RetinaSnapshotWindow(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.frame = container.bounds
        hostingView.wantsLayer = true
        hostingView.layer?.contentsScale = scale

        container.wantsLayer = true
        container.layer?.contentsScale = scale
        container.addSubview(hostingView)
        window.contentView = container

        try await waitForEditorReady(session: session, window: window, container: container, hostingView: hostingView)
        try await waitForStableRenderedImage(
            session: session,
            window: window,
            container: container,
            hostingView: hostingView,
            canvasSize: canvasSize,
            scale: scale
        )

        if let selection {
            session.restoreCursor(location: selection.location, length: selection.length)
            session.selectionDidChange(selection)
            try await waitForStableRenderedImage(
                session: session,
                window: window,
                container: container,
                hostingView: hostingView,
                canvasSize: canvasSize,
                scale: scale
            )
        }

        if let preparation {
            try await preparation(session)
            try await waitForEditorReady(session: session, window: window, container: container, hostingView: hostingView)
            try await waitForStableRenderedImage(
                session: session,
                window: window,
                container: container,
                hostingView: hostingView,
                canvasSize: canvasSize,
                scale: scale
            )
        }

        return renderSnapshotImage(
            session: session,
            window: window,
            container: container,
            hostingView: hostingView,
            canvasSize: canvasSize,
            scale: scale
        )
    }

    private func waitForEditorReady(
        session: EditorSession,
        window: NSWindow,
        container: NSView,
        hostingView: NSView
    ) async throws {
        for _ in 0..<80 {
            driveSnapshotLayout(session: session, window: window, container: container, hostingView: hostingView)

            if let textView = session.activeTextView,
               textView.alphaValue == 1,
               textView.string == session.currentText,
               textView.textStorage?.length == (session.currentText as NSString).length,
               session.semanticDocument.textLength == (session.currentText as NSString).length {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for editor snapshot harness to render")
    }

    private func waitForStableRenderedImage(
        session: EditorSession,
        window: NSWindow,
        container: NSView,
        hostingView: NSView,
        canvasSize: CGSize,
        scale: CGFloat
    ) async throws {
        var previousFrame: Data?
        var consecutiveStableFrames = 0

        for _ in 0..<80 {
            driveSnapshotLayout(session: session, window: window, container: container, hostingView: hostingView)

            guard let frame = renderedSnapshotBitmapData(
                container: container,
                canvasSize: canvasSize,
                scale: scale
            ) else {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }

            if frame == previousFrame {
                consecutiveStableFrames += 1
            } else {
                consecutiveStableFrames = 1
                previousFrame = frame
            }

            if consecutiveStableFrames >= 3 {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for editor snapshot harness to reach a stable render")
    }

    private func driveSnapshotLayout(
        session: EditorSession,
        window: NSWindow,
        container: NSView,
        hostingView: NSView
    ) {
        if let textView = session.activeTextView {
            if let textLayoutManager = textView.textLayoutManager {
                textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
            }
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            textView.enclosingScrollView?.layoutSubtreeIfNeeded()
            textView.enclosingScrollView?.displayIfNeeded()
        }

        window.displayIfNeeded()
        container.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
    }

    private func renderSnapshotImage(
        session: EditorSession,
        window: NSWindow,
        container: NSView,
        hostingView: NSView,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> NSImage {
        driveSnapshotLayout(session: session, window: window, container: container, hostingView: hostingView)

        let bitmapRep = makeSnapshotBitmapRep(
            container: container,
            canvasSize: canvasSize,
            scale: scale
        )

        let image = NSImage(size: canvasSize)
        image.addRepresentation(bitmapRep)
        return image
    }

    private func renderedSnapshotBitmapData(
        container: NSView,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> Data? {
        let bitmapRep = makeSnapshotBitmapRep(
            container: container,
            canvasSize: canvasSize,
            scale: scale
        )

        guard let bytes = bitmapRep.bitmapData else {
            return nil
        }

        return Data(bytes: bytes, count: bitmapRep.bytesPerRow * bitmapRep.pixelsHigh)
    }

    private func makeSnapshotBitmapRep(
        container: NSView,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> NSBitmapImageRep {
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width * scale),
            pixelsHigh: Int(canvasSize.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmapRep.size = canvasSize

        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        container.cacheDisplay(in: container.bounds, to: bitmapRep)
        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep
    }

    private func performHealingEdit(on session: EditorSession, headingLine: String) async throws {
        let text = session.currentText
        let nsText = text as NSString
        let headingRange = nsText.range(of: headingLine)
        XCTAssertNotEqual(headingRange.location, NSNotFound, "Fixture must contain heading line '\(headingLine)'")

        let insertionLocation = NSMaxRange(headingRange)
        let insertedText = nsText.replacingCharacters(in: NSRange(location: insertionLocation, length: 0), with: " ")

        session.applyExternalEdit(
            replacement: " ",
            range: NSRange(location: insertionLocation, length: 0),
            cursorAfter: NSRange(location: insertionLocation + 1, length: 0),
            origin: .formatting
        )
        try await waitForSessionText(session, expected: insertedText)

        session.applyExternalEdit(
            replacement: "",
            range: NSRange(location: insertionLocation, length: 1),
            cursorAfter: NSRange(location: insertionLocation, length: 0),
            origin: .formatting
        )
        try await waitForSessionText(session, expected: text)
    }

    private func waitForSessionText(_ session: EditorSession, expected: String) async throws {
        for _ in 0..<80 {
            if session.currentText == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for editor snapshot session text to settle")
    }
}
#endif
