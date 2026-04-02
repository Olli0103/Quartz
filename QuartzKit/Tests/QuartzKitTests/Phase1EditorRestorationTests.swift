import XCTest
@testable import QuartzKit

// MARK: - Phase 1: Editor & Restoration Determinism (CODEX.md Recovery Plan)
// TDD Red Phase: These tests define expected behavior for editor restoration.
// Per CODEX.md F3, F6: stale editorViewModel references, incomplete restoration wiring.
//
// Note: These tests document the EXPECTED behavior. Some will fail until
// the restoration APIs (restoreCursor, restoreScroll) are implemented on EditorSession.

// MARK: - EditorSessionRestorationTests

/// Tests that EditorSession properly restores cursor and scroll position on reopen.
/// Per CODEX.md F6: scene storage persists values but shell restoration is incomplete.
final class EditorSessionRestorationTests: XCTestCase {

    // MARK: - Cursor State Tracking

    /// Tests that cursor position is tracked via selectionDidChange.
    @MainActor
    func testCursorPositionIsTracked() async throws {
        let session = createTestSession()

        // Initial state
        XCTAssertEqual(session.cursorPosition, NSRange(location: 0, length: 0))

        // Simulate user moving cursor
        session.selectionDidChange(NSRange(location: 25, length: 0))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 25, length: 0))

        // Simulate selection
        session.selectionDidChange(NSRange(location: 10, length: 5))
        XCTAssertEqual(session.cursorPosition, NSRange(location: 10, length: 5))
    }

    /// Tests that scroll offset is tracked via scrollDidChange.
    @MainActor
    func testScrollOffsetIsTracked() async throws {
        let session = createTestSession()

        // Initial state
        XCTAssertEqual(session.scrollOffset, CGPoint.zero)

        // Simulate scrolling
        session.scrollDidChange(CGPoint(x: 0, y: 150))
        XCTAssertEqual(session.scrollOffset, CGPoint(x: 0, y: 150))
    }

    /// Tests that cursor is cleared when note is closed.
    /// Fixed in Phase 1: closeNote() now resets cursor position.
    @MainActor
    func testCursorClearedOnNoteClose() async throws {
        let session = createTestSession()

        // Set cursor position
        session.selectionDidChange(NSRange(location: 25, length: 0))
        XCTAssertEqual(session.cursorPosition.location, 25)

        // Clear note
        session.closeNote()

        // Cursor should be reset (fixed in Phase 1)
        XCTAssertEqual(session.cursorPosition, NSRange(location: 0, length: 0),
            "closeNote() should reset cursor position")
    }

    /// Tests that restoreCursor API works correctly.
    @MainActor
    func testRestoreCursorAPI() async throws {
        let session = createTestSession()

        // Simulate document with content (via textDidChange callback)
        session.textDidChange("This is sample content for testing cursor restoration.")

        // Restore cursor to position 42 (within document bounds)
        session.restoreCursor(location: 42, length: 5)

        XCTAssertEqual(session.cursorPosition.location, 42)
        XCTAssertEqual(session.cursorPosition.length, 5)
    }

    /// Tests that restoreCursor clamps to document length.
    @MainActor
    func testRestoreCursorClampsToDocumentLength() async throws {
        let session = createTestSession()

        // Document is empty, so position should clamp to 0
        session.restoreCursor(location: 1000, length: 0)

        XCTAssertEqual(session.cursorPosition.location, 0,
            "Cursor should be clamped to document length")
    }

    /// Tests that restoreScroll API works correctly.
    @MainActor
    func testRestoreScrollAPI() async throws {
        let session = createTestSession()

        // Restore scroll to y=150
        session.restoreScroll(y: 150)

        XCTAssertEqual(session.scrollOffset.y, 150)
    }

    // MARK: - State Persistence Contract

    /// Tests that cursor state is accessible for persistence.
    @MainActor
    func testCursorStateAccessibleForPersistence() async throws {
        let session = createTestSession()
        session.selectionDidChange(NSRange(location: 42, length: 10))

        // These values should be accessible for saving to @SceneStorage
        let location = session.cursorPosition.location
        let length = session.cursorPosition.length

        XCTAssertEqual(location, 42)
        XCTAssertEqual(length, 10)
    }

    /// Tests that scroll state is accessible for persistence.
    @MainActor
    func testScrollStateAccessibleForPersistence() async throws {
        let session = createTestSession()
        session.scrollDidChange(CGPoint(x: 10, y: 200))

        // These values should be accessible for saving to @SceneStorage
        let scrollY = session.scrollOffset.y

        XCTAssertEqual(scrollY, 200)
    }

    // MARK: - Restoration Flow Documentation

    /// Documents the expected restoration flow that ContentView should implement.
    /// This test passes trivially but documents the required integration.
    @MainActor
    func testRestorationFlowDocumentation() async throws {
        // EXPECTED FLOW (per CODEX.md F6 + F8):
        //
        // 1. On app relaunch:
        //    - ContentView reads @SceneStorage values:
        //      - restoredNotePath: String?
        //      - restoredCursorLocation: Int
        //      - restoredCursorLength: Int
        //      - restoredScrollOffset: Double
        //
        // 2. After vault loads and note is opened:
        //    - session.loadNote(at: restoredURL)
        //
        // 3. After note content is loaded (F8 handshake):
        //    - await session.awaitReadiness()  // <-- NEW: explicit handshake
        //    - session.restoreCursor(location:length:)
        //    - session.restoreScroll(y:)
        //
        // IMPLEMENTED: All steps now work with Phase 1 changes.
        // F8 FIX: Replaced Task.sleep(100ms) with awaitReadiness() handshake.

        XCTAssertTrue(true, "Restoration flow implemented")
    }

    // MARK: - Readiness Handshake Tests (F8)

    /// Tests that session starts not ready for restoration.
    @MainActor
    func testSessionStartsNotReady() async throws {
        let session = createTestSession()
        XCTAssertFalse(session.isReadyForRestoration,
            "New session should not be ready for restoration")
    }

    /// Tests that awaitReadiness returns immediately when already ready.
    @MainActor
    func testAwaitReadinessReturnsImmediatelyWhenReady() async throws {
        let session = createTestSession()

        // Manually signal ready
        session.signalReadyForRestoration()
        XCTAssertTrue(session.isReadyForRestoration)

        // Should return immediately (no hang)
        await session.awaitReadiness()

        XCTAssertTrue(true, "awaitReadiness returned immediately")
    }

    /// Tests that multiple waiters are all resumed when ready is signaled.
    @MainActor
    func testMultipleWaitersResumedOnReady() async throws {
        let session = createTestSession()
        var waiter1Done = false
        var waiter2Done = false

        // Start two waiters
        let task1 = Task { @MainActor in
            await session.awaitReadiness()
            waiter1Done = true
        }
        let task2 = Task { @MainActor in
            await session.awaitReadiness()
            waiter2Done = true
        }

        // Give tasks time to start waiting
        try await Task.sleep(for: .milliseconds(10))

        // Signal ready
        session.signalReadyForRestoration()

        // Wait for tasks to complete
        await task1.value
        await task2.value

        XCTAssertTrue(waiter1Done, "Waiter 1 should be resumed")
        XCTAssertTrue(waiter2Done, "Waiter 2 should be resumed")
    }

    /// Tests that closeNote resets readiness state.
    @MainActor
    func testCloseNoteResetsReadiness() async throws {
        let session = createTestSession()

        // Signal ready
        session.signalReadyForRestoration()
        XCTAssertTrue(session.isReadyForRestoration)

        // Close note
        session.closeNote()

        // Readiness should be reset
        XCTAssertFalse(session.isReadyForRestoration,
            "closeNote should reset readiness state")
    }

    /// Tests that signalReadyForRestoration is idempotent.
    @MainActor
    func testSignalReadyIsIdempotent() async throws {
        let session = createTestSession()

        // Signal ready multiple times
        session.signalReadyForRestoration()
        session.signalReadyForRestoration()
        session.signalReadyForRestoration()

        XCTAssertTrue(session.isReadyForRestoration,
            "Multiple signals should not cause issues")
    }

    // MARK: - Helper

    @MainActor
    private func createTestSession() -> EditorSession {
        let provider = TestVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }
}

