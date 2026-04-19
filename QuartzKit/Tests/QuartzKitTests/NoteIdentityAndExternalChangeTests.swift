import Testing
import Foundation
@testable import QuartzKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Note identity and external changes")
struct NoteIdentityAndExternalChangeTests {

    @Test("NoteDocument canonical identity normalizes file URLs")
    func canonicalIdentityNormalizesFileURLs() {
        let rawURL = URL(fileURLWithPath: "/tmp/quartz/../quartz/test.md")
        let document = NoteDocument(
            id: UUID(),
            fileURL: rawURL,
            frontmatter: Frontmatter(title: "Identity"),
            body: "Body"
        )

        #expect(document.fileURL == rawURL.standardizedFileURL)
        #expect(document.id == CanonicalNoteIdentity(fileURL: rawURL))
    }

    @Test("Clean external change auto-reloads while preserving user context")
    @MainActor func cleanExternalChangePreservesContext() async {
        let provider = ExternalChangeVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/quartz-clean-reload.md")
        await provider.addNote(
            NoteDocument(
                fileURL: url,
                frontmatter: Frontmatter(title: "Reload"),
                body: "alpha beta gamma",
                isDirty: false
            )
        )

        let session = makeSession(provider: provider)
        await session.loadNote(at: url)
        session.selectionDidChange(NSRange(location: 6, length: 4))
        session.scrollDidChange(CGPoint(x: 0, y: 84))

        await provider.replaceBody(at: url, with: "alpha beta gamma delta")

        let presenter = NoteFilePresenter(url: url)
        session.filePresenterDidDetectChange(presenter)
        presenter.invalidate()

        await waitUntil(timeout: .seconds(2)) {
            session.currentText == "alpha beta gamma delta"
        }

        #expect(session.note?.id == CanonicalNoteIdentity(fileURL: url))
        #expect(session.currentText == "alpha beta gamma delta")
        #expect(session.cursorPosition == NSRange(location: 6, length: 4))
        #expect(session.scrollOffset.y == 84)
        #expect(session.externalModificationDetected == false)
        #expect(session.pendingExternalChangeIdentity == nil)
    }

    @Test("Dirty external change remains non-destructive and explicit")
    @MainActor func dirtyExternalChangeSetsDeterministicConflict() async {
        let provider = ExternalChangeVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/quartz-dirty-conflict.md")
        await provider.addNote(
            NoteDocument(
                fileURL: url,
                frontmatter: Frontmatter(title: "Conflict"),
                body: "Remote base",
                isDirty: false
            )
        )

        let session = makeSession(provider: provider)
        await session.loadNote(at: url)
        session.textDidChange("Local draft")

        await provider.replaceBody(at: url, with: "Remote newer")

        let presenter = NoteFilePresenter(url: url)
        session.filePresenterDidDetectChange(presenter)
        presenter.invalidate()

        #expect(session.note?.id == CanonicalNoteIdentity(fileURL: url))
        #expect(session.currentText == "Local draft")
        #expect(session.externalModificationDetected == true)
        #expect(session.pendingExternalChangeIdentity == CanonicalNoteIdentity(fileURL: url))
    }

    @Test("Relocated note rekeys canonical identity without losing context")
    @MainActor func relocationPreservesIdentityAndContext() async {
        let provider = ExternalChangeVaultProvider()
        let oldURL = URL(fileURLWithPath: "/tmp/quartz-old.md")
        let newURL = URL(fileURLWithPath: "/tmp/folder/../quartz-new.md")
        await provider.addNote(
            NoteDocument(
                fileURL: oldURL,
                frontmatter: Frontmatter(title: "Moved"),
                body: "Moved body",
                isDirty: false
            )
        )

        let session = makeSession(provider: provider)
        await session.loadNote(at: oldURL)
        session.selectionDidChange(NSRange(location: 3, length: 5))
        session.scrollDidChange(CGPoint(x: 0, y: 32))

        await provider.moveNote(from: oldURL, to: newURL)
        let presenter = NoteFilePresenter(url: oldURL)
        session.filePresenter(presenter, didMoveFrom: oldURL, to: newURL)
        presenter.invalidate()

        #expect(session.note?.id == CanonicalNoteIdentity(fileURL: newURL))
        #expect(session.note?.fileURL == CanonicalNoteIdentity.canonicalFileURL(for: newURL))
        #expect(session.cursorPosition == NSRange(location: 3, length: 5))
        #expect(session.scrollOffset.y == 32)

        await session.reloadFromDisk()

        #expect(session.note?.id == CanonicalNoteIdentity(fileURL: newURL))
        #expect(session.currentText == "Moved body")
        #expect(session.cursorPosition == NSRange(location: 3, length: 5))
    }

