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

    private func makeLoadedSession(fixture: EditorRealityFixture) async throws -> EditorSession {
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

        if let selection {
            session.restoreCursor(location: selection.location, length: selection.length)
            session.selectionDidChange(selection)
            window.displayIfNeeded()
            container.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
        }

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

        let image = NSImage(size: canvasSize)
        image.addRepresentation(bitmapRep)
        return image
    }

    private func waitForEditorReady(
        session: EditorSession,
        window: NSWindow,
        container: NSView,
        hostingView: NSView
    ) async throws {
        for _ in 0..<80 {
            window.displayIfNeeded()
            container.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()

            if let textView = session.activeTextView,
               textView.alphaValue == 1,
               textView.string == session.currentText,
               textView.textStorage?.length == (session.currentText as NSString).length {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for editor snapshot harness to render")
    }
}
#endif