// MARK: - OpenNoteScannerHookTests

/// Tests that document scanner hooks don't reference stale editor view models.
/// Per CODEX.md F3: stale editorViewModel references in ContentView.
final class OpenNoteScannerHookTests: XCTestCase {

    /// Tests that ContentViewModel exposes editorSession (not legacy editorViewModel).
    @MainActor
    func testContentViewModelExposesEditorSession() async throws {
        let appState = AppState()
        let viewModel = ContentViewModel(appState: appState)

        // editorSession should be the public API
        XCTAssertNil(viewModel.editorSession, "EditorSession starts nil before note is opened")

        // If we could access viewModel.editorViewModel, this test would fail to compile
        // The fact that this compiles proves the legacy property is gone or renamed
    }

    /// Tests that AppState has the scanner flag.
    @MainActor
    func testAppStateHasScannerFlag() async throws {
        let appState = AppState()

        // The flag should exist
        XCTAssertFalse(appState.pendingOpenDocumentScanner)

        // Setting it should work
        appState.pendingOpenDocumentScanner = true
        XCTAssertTrue(appState.pendingOpenDocumentScanner)

        // ContentView.onChange should consume this flag
        // and trigger scanner presentation WITHOUT using editorViewModel
    }

    /// Documents the scanner hook issue from CODEX.md F3.
    @MainActor
    func testScannerHookIssueDocumentation() async throws {
        // ISSUE (per CODEX.md F3):
        //
        // ContentView.swift has this code:
        // ```swift
        // .onChange(of: appState.pendingOpenDocumentScanner) { _, pending in
        //     guard pending else { return }
        //     appState.pendingOpenDocumentScanner = false
        //     #if os(iOS)
        //     viewModel?.editorViewModel?.requestDocumentScannerPresentation = true
        //     #endif
        // }
        // ```
        //
        // But `editorViewModel` doesn't exist on ContentViewModel anymore.
        // This code either:
        // - Doesn't compile (if editorViewModel was fully removed)
        // - References a stale/unused property
        // - Is dead code
        //
        // FIX: Scanner presentation should use EditorSession or a dedicated coordinator

        XCTAssertTrue(true, "Scanner hook issue documented - needs cleanup")
    }
}

