import XCTest
@testable import QuartzKit

// MARK: - Editor Session Save Flow Tests
// Comprehensive tests for all user editing and save scenarios.
// These tests ensure that saves, version history, and dirty state work correctly
// across all possible user flows.

final class EditorSessionSaveFlowTests: XCTestCase {

    var session: EditorSession!
    var mockVaultProvider: AdvancedMockVaultProvider!
    var testVaultURL: URL!
    var testNoteURL: URL!

    @MainActor
    override func setUp() async throws {
        testVaultURL = URL(filePath: "/mock/vault")
        testNoteURL = testVaultURL.appending(path: "test-note.md")

        mockVaultProvider = AdvancedMockVaultProvider()

        // Add a test note to the mock
        let frontmatter = Frontmatter(
            title: "Test Note",
            createdAt: Date(),
            modifiedAt: Date()
        )
        let testNote = NoteDocument(
            fileURL: testNoteURL,
            frontmatter: frontmatter,
            body: "# Initial Content\n\nSome text here.",
            isDirty: false
        )
        await mockVaultProvider.addNote(testNote)

        let frontmatterParser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        session = EditorSession(
            vaultProvider: mockVaultProvider,
            frontmatterParser: frontmatterParser,
            inspectorStore: inspectorStore
        )
        session.vaultRootURL = testVaultURL
    }

    @MainActor
    override func tearDown() async throws {
        session = nil
        mockVaultProvider = nil
    }

    // MARK: - Flow 1: Load Note, Edit, Save

    /// Tests that a loaded note can be edited and saved.
    @MainActor
    func testLoadNoteEditAndSave() async throws {
        // Load the note
        await session.loadNote(at: testNoteURL)

        XCTAssertNotNil(session.note, "Note should be loaded")
        XCTAssertFalse(session.isDirty, "Fresh load should not be dirty")
        XCTAssertEqual(session.currentText, "# Initial Content\n\nSome text here.")

        // Simulate user typing
        session.textDidChange("# Initial Content\n\nSome text here. Added text.")

        XCTAssertTrue(session.isDirty, "After edit, should be dirty")

        // Manual save
        await session.save()

        // Verify save occurred
        XCTAssertFalse(session.isDirty, "After save, should not be dirty")

        let operations = await mockVaultProvider.operations
        XCTAssertTrue(operations.contains { $0.0 == .saveNote }, "saveNote should have been called")
    }

    /// Tests that isDirty flag is set correctly on text change.
    @MainActor
    func testIsDirtySetOnTextChange() async throws {
        await session.loadNote(at: testNoteURL)

        XCTAssertFalse(session.isDirty)

        // Single character edit
        session.textDidChange("# Initial Content\n\nSome text here.X")

        XCTAssertTrue(session.isDirty, "Single char edit should set dirty")
    }

    // MARK: - Flow 2: Edit, Save, Edit Again, Save Again

    /// Tests multiple edit-save cycles on the same note.
    @MainActor
    func testMultipleEditSaveCycles() async throws {
        await session.loadNote(at: testNoteURL)

        // First edit
        session.textDidChange("First edit")
        XCTAssertTrue(session.isDirty)

        await session.save()
        XCTAssertFalse(session.isDirty, "After first save, should not be dirty")

        let countAfterFirst = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertEqual(countAfterFirst, 1)

        // Second edit
        session.textDidChange("Second edit")
        XCTAssertTrue(session.isDirty)

        await session.save()
        XCTAssertFalse(session.isDirty, "After second save, should not be dirty")

        let countAfterSecond = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertEqual(countAfterSecond, 2)

        // Third edit
        session.textDidChange("Third edit")
        XCTAssertTrue(session.isDirty)

        await session.save()
        XCTAssertFalse(session.isDirty, "After third save, should not be dirty")

        let countAfterThird = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertEqual(countAfterThird, 3)
    }

    // MARK: - Flow 3: Switch Notes, Come Back, Edit (CRITICAL)

    /// Tests that editing works after switching notes and returning.
    /// THIS IS THE BUG SCENARIO REPORTED BY USER.
    @MainActor
    func testSwitchNotesAndReturnThenEdit() async throws {
        // Create a second note
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        let secondNote = NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second note content",
            isDirty: false
        )
        await mockVaultProvider.addNote(secondNote)

        // Load first note
        await session.loadNote(at: testNoteURL)
        XCTAssertEqual(session.note?.fileURL, testNoteURL)

        // Edit first note
        session.textDidChange("First note edited")
        XCTAssertTrue(session.isDirty)
        await session.save()
        XCTAssertFalse(session.isDirty)

        let saveCountAfterFirstEdit = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count

