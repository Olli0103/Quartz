import Testing
import Foundation
import SwiftUI
@testable import QuartzKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Scene Storage / Editor State Restoration Tests

@Suite("SceneStorage")
struct SceneStorageTests {

    @MainActor private func makeSession() -> EditorSession {
        let provider = MockVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }

    @Test("restoreCursor clamps out-of-range values, restoreScroll updates offset")
    @MainActor func cursorAndScrollRestoration() {
        let session = makeSession()
        // Empty session — currentText.count == 0

        // Cursor beyond text length — should clamp to 0
        session.restoreCursor(location: 999, length: 10)
        #expect(session.cursorPosition.location == 0)
        #expect(session.cursorPosition.length == 0)

        // Zero cursor works
        session.restoreCursor(location: 0)
        #expect(session.cursorPosition.location == 0)
        #expect(session.cursorPosition.length == 0)

        // Restore scroll offset
        session.restoreScroll(y: 42.5)
        #expect(session.scrollOffset.y == 42.5)

        // Scroll with zero
        session.restoreScroll(y: 0)
        #expect(session.scrollOffset.y == 0)
    }

    @Test("awaitReadiness resolves immediately when already ready, signalReadyForRestoration is idempotent")
    @MainActor func readinessHandshake() async {
        let session = makeSession()

        // Signal ready
        session.signalReadyForRestoration()
        #expect(session.isReadyForRestoration == true)

        // awaitReadiness returns immediately when already ready
        await session.awaitReadiness()
        #expect(session.isReadyForRestoration == true)

        // Signaling again is idempotent (no crash)
        session.signalReadyForRestoration()
        #expect(session.isReadyForRestoration == true)
    }

    @Test("loadNote readiness waits for a mounted native editor")
    @MainActor func loadNoteReadinessRequiresMountedEditor() async throws {
        let provider = MockVaultProvider()
        let noteURL = URL(fileURLWithPath: "/tmp/scene-storage-readiness-\(UUID().uuidString).md")
        await provider.addNote(NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Readiness"),
            body: "Hello world",
            isDirty: false
        ))

        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        await session.loadNote(at: noteURL)

        #expect(session.isReadyForRestoration == false)

        #if canImport(UIKit)
        let textView = MarkdownEditorUITextView(frame: .zero, textContainer: nil)
        textView.text = session.currentText
        session.bindActiveTextView(textView)
        #elseif canImport(AppKit)
        let textView = MarkdownEditorNSTextView(frame: .zero, textContainer: nil)
        textView.string = session.currentText
        session.bindActiveTextView(textView)
        #endif

        await session.awaitReadiness()
        #expect(session.isReadyForRestoration == true)
    }

    @Test("restoreCursor defers to the mounted editor when restoration happens before mount")
    @MainActor func deferredCursorRestorationAppliesOnMount() async {
        let session = makeSession()
        session.textDidChange("Hello world")
        session.restoreCursor(location: 6, length: 5)

        #if canImport(UIKit)
        let textView = MarkdownEditorUITextView(frame: .zero, textContainer: nil)
        textView.text = session.currentText
        session.bindActiveTextView(textView)
        #expect(textView.selectedRange == NSRange(location: 6, length: 5))
        #elseif canImport(AppKit)
        let canvasSize = CGSize(width: 320, height: 120)
        let rootView = AnyView(
            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: 1.0,
                editorFontFamily: EditorTypography.defaultFontFamily,
                editorLineSpacing: EditorTypography.defaultLineSpacingMultiplier,
                editorMaxWidth: EditorTypography.defaultMaxWidth,
                syntaxVisibilityMode: .full
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: canvasSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: NSRect(origin: .zero, size: canvasSize))
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        window.contentView = container
        for _ in 0..<80 {
            window.displayIfNeeded()
            container.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            if let textView = session.activeTextView {
                #expect(textView.selectedRange() == NSRange(location: 6, length: 5))
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #endif

        #expect(session.cursorPosition == NSRange(location: 6, length: 5))
    }
}