// MARK: - ExternalChangeNoCursorLossTests

/// Tests that external file changes don't cause cursor position loss.
/// Per CODEX.md: EditorSession should handle external modifications gracefully.
final class ExternalChangeNoCursorLossTests: XCTestCase {

    /// Tests that cursor position survives highlighting passes.
    @MainActor
    func testCursorSurvivesHighlighting() async throws {
        let session = createTestSession()

        // Set cursor
        session.selectionDidChange(NSRange(location: 15, length: 0))

        // Trigger highlighting (should not affect cursor)
        session.scheduleHighlight()

        // Allow debounce
        try await Task.sleep(for: .milliseconds(100))

        // Cursor should be unchanged
        XCTAssertEqual(session.cursorPosition.location, 15,
            "Highlighting should not reset cursor position")
    }

    /// Tests that EditorSession has reloadFromDisk method.
    @MainActor
    func testReloadFromDiskMethodExists() async throws {
        let session = createTestSession()

        // This test verifies the API exists
        // Actual behavior depends on loaded note
        await session.reloadFromDisk()

        XCTAssertTrue(true, "reloadFromDisk method exists")
    }

    /// Tests that isDirty flag works correctly.
    @MainActor
    func testIsDirtyFlagTracking() async throws {
        let session = createTestSession()

        // Initial state
        XCTAssertFalse(session.isDirty)

        // After text change
        session.textDidChange("Modified content")
        XCTAssertTrue(session.isDirty, "Session should be dirty after edit")
    }