        // Switch to second note
        await session.loadNote(at: secondNoteURL)
        XCTAssertEqual(session.note?.fileURL, secondNoteURL)
        XCTAssertFalse(session.isDirty, "Fresh load of second note should not be dirty")
        XCTAssertEqual(session.currentText, "Second note content")

        // Switch back to first note
        await session.loadNote(at: testNoteURL)
        XCTAssertEqual(session.note?.fileURL, testNoteURL)
        XCTAssertFalse(session.isDirty, "Fresh load of first note should not be dirty")

        // CRITICAL: Verify currentText is correct after return
        let savedContent = await mockVaultProvider.getContent(for: testNoteURL)
        XCTAssertEqual(session.currentText, savedContent,
            "currentText should match saved content after returning")

        // Edit first note again - THIS IS THE CRITICAL TEST
        let newContent = session.currentText + " - edited after return"
        session.textDidChange(newContent)

        XCTAssertTrue(session.isDirty,
            "CRITICAL: Edit after returning to note MUST set dirty flag")
        XCTAssertEqual(session.currentText, newContent,
            "currentText should be updated after edit")

        await session.save()

        XCTAssertFalse(session.isDirty, "Save after return should clear dirty")

        let finalSaveCount = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertGreaterThan(finalSaveCount, saveCountAfterFirstEdit,
            "CRITICAL: Save MUST be called after editing returned note")
    }

    /// Tests that currentText is properly synced after note switch.
    @MainActor
    func testCurrentTextSyncAfterNoteSwitch() async throws {
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        let secondNote = NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second content",
            isDirty: false
        )
        await mockVaultProvider.addNote(secondNote)

        // Load first, edit, save
        await session.loadNote(at: testNoteURL)
        session.textDidChange("Modified first")
        await session.save()

        // Load second
        await session.loadNote(at: secondNoteURL)
        XCTAssertEqual(session.currentText, "Second content",
            "currentText should match second note content")

        // Load first again
        await session.loadNote(at: testNoteURL)

        // CRITICAL: currentText should be the SAVED content, not stale
        let savedFirstContent = await mockVaultProvider.getContent(for: testNoteURL)
        XCTAssertEqual(session.currentText, savedFirstContent,
            "currentText should match saved first note content")
    }

    /// Tests rapid note switching doesn't break save.
    @MainActor
    func testRapidNoteSwitching() async throws {
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        let thirdNoteURL = testVaultURL.appending(path: "third-note.md")

        await mockVaultProvider.addNote(NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second note",
            isDirty: false
        ))
        await mockVaultProvider.addNote(NoteDocument(
            fileURL: thirdNoteURL,
            frontmatter: Frontmatter(title: "Third", createdAt: Date(), modifiedAt: Date()),
            body: "Third note",
            isDirty: false
        ))

        // Rapid switching
        await session.loadNote(at: testNoteURL)
        await session.loadNote(at: secondNoteURL)
        await session.loadNote(at: thirdNoteURL)
        await session.loadNote(at: testNoteURL)

        // Verify we're on the right note
        XCTAssertEqual(session.note?.fileURL, testNoteURL)

        // Now edit - should still work
        session.textDidChange("Edited after rapid switching")
        XCTAssertTrue(session.isDirty, "Edit after rapid switching should set dirty")

        await session.save()
        XCTAssertFalse(session.isDirty)

        let saveCount = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertGreaterThan(saveCount, 0, "Save should have occurred")
    }

    // MARK: - Flow 4: Edit Without Switching

    /// Tests continuous editing without switching notes.
    @MainActor
    func testContinuousEditing() async throws {
        await session.loadNote(at: testNoteURL)

        // Simulate typing multiple characters
        var text = session.currentText
        for i in 0..<10 {
            text += "\(i)"
            session.textDidChange(text)
            XCTAssertTrue(session.isDirty, "Should be dirty after edit \(i)")
        }

        await session.save()
        XCTAssertFalse(session.isDirty)
    }

    // MARK: - Flow 5: No Edit, No Save

    /// Tests that no save occurs if no edit was made.
    @MainActor
    func testNoSaveWithoutEdit() async throws {
        await session.loadNote(at: testNoteURL)

        XCTAssertFalse(session.isDirty)

        // Don't edit, just try to save
        await session.save()

        let saveCount = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertEqual(saveCount, 0, "Save should not be called when not dirty")
    }

    /// Tests that identical text doesn't trigger dirty state.
    @MainActor
    func testIdenticalTextDoesNotTriggerDirty() async throws {
        await session.loadNote(at: testNoteURL)
        let originalText = session.currentText

        XCTAssertFalse(session.isDirty)

        // "Edit" with identical content
        session.textDidChange(originalText)

        XCTAssertFalse(session.isDirty, "Identical text should not set dirty")
    }

    // MARK: - Flow 6: Close Note, Reopen, Edit

    /// Tests editing works after closing and reopening a note.
    @MainActor
    func testCloseAndReopenNote() async throws {
        await session.loadNote(at: testNoteURL)

        // Edit and save
        session.textDidChange("Edited content")
        await session.save()

        // Close the note
        session.closeNote()
        XCTAssertNil(session.note)
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.currentText, "")

        // Reopen the same note
        await session.loadNote(at: testNoteURL)
        XCTAssertNotNil(session.note)
        XCTAssertFalse(session.isDirty)

        // Verify content loaded correctly
        let savedContent = await mockVaultProvider.getContent(for: testNoteURL)
        XCTAssertEqual(session.currentText, savedContent)

        // Edit again - should work
        session.textDidChange("Edited after close and reopen")
        XCTAssertTrue(session.isDirty, "Edit after reopen should set dirty")

        await session.save()
        XCTAssertFalse(session.isDirty)
    }

    // MARK: - Flow 7: Manual Save

    /// Tests manual save (Cmd+S) works correctly.
    @MainActor
    func testManualSave() async throws {
        await session.loadNote(at: testNoteURL)

        session.textDidChange("Content for manual save")
        XCTAssertTrue(session.isDirty)

        // Manual save should be immediate
        await session.manualSave()

        XCTAssertFalse(session.isDirty)

        let saveCount = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertGreaterThan(saveCount, 0)
    }

    /// Tests manual save when not dirty still saves (force).
    @MainActor
    func testManualSaveWhenNotDirty() async throws {
        await session.loadNote(at: testNoteURL)

        XCTAssertFalse(session.isDirty)

        // Manual save should force save even when not dirty
        await session.manualSave()

        let saveCount = await mockVaultProvider.operations.filter { $0.0 == .saveNote }.count
        XCTAssertGreaterThan(saveCount, 0, "Manual save should force save even when not dirty")
    }

    // MARK: - Flow 8: Save Error Recovery

    /// Tests that save error sets error message.
    @MainActor
    func testSaveErrorSetsErrorMessage() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure mock to fail
        await mockVaultProvider.simulateError(.diskFull, for: .saveNote)

        session.textDidChange("Content that will fail to save")
        XCTAssertTrue(session.isDirty)

        await session.save()

        // Should still be dirty after failed save
        XCTAssertTrue(session.isDirty, "Should remain dirty after save failure")
        XCTAssertNotNil(session.errorMessage, "Error message should be set")
    }

    // MARK: - Flow 9: Note Property Consistency

    /// Tests that note property is correct after switch.
    @MainActor
    func testNotePropertyAfterSwitch() async throws {
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        await mockVaultProvider.addNote(NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second content",
            isDirty: false
        ))

        await session.loadNote(at: testNoteURL)
        XCTAssertEqual(session.note?.fileURL, testNoteURL)

        await session.loadNote(at: secondNoteURL)
        XCTAssertEqual(session.note?.fileURL, secondNoteURL)

        await session.loadNote(at: testNoteURL)
        XCTAssertEqual(session.note?.fileURL, testNoteURL)

        // Edit - note should still be the first note
        session.textDidChange("Edit after switches")
        XCTAssertEqual(session.note?.fileURL, testNoteURL,
            "Note URL should be preserved after edit")
    }

    // MARK: - Flow 10: Orange Indicator (isDirty) Lifecycle

    /// Tests the orange unsaved indicator appears and disappears correctly.
    @MainActor
    func testUnsavedIndicatorLifecycle() async throws {
        await session.loadNote(at: testNoteURL)

        // Initially no indicator
        XCTAssertFalse(session.isDirty, "No indicator on fresh load")

        // Edit shows indicator
        session.textDidChange("New content")
        XCTAssertTrue(session.isDirty, "Indicator should show after edit")

        // Save clears indicator
        await session.save()
        XCTAssertFalse(session.isDirty, "Indicator should clear after save")

        // Another edit shows indicator again
        session.textDidChange("More content")
        XCTAssertTrue(session.isDirty, "Indicator should show after second edit")

        // Another save clears again
        await session.save()
        XCTAssertFalse(session.isDirty, "Indicator should clear after second save")
    }

    // MARK: - Flow 11: Verify Save Actually Persists Content

    /// Tests that saved content is actually persisted.
    @MainActor
    func testSaveActuallyPersistsContent() async throws {
        await session.loadNote(at: testNoteURL)

        let newContent = "This is the new content that should be saved"
        session.textDidChange(newContent)
        await session.save()

        // Verify the mock received the correct content
        let savedContent = await mockVaultProvider.getContent(for: testNoteURL)
        XCTAssertEqual(savedContent, newContent,
            "Saved content should match what was edited")
    }

    /// Tests that content persists across note switches.
    @MainActor
    func testContentPersistsAcrossNoteSwitches() async throws {
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        await mockVaultProvider.addNote(NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second content",
            isDirty: false
        ))

        // Edit and save first note
        await session.loadNote(at: testNoteURL)
        let editedContent = "Edited first note content"
        session.textDidChange(editedContent)
        await session.save()

        // Switch to second note
        await session.loadNote(at: secondNoteURL)

        // Switch back to first note
        await session.loadNote(at: testNoteURL)

        // Content should be the edited version
        XCTAssertEqual(session.currentText, editedContent,
            "Content should persist across note switches")
    }

    // MARK: - Flow 12: Switch Without Edit Should Not Dirty

    /// Tests that switching notes without editing doesn't set dirty.
    @MainActor
    func testSwitchWithoutEditDoesNotDirty() async throws {
        let secondNoteURL = testVaultURL.appending(path: "second-note.md")
        await mockVaultProvider.addNote(NoteDocument(
            fileURL: secondNoteURL,
            frontmatter: Frontmatter(title: "Second", createdAt: Date(), modifiedAt: Date()),
            body: "Second content",
            isDirty: false
        ))

        // Load first
        await session.loadNote(at: testNoteURL)
        XCTAssertFalse(session.isDirty)

        // Switch to second (no edit)
        await session.loadNote(at: secondNoteURL)
        XCTAssertFalse(session.isDirty)

        // Switch back to first (no edit)
        await session.loadNote(at: testNoteURL)
        XCTAssertFalse(session.isDirty,
            "Switching without editing should not set dirty")
    }

    // MARK: - Flow 13: Edit After Load Without Switch

    /// Tests basic edit immediately after load.
    @MainActor
    func testEditImmediatelyAfterLoad() async throws {
        await session.loadNote(at: testNoteURL)

        // Immediate edit
        session.textDidChange("Immediate edit")

        XCTAssertTrue(session.isDirty, "Immediate edit should set dirty")
        XCTAssertEqual(session.currentText, "Immediate edit")
    }

    // MARK: - Flow 14: Multiple Rapid Edits

    /// Tests that rapid edits all register correctly.
    @MainActor
    func testRapidEditsAllRegister() async throws {
        await session.loadNote(at: testNoteURL)

        // Rapid edits
        session.textDidChange("Edit 1")
        XCTAssertEqual(session.currentText, "Edit 1")
        XCTAssertTrue(session.isDirty)

        session.textDidChange("Edit 2")
        XCTAssertEqual(session.currentText, "Edit 2")
        XCTAssertTrue(session.isDirty)

        session.textDidChange("Edit 3")
        XCTAssertEqual(session.currentText, "Edit 3")
        XCTAssertTrue(session.isDirty)

        await session.save()
        XCTAssertFalse(session.isDirty)

        let savedContent = await mockVaultProvider.getContent(for: testNoteURL)
        XCTAssertEqual(savedContent, "Edit 3",
            "Final edit should be the saved content")
    }

    // MARK: - Flow 15: Concurrent Save Attempts

    /// Tests that concurrent save attempts don't permanently block isSaving.
    @MainActor
    func testConcurrentSaveDoesNotPermanentlyBlock() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure a slow save
        await mockVaultProvider.simulateDelay(0.5, for: .saveNote)

        session.textDidChange("First edit")
        XCTAssertTrue(session.isDirty)

        // Start first save (will be slow)
        let firstSave = Task {
            await session.save()
        }

        // Give it a moment to start
        try await Task.sleep(for: .milliseconds(50))

        // Try concurrent save - should bail (isSaving = true)
        await session.save()

        // Wait for first save to complete
        await firstSave.value

        // CRITICAL: isSaving should now be false
        XCTAssertFalse(session.isSaving,
            "CRITICAL: isSaving must be false after save completes")

        // Should be able to save again
        session.textDidChange("Second edit")
        await session.save()

        XCTAssertFalse(session.isDirty,
            "Should be able to save after previous save completed")
    }

    // MARK: - Flow 16: Save During Typing

    /// Tests that typing during save doesn't permanently block saves.
    @MainActor
    func testTypingDuringSaveDoesNotBlock() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure a slow save
        await mockVaultProvider.simulateDelay(0.3, for: .saveNote)

        session.textDidChange("Initial edit")

        // Start save
        let saveTask = Task {
            await session.save()
        }

        // Type during save
        try await Task.sleep(for: .milliseconds(50))
        session.textDidChange("Typed during save")
        XCTAssertTrue(session.isDirty)

        // Wait for first save
        await saveTask.value

        // After save, should still be dirty (typed during save)
        // and isSaving should be false
        XCTAssertFalse(session.isSaving,
            "isSaving must be false after save completes")

        // Now should be able to save the new content
        await session.save()
        XCTAssertFalse(session.isDirty)
    }

    // MARK: - Flow 17: isSaving State Invariant

    /// Tests that isSaving is always false when no save is in progress.
    @MainActor
    func testIsSavingInvariant() async throws {
        // Initially false
        XCTAssertFalse(session.isSaving)

        await session.loadNote(at: testNoteURL)
        XCTAssertFalse(session.isSaving)

        session.textDidChange("Edit")
        XCTAssertFalse(session.isSaving) // Still false until save starts

        await session.save()
        XCTAssertFalse(session.isSaving) // False after save completes

        // Multiple saves
        for i in 0..<5 {
            session.textDidChange("Edit \(i)")
            await session.save()
            XCTAssertFalse(session.isSaving,
                "isSaving must be false after save \(i)")
        }
    }

    // MARK: - Flow 18: Save Timeout Recovery (CRITICAL)

    /// Tests that a hanging save operation times out and doesn't permanently block.
    /// THIS TEST CATCHES THE BUG: iCloud coordination hanging indefinitely.
    @MainActor
    func testSaveTimeoutDoesNotPermanentlyBlock() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure mock to hang for a very long time (simulating stuck iCloud)
        await mockVaultProvider.simulateDelay(30.0, for: .saveNote) // 30 seconds

        session.textDidChange("Content that will timeout")
        XCTAssertTrue(session.isDirty)

        // Start save with a timeout expectation
        // The save should timeout (if properly implemented) or complete
        // Either way, isSaving MUST be false after
        let saveTask = Task {
            await session.save()
        }

        // Wait a reasonable amount of time (more than normal save, less than hang)
        try await Task.sleep(for: .seconds(2))

        // Cancel the slow save task
        saveTask.cancel()

        // Give it a moment to clean up
        try await Task.sleep(for: .milliseconds(100))

        // CRITICAL: Even if save timed out or was cancelled, isSaving must be reset
        // This is the bug we're catching - if isSaving stays true, future saves fail
        XCTAssertFalse(session.isSaving,
            "CRITICAL BUG: isSaving must be false after save timeout/cancel")

        // Clear the delay for next test
        await mockVaultProvider.clearSimulatedError(for: .saveNote)

        // Verify we can still save after the timeout
        session.textDidChange("Content after timeout")
        await session.save()
        XCTAssertFalse(session.isDirty,
            "Should be able to save after previous timeout")
    }

    // MARK: - Flow 19: Save Error Clears isSaving

    /// Tests that save errors properly reset isSaving flag.
    @MainActor
    func testSaveErrorClearsIsSaving() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure mock to fail
        await mockVaultProvider.simulateError(.diskFull, for: .saveNote)

        session.textDidChange("Content that will fail")
        XCTAssertTrue(session.isDirty)

        await session.save()

        // CRITICAL: isSaving must be false even after error
        XCTAssertFalse(session.isSaving,
            "isSaving must be false after save error")
        XCTAssertTrue(session.isDirty,
            "isDirty should remain true after failed save")

        // Clear error and verify we can save again
        await mockVaultProvider.clearSimulatedError(for: .saveNote)

        await session.save()
        XCTAssertFalse(session.isDirty)
    }

    // MARK: - Flow 20: Autosave After Failed Save

    /// Tests that autosave is rescheduled after a failed save.
    @MainActor
    func testAutosaveRescheduledAfterFailure() async throws {
        await session.loadNote(at: testNoteURL)

        // Configure mock to fail once
        await mockVaultProvider.simulateError(.networkUnavailable, for: .saveNote)

        session.textDidChange("Content that will initially fail")

        // First save attempt should fail
        await session.save()
        XCTAssertTrue(session.isDirty, "Should still be dirty after failed save")
        XCTAssertFalse(session.isSaving, "isSaving must be false")

        // Clear the error
        await mockVaultProvider.clearSimulatedError(for: .saveNote)

        // The error handler should have scheduled another autosave
        // Wait for it to trigger
        try await Task.sleep(for: .seconds(1.5))

        // Now it should have saved successfully
        XCTAssertFalse(session.isDirty, "Rescheduled autosave should have succeeded")
    }
}