    @Test("Ready editor stays ready and clamps context across external reload")
    @MainActor func readyEditorRemainsReadyAcrossExternalReload() async {
        let provider = ExternalChangeVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/quartz-ready-reload.md")
        await provider.addNote(
            NoteDocument(
                fileURL: url,
                frontmatter: Frontmatter(title: "Ready"),
                body: "1234567890",
                isDirty: false
            )
        )

        let session = makeSession(provider: provider)
        await session.loadNote(at: url)
        bindNativeEditor(to: session)
        await session.awaitReadiness()
        session.restoreCursor(location: 8, length: 2)
        session.restoreScroll(y: 120)

        await provider.replaceBody(at: url, with: "12345")
        await session.reloadFromDisk()

        #expect(session.isReadyForRestoration == true)
        #expect(session.note?.id == CanonicalNoteIdentity(fileURL: url))
        #expect(session.currentText == "12345")
        #expect(session.cursorPosition == NSRange(location: 5, length: 0))
        #expect(session.scrollOffset.y == 120)
    }

    @Test("Independent sessions keep context while sharing canonical identity after reload")
    @MainActor func multiwindowSessionsPreserveIndependentContext() async {
        let provider = ExternalChangeVaultProvider()
        let url = URL(fileURLWithPath: "/tmp/quartz-multiwindow.md")
        await provider.addNote(
            NoteDocument(
                fileURL: url,
                frontmatter: Frontmatter(title: "Shared"),
                body: "Shared base",
                isDirty: false
            )
        )

        let sessionA = makeSession(provider: provider)
        let sessionB = makeSession(provider: provider)

        await sessionA.loadNote(at: url)
        await sessionB.loadNote(at: url)

        sessionA.selectionDidChange(NSRange(location: 0, length: 6))
        sessionA.scrollDidChange(CGPoint(x: 0, y: 12))
        sessionB.selectionDidChange(NSRange(location: 7, length: 4))
        sessionB.scrollDidChange(CGPoint(x: 0, y: 48))

        sessionA.textDidChange("Window A edit")
        await sessionA.save(force: true)

        let presenter = NoteFilePresenter(url: url)
        sessionB.filePresenterDidDetectChange(presenter)
        presenter.invalidate()

        await waitUntil(
            timeout: .seconds(2),
            pollInterval: .milliseconds(10)
        ) {
            sessionB.currentText == "Window A edit"
        }

        #expect(sessionA.note?.id == sessionB.note?.id)
        #expect(sessionA.note?.id == CanonicalNoteIdentity(fileURL: url))
        #expect(sessionB.currentText == "Window A edit")
        #expect(sessionB.cursorPosition == NSRange(location: 7, length: 4))
        #expect(sessionB.scrollOffset.y == 48)
    }

    // MARK: - Helpers

    @MainActor
    private func makeSession(provider: ExternalChangeVaultProvider) -> EditorSession {
        let session = EditorSession(
            vaultProvider: provider,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        session.vaultRootURL = URL(fileURLWithPath: "/tmp")
        return session
    }

    @MainActor
    private func bindNativeEditor(to session: EditorSession) {
        #if canImport(UIKit)
        let textView = MarkdownEditorUITextView(frame: .zero, textContainer: nil)
        textView.text = session.currentText
        session.bindActiveTextView(textView)
        #elseif canImport(AppKit)
        let textView = MarkdownEditorNSTextView(frame: .zero, textContainer: nil)
        textView.string = session.currentText
        session.bindActiveTextView(textView)
        #endif
    }

    @MainActor
    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }

        #expect(condition())
    }
}

private actor ExternalChangeVaultProvider: VaultProviding {
    private var notes: [URL: NoteDocument] = [:]

    func addNote(_ note: NoteDocument) {
        notes[note.fileURL] = note
    }

    func replaceBody(at url: URL, with body: String) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard var note = notes[canonicalURL] else { return }
        note.body = body
        note.isDirty = false
        notes[canonicalURL] = note
    }

    func moveNote(from oldURL: URL, to newURL: URL) {
        let canonicalOldURL = CanonicalNoteIdentity.canonicalFileURL(for: oldURL)
        let canonicalNewURL = CanonicalNoteIdentity.canonicalFileURL(for: newURL)
        guard var note = notes.removeValue(forKey: canonicalOldURL) else { return }
        note.fileURL = canonicalNewURL
        notes[canonicalNewURL] = note
    }

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        []
    }

    func readNote(at url: URL) async throws -> NoteDocument {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard let note = notes[canonicalURL] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return note
    }

    func saveNote(_ note: NoteDocument) async throws {
        notes[note.fileURL] = note
    }

    func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        let note = NoteDocument(fileURL: folder.appending(path: "\(name).md"))
        notes[note.fileURL] = note
        return note
    }

    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        let note = NoteDocument(fileURL: folder.appending(path: "\(name).md"), body: initialContent)
        notes[note.fileURL] = note
        return note
    }

    func deleteNote(at url: URL) async throws {
        notes.removeValue(forKey: CanonicalNoteIdentity.canonicalFileURL(for: url))
    }

    func rename(at url: URL, to newName: String) async throws -> URL {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let newURL = canonicalURL.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
        moveNote(from: canonicalURL, to: newURL)
        return newURL
    }

    func createFolder(named name: String, in parent: URL) async throws -> URL {
        parent.appending(path: name)
    }
}