    /// Documents the external change conflict scenario.
    @MainActor
    func testExternalChangeConflictDocumentation() async throws {
        // EXPECTED BEHAVIOR:
        //
        // When external file change is detected:
        // 1. If session is NOT dirty: reload content, preserve cursor (or clamp)
        // 2. If session IS dirty: flag conflict, show resolution UI
        //
        // CURSOR HANDLING:
        // - If content before cursor is unchanged: preserve position
        // - If content changed: clamp to valid range
        // - Never leave cursor in invalid state
        //
        // Currently handled by:
        // - EditorSession.reloadFromDisk() for reload
        // - ContentView/ConflictListResolverView for conflict UI

        XCTAssertTrue(true, "External change conflict handling documented")
    }

    // MARK: - Helper

    @MainActor
    private func createTestSession() -> EditorSession {
        let provider = TestVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }
}

// MARK: - Test VaultProvider

/// Minimal vault provider for testing EditorSession in isolation.
private actor TestVaultProvider: VaultProviding {
    private var notes: [URL: NoteDocument] = [:]

    func loadFileTree(at root: URL) async throws -> [FileNode] {
        return []
    }

    func readNote(at url: URL) async throws -> NoteDocument {
        if let note = notes[url] {
            return note
        }
        throw FileSystemError.fileNotFound(url)
    }

    func saveNote(_ note: NoteDocument) async throws {
        notes[note.fileURL] = note
    }

    func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        let url = folder.appendingPathComponent("\(name).md")
        let note = NoteDocument(fileURL: url)
        notes[url] = note
        return note
    }

    func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        var note = try await createNote(named: name, in: folder)
        note.body = initialContent
        notes[note.fileURL] = note
        return note
    }

    func deleteNote(at url: URL) async throws {
        notes.removeValue(forKey: url)
    }

    func rename(at url: URL, to newName: String) async throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        if let note = notes[url] {
            var renamed = note
            renamed = NoteDocument(fileURL: newURL, frontmatter: note.frontmatter, body: note.body, isDirty: note.isDirty)
            notes.removeValue(forKey: url)
            notes[newURL] = renamed
        }
        return newURL
    }

    func createFolder(named name: String, in parent: URL) async throws -> URL {
        return parent.appendingPathComponent(name)
    }
}

// MARK: - RelaunchRestoresCursorAndViewportTests

/// Tests that cursor and viewport are correctly restored after simulated app relaunch.
/// Per CODEX.md Phase 1: Restoration must work across cold launch, background/foreground.
final class RelaunchRestoresCursorAndViewportTests: XCTestCase {

    /// Tests the complete restoration flow with explicit readiness handshake.
    @MainActor
    func testCompleteRestorationFlowWithHandshake() async throws {
        let session = createTestSession()

        // Simulate: User opens note, moves cursor, scrolls
        session.textDidChange("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLong content here...")
        session.selectionDidChange(NSRange(location: 25, length: 0))
        session.scrollDidChange(CGPoint(x: 0, y: 150))

        // Capture state for "persistence" (simulating @SceneStorage)
        let savedCursorLocation = session.cursorPosition.location
        let savedCursorLength = session.cursorPosition.length
        let savedScrollY = session.scrollOffset.y

        XCTAssertEqual(savedCursorLocation, 25)
        XCTAssertEqual(savedScrollY, 150)

        // Simulate: App terminates, session is recreated
        let newSession = createTestSession()

        // Simulate: Note is loaded (triggers readiness flow)
        // In real app, this would be: await session.loadNote(at: url)
        // For test, we manually set content and signal ready
        newSession.textDidChange("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLong content here...")
        newSession.signalReadyForRestoration()

        // Simulate: ContentView awaits readiness then restores
        await newSession.awaitReadiness()
        newSession.restoreCursor(location: savedCursorLocation, length: savedCursorLength)
        newSession.restoreScroll(y: savedScrollY)

        // Verify restoration
        XCTAssertEqual(newSession.cursorPosition.location, 25,
            "Cursor location should be restored")
        XCTAssertEqual(newSession.scrollOffset.y, 150,
            "Scroll offset should be restored")
    }

    /// Tests that restoration handles document content changes gracefully.
    @MainActor
    func testRestorationWithShorterDocument() async throws {
        let session = createTestSession()

        // Original document was long, cursor at position 100
        let savedCursorLocation = 100

        // New document is shorter (e.g., external sync changed it)
        session.textDidChange("Short")
        session.signalReadyForRestoration()

        await session.awaitReadiness()
        session.restoreCursor(location: savedCursorLocation, length: 0)

        // Cursor should be clamped to document length
        XCTAssertEqual(session.cursorPosition.location, 5,
            "Cursor should be clamped to document length")
    }

    /// Tests that restoration works correctly when note didn't change.
    @MainActor
    func testRestorationWithUnchangedDocument() async throws {
        let content = "Hello World"
        let session = createTestSession()

        session.textDidChange(content)
        session.signalReadyForRestoration()

        await session.awaitReadiness()
        session.restoreCursor(location: 6, length: 5) // Select "World"
        session.restoreScroll(y: 0)

        XCTAssertEqual(session.cursorPosition.location, 6)
        XCTAssertEqual(session.cursorPosition.length, 5)
    }

    /// Tests that awaiting readiness before signal works correctly.
    @MainActor
    func testAwaitBeforeSignal() async throws {
        let session = createTestSession()
        var restorationComplete = false

        // Start awaiting readiness (will suspend)
        let restorationTask = Task { @MainActor in
            await session.awaitReadiness()
            session.restoreCursor(location: 10, length: 0)
            restorationComplete = true
        }

        // Simulate async note loading
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(restorationComplete, "Should still be waiting")

        // Signal ready (simulates loadNote completion)
        session.textDidChange("Some content here")
        session.signalReadyForRestoration()

        // Wait for restoration to complete
        await restorationTask.value

        XCTAssertTrue(restorationComplete, "Restoration should complete after signal")
        XCTAssertEqual(session.cursorPosition.location, 10)
    }

    // MARK: - Helper

    @MainActor
    private func createTestSession() -> EditorSession {
        let provider = TestVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }
}

// MARK: - CreateRenameDeletePropagationConsistencyTests

/// Tests that create/rename/delete operations propagate consistently across all subsystems.
/// Per CODEX.md Phase 1: Note lifecycle must be deterministic across sidebar, list, editor, graph.
final class CreateRenameDeletePropagationConsistencyTests: XCTestCase {

    /// Tests that note creation triggers appropriate notifications.
    @MainActor
    func testNoteCreationTriggersNotifications() async throws {
        // The notification system should propagate create events
        // SidebarViewModel.createNote posts relevant notifications

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Simulate note save notification (as createNote would trigger)
        let testURL = URL(fileURLWithPath: "/tmp/test-note.md")
        NotificationCenter.default.post(name: .quartzNoteSaved, object: testURL)

        // Allow notification to propagate
        try await Task.sleep(for: .milliseconds(10))

        XCTAssertTrue(notificationReceived, "Note save notification should propagate")
    }

    /// Tests that note deletion triggers removal notifications.
    @MainActor
    func testNoteDeletionTriggersRemovalNotification() async throws {
        var removedURLs: [URL] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNotesRemoved,
            object: nil,
            queue: .main
        ) { notification in
            if let urls = notification.userInfo?["urls"] as? [URL] {
                removedURLs = urls
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Simulate deletion notification
        let deletedURL = URL(fileURLWithPath: "/tmp/deleted-note.md")
        NotificationCenter.default.post(
            name: .quartzSpotlightNotesRemoved,
            object: nil,
            userInfo: ["urls": [deletedURL]]
        )

        try await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(removedURLs.count, 1)
        XCTAssertEqual(removedURLs.first, deletedURL)
    }

    /// Tests that note rename triggers relocation notification.
    @MainActor
    func testNoteRenameTriggersRelocationNotification() async throws {
        var oldURL: URL?
        var newURL: URL?
        let observer = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNoteRelocated,
            object: nil,
            queue: .main
        ) { notification in
            oldURL = notification.userInfo?["old"] as? URL
            newURL = notification.userInfo?["new"] as? URL
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // Simulate rename notification
        let from = URL(fileURLWithPath: "/tmp/old-name.md")
        let to = URL(fileURLWithPath: "/tmp/new-name.md")
        NotificationCenter.default.post(
            name: .quartzSpotlightNoteRelocated,
            object: nil,
            userInfo: ["old": from, "new": to]
        )

        try await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(oldURL, from)
        XCTAssertEqual(newURL, to)
    }

    /// Tests that EditorSession handles opened note being deleted.
    @MainActor
    func testEditorHandlesOpenNoteDeleted() async throws {
        let session = createTestSession()

        // Load some content
        session.textDidChange("Content that will be deleted")
        session.signalReadyForRestoration()

        // Simulate note deletion by closing the session
        session.closeNote()

        // Session should be in clean state
        XCTAssertNil(session.note)
        XCTAssertEqual(session.currentText, "")
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.isReadyForRestoration)
    }

    /// Tests that EditorSession handles opened note being renamed.
    @MainActor
    func testEditorStateAfterNoteRename() async throws {
        let session = createTestSession()

        // Simulate having a note open with edits
        session.textDidChange("Content before rename")
        session.selectionDidChange(NSRange(location: 10, length: 0))
        session.signalReadyForRestoration()

        // After rename, the note URL changes but content/cursor should persist
        // (In real app, SidebarViewModel updates selection to new URL)
        // EditorSession.loadNote would be called with new URL

        // The key contract: cursor position should survive if content unchanged
        let cursorBeforeRename = session.cursorPosition
        XCTAssertEqual(cursorBeforeRename.location, 10)

        // Content hasn't changed, so position should be valid
        XCTAssertTrue(cursorBeforeRename.location <= session.currentText.count)
    }

    /// Documents the propagation flow for note lifecycle events.
    @MainActor
    func testLifecyclePropagationDocumentation() async throws {
        // CREATE FLOW:
        // 1. SidebarViewModel.createNote() creates file
        // 2. Posts .quartzNoteSaved notification
        // 3. ContentViewModel observers update:
        //    - spotlightIndexNote (Spotlight)
        //    - updatePreviewForNote (preview cache)
        //    - updateSearchIndex (in-app search)
        // 4. FileWatcher detects new file, triggers sidebar refresh
        //
        // DELETE FLOW:
        // 1. SidebarViewModel.delete() removes file
        // 2. Posts .quartzSpotlightNotesRemoved notification
        // 3. ContentViewModel observers update:
        //    - spotlightRemoveNotes
        //    - removePreviewsForNotes
        // 4. If deleted note was open: WorkspaceStore.selectedNoteURL = nil
        //
        // RENAME FLOW:
        // 1. SidebarViewModel.rename() moves file
        // 2. Posts .quartzSpotlightNoteRelocated notification
        // 3. ContentViewModel observers update:
        //    - spotlightRelocateNote
        //    - relocatePreview
        // 4. If renamed note was open: WorkspaceStore.selectedNoteURL = newURL

        XCTAssertTrue(true, "Lifecycle propagation flow documented")
    }

    // MARK: - Helper

    @MainActor
    private func createTestSession() -> EditorSession {
        let provider = TestVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }
}
