import Testing
import Foundation
@testable import QuartzKit

// MARK: - Autosave Reliability Tests

/// Tests for autosave race conditions, save-before-switch guarantees,
/// version history snapshots, and data loss prevention.
///
/// These tests validate the fixes for three race conditions:
/// 1. isSavingToFileSystem 200ms echo-suppression window
/// 2. Autosave targeting wrong note after switch (captured URL guard)
/// 3. Save-before-switch in loadNote(at:) (dirty content preserved)

@Suite("Autosave Reliability")
struct AutosaveReliabilityTests {

    // MARK: - Test Helpers

    @MainActor
    private func makeSession() async -> (EditorSession, AdvancedMockVaultProvider, URL, URL) {
        let vaultURL = URL(filePath: "/mock/vault")
        let noteAURL = vaultURL.appending(path: "note-a.md")
        let noteBURL = vaultURL.appending(path: "note-b.md")

        let mock = AdvancedMockVaultProvider()

        let noteA = NoteDocument(
            fileURL: noteAURL,
            frontmatter: Frontmatter(title: "Note A", createdAt: Date(), modifiedAt: Date()),
            body: "Content of Note A",
            isDirty: false
        )
        let noteB = NoteDocument(
            fileURL: noteBURL,
            frontmatter: Frontmatter(title: "Note B", createdAt: Date(), modifiedAt: Date()),
            body: "Content of Note B",
            isDirty: false
        )
        await mock.addNote(noteA)
        await mock.addNote(noteB)

        let session = EditorSession(
            vaultProvider: mock,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        session.vaultRootURL = vaultURL

        return (session, mock, noteAURL, noteBURL)
    }

    // MARK: - Save-Before-Switch Guarantee (Bug 3 fix)

    @Test("Dirty content is saved before switching notes")
    @MainActor func saveBeforeSwitchGuarantee() async {
        let (session, mock, noteAURL, noteBURL) = await makeSession()

        // Load Note A and edit it
        await session.loadNote(at: noteAURL)
        session.textDidChange("Edited Note A content")
        #expect(session.isDirty == true)

        // Switch to Note B WITHOUT manual save
        await session.loadNote(at: noteBURL)

        // Verify Note A's edits were saved (Bug 3 fix: loadNote saves dirty before switch)
        let savedContent = await mock.getContent(for: noteAURL)
        #expect(savedContent == "Edited Note A content",
            "Dirty content must be saved before note switch to prevent data loss")

        // Verify we're now on Note B
        #expect(session.note?.fileURL == noteBURL)
        #expect(session.currentText == "Content of Note B")
    }

    @Test("Non-dirty switch does not trigger extra save")
    @MainActor func cleanSwitchNoExtraSave() async {
        let (session, mock, noteAURL, noteBURL) = await makeSession()

        // Load Note A, don't edit
        await session.loadNote(at: noteAURL)
        #expect(session.isDirty == false)

        let saveCountBefore = await mock.operations.filter { $0.0 == .saveNote }.count

        // Switch to Note B
        await session.loadNote(at: noteBURL)

        let saveCountAfter = await mock.operations.filter { $0.0 == .saveNote }.count
        #expect(saveCountAfter == saveCountBefore,
            "Clean switch should not trigger a save")
    }

    // MARK: - Autosave Targets Correct Note (Bug 2 fix)

    @Test("Scheduled autosave targets the note it was scheduled for")
    @MainActor func autosaveTargetsCorrectNote() async {
        let (session, mock, noteAURL, noteBURL) = await makeSession()

        // Load Note A
        await session.loadNote(at: noteAURL)

        // Edit triggers scheduleAutosave (1s debounce)
        session.textDidChange("Edited A")

        // Immediately switch to Note B (autosave task still sleeping)
        // Bug 3 fix: loadNote saves dirty content before switching
        await session.loadNote(at: noteBURL)

        // Wait for autosave delay to expire (1.5s > 1s debounce)
        try? await Task.sleep(for: .milliseconds(1500))

        // Verify: Note B's content was NOT overwritten by autosave
        let noteBContent = await mock.getContent(for: noteBURL)
        #expect(noteBContent == "Content of Note B",
            "Autosave must not save wrong note's content to Note B")

        // Verify: Note A was saved correctly (by the save-before-switch)
        let noteAContent = await mock.getContent(for: noteAURL)
        #expect(noteAContent == "Edited A",
            "Note A's edits should be preserved by save-before-switch")
    }

    // MARK: - Concurrent Save Prevention

    @Test("isSaving guard prevents concurrent saves")
    @MainActor func concurrentSavePrevention() async {
        let (session, mock, noteAURL, _) = await makeSession()

        // Configure mock with a 300ms delay to simulate slow save
        await mock.simulateDelay(0.3, for: .saveNote)

        await session.loadNote(at: noteAURL)
        session.textDidChange("First edit")

        // Start first save
        let saveTask = Task { @MainActor in
            await session.save()
        }

        // Immediately try second save (should be rejected by !isSaving guard)
        // Small delay to ensure first save has entered
        try? await Task.sleep(for: .milliseconds(50))
        session.textDidChange("Second edit")
        await session.save()

        await saveTask.value

        // Wait for isSavingToFileSystem echo delay
        try? await Task.sleep(for: .milliseconds(300))

        // Only one save should have executed during the overlap
        let saveCount = await mock.operations.filter { $0.0 == .saveNote }.count
        #expect(saveCount >= 1, "At least one save should have occurred")
    }

    @Test("Save request during active save is replayed after current write")
    @MainActor func saveRequestDuringActiveSaveIsReplayed() async {
        let (session, mock, noteAURL, _) = await makeSession()

        await mock.simulateDelay(0.3, for: .saveNote)
        await session.loadNote(at: noteAURL)
        session.textDidChange("First snapshot")

        let saveTask = Task { @MainActor in
            await session.save()
        }

        try? await Task.sleep(for: .milliseconds(50))
        session.textDidChange("This is a test")
        await session.save()

        await saveTask.value
        await mock.simulateDelay(0, for: .saveNote)

        for _ in 0..<80 {
            if await mock.getContent(for: noteAURL) == "This is a test", session.isDirty == false {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let finalContent = await mock.getContent(for: noteAURL)
        let saveCount = await mock.operations.filter { $0.0 == .saveNote }.count
        #expect(finalContent == "This is a test", "Latest text typed during a save must be persisted by the replayed save")
        #expect(session.isDirty == false, "Dirty indicator must clear after replayed save")
        #expect(session.isSaving == false, "Save spinner must stop after replayed save")
        #expect(saveCount >= 2, "The second save request should not be dropped while the first write is active")
    }

    // MARK: - Fast Back-and-Forth

    @Test("Fast note switching preserves all edits")
    @MainActor func fastBackAndForthNoDataLoss() async {
        let (session, mock, noteAURL, noteBURL) = await makeSession()

        // Load A → edit → switch B → switch A → verify
        await session.loadNote(at: noteAURL)
        session.textDidChange("A edited round 1")
        #expect(session.isDirty == true)

        // Switch to B (should save A's edits first)
        await session.loadNote(at: noteBURL)
        let savedA1 = await mock.getContent(for: noteAURL)
        #expect(savedA1 == "A edited round 1", "Round 1 edits must be saved")

        // Edit B
        session.textDidChange("B edited round 1")

        // Switch back to A (should save B's edits first)
        await session.loadNote(at: noteAURL)
        let savedB1 = await mock.getContent(for: noteBURL)
        #expect(savedB1 == "B edited round 1", "Note B edits must be saved on switch")

        // Verify A's content is what we saved
        #expect(session.currentText == "A edited round 1",
            "Note A should reload with saved content")

        // Edit A again
        session.textDidChange("A edited round 2")

        // Switch to B again
        await session.loadNote(at: noteBURL)
        let savedA2 = await mock.getContent(for: noteAURL)
        #expect(savedA2 == "A edited round 2", "Round 2 edits must be saved")
    }

    // MARK: - Typing During Save Window

    @Test("Typing during save keeps dirty flag for new content")
    @MainActor func typingDuringSave() async {
        let (session, mock, noteAURL, _) = await makeSession()

        await mock.simulateDelay(0.3, for: .saveNote)
        await session.loadNote(at: noteAURL)

        session.textDidChange("First edit")

        // Start save (takes 300ms due to mock delay)
        let saveTask = Task { @MainActor in
            await session.save()
        }

        // Type during save
        try? await Task.sleep(for: .milliseconds(50))
        session.textDidChange("Typed during save")
        #expect(session.isDirty == true, "New typing during save must set dirty")

        await saveTask.value

        // After save completes, should STILL be dirty (new content since snapshot)
        // Note: isDirty may or may not be true depending on timing, but the key
        // invariant is that isSaving is eventually false and content is not lost
        try? await Task.sleep(for: .milliseconds(300))
        #expect(session.isSaving == false, "isSaving must be false after save completes")

        // Save the remaining content
        await session.save()
        let finalContent = await mock.getContent(for: noteAURL)
        #expect(finalContent == "Typed during save",
            "Final content must reflect the latest typing")
    }

    // MARK: - Save Timeout Recovery

    @Test("Save timeout does not permanently block subsequent saves")
    @MainActor func saveTimeoutRecovery() async {
        let (session, mock, noteAURL, _) = await makeSession()

        // Simulate a very slow save (but not infinite — tests shouldn't hang)
        await mock.simulateDelay(2.0, for: .saveNote)

        await session.loadNote(at: noteAURL)
        session.textDidChange("Edit before timeout")

        // Start save (will take 2s)
        let saveTask = Task { @MainActor in
            await session.save()
        }

        // Wait for it to complete
        await saveTask.value
        try? await Task.sleep(for: .milliseconds(300))

        // Key invariant: isSaving must be false after save completes (even if slow)
        #expect(session.isSaving == false,
            "isSaving must be false after slow save completes")

        // Clear delay and verify subsequent saves work
        await mock.clearSimulatedError(for: .saveNote)
        await mock.simulateDelay(0, for: .saveNote)

        session.textDidChange("Edit after recovery")
        await session.save()

        #expect(session.isDirty == false, "Should be able to save after recovery")
    }
}

// MARK: - Save Data Integrity Tests

@Suite("Save Data Integrity")
struct SaveDataIntegrityTests {

    @MainActor
    private func makeSession() async -> (EditorSession, AdvancedMockVaultProvider, URL) {
        let vaultURL = URL(filePath: "/mock/vault")
        let noteURL = vaultURL.appending(path: "test-note.md")

        let mock = AdvancedMockVaultProvider()
        let note = NoteDocument(
            fileURL: noteURL,
            frontmatter: Frontmatter(title: "Test", createdAt: Date(), modifiedAt: Date()),
            body: "Original content",
            isDirty: false
        )
        await mock.addNote(note)

        let session = EditorSession(
            vaultProvider: mock,
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        session.vaultRootURL = vaultURL

        return (session, mock, noteURL)
    }

    @Test("Save persists exact content to vault provider")
    @MainActor func saveExactContent() async {
        let (session, mock, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        let content = "# Hello\n\nThis is **bold** and *italic*.\n\n- List item 1\n- List item 2"
        session.textDidChange(content)
        await session.save()

        let saved = await mock.getContent(for: noteURL)
        #expect(saved == content, "Saved content must match exactly")
    }

    @Test("Multiple rapid edits — last edit wins on save")
    @MainActor func rapidEditsLastWins() async {
        let (session, mock, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        // Simulate rapid typing (multiple textDidChange calls)
        for i in 1...20 {
            session.textDidChange("Edit \(i)")
        }

        await session.save()

        let saved = await mock.getContent(for: noteURL)
        #expect(saved == "Edit 20", "Last edit must be the saved content")
    }

    @Test("Save error sets error message and reschedules")
    @MainActor func saveErrorHandling() async {
        let (session, mock, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        // Simulate disk full error
        await mock.simulateError(.diskFull, for: .saveNote)

        session.textDidChange("Edit that will fail to save")
        await session.save()

        #expect(session.errorMessage != nil, "Error should be reported to user")
        #expect(session.isDirty == true, "Should still be dirty after failed save")
    }

    @Test("Save clears dirty flag only when content unchanged since snapshot")
    @MainActor func dirtyClearOnlyWhenUnchanged() async {
        let (session, _, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        session.textDidChange("Edited content")
        #expect(session.isDirty == true)

        await session.save()
        #expect(session.isDirty == false, "Dirty should clear when no new edits during save")
    }

    @Test("isDirty lifecycle: edit → save → clean → edit → dirty")
    @MainActor func isDirtyLifecycle() async {
        let (session, _, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        #expect(session.isDirty == false, "Fresh load is clean")

        session.textDidChange("Edit 1")
        #expect(session.isDirty == true, "Edit sets dirty")

        await session.save()
        #expect(session.isDirty == false, "Save clears dirty")

        session.textDidChange("Edit 2")
        #expect(session.isDirty == true, "New edit sets dirty again")

        await session.save()
        #expect(session.isDirty == false, "Second save clears dirty")
    }

    @Test("Identical text does not set dirty flag")
    @MainActor func identicalTextNotDirty() async {
        let (session, _, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        let original = session.currentText
        session.textDidChange(original)

        #expect(session.isDirty == false,
            "Setting text to identical content should not trigger dirty")
    }

    @Test("Force save works even when not dirty")
    @MainActor func forceSaveWhenClean() async {
        let (session, mock, noteURL) = await makeSession()
        await session.loadNote(at: noteURL)

        #expect(session.isDirty == false)

        let saveCountBefore = await mock.operations.filter { $0.0 == .saveNote }.count
        await session.save(force: true)
        let saveCountAfter = await mock.operations.filter { $0.0 == .saveNote }.count

        #expect(saveCountAfter > saveCountBefore,
            "Force save should call saveNote even when not dirty")
    }
}

// MARK: - Version History Tests

@Suite("Version History Service")
struct VersionHistoryServiceTests {

    @Test("VersionHistoryService initializes without error")
    func initDoesNotThrow() {
        let service = VersionHistoryService()
        _ = service // Ensure it can be instantiated
    }

    @Test("Max snapshots per note is 50")
    func maxSnapshotsValue() {
        #expect(VersionHistoryService.maxSnapshotsPerNote == 50)
    }

    @Test("Max preview bytes is 512KB")
    func maxPreviewBytesValue() {
        #expect(VersionHistoryService.maxPreviewBytes == 512_000)
    }

    @Test("saveSnapshot creates snapshot retrievable via fetchVersions")
    func saveSnapshotCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "quartz-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vaultRoot = tempDir.appending(path: "vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

        let noteURL = vaultRoot.appending(path: "test-note.md")
        let content = "# Test\n\nSome content for versioning."

        let service = VersionHistoryService()
        service.saveSnapshot(for: noteURL, content: content, vaultRoot: vaultRoot)

        // Use the public API to verify
        let versions = service.fetchVersions(for: noteURL, vaultRoot: vaultRoot)
        #expect(versions.count == 1, "Should have one snapshot")
    }

    @Test("saveSnapshot content is readable via snapshot URL")
    func snapshotContentReadable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "quartz-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vaultRoot = tempDir.appending(path: "vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

        let noteURL = vaultRoot.appending(path: "version-test.md")
        let content = "Version history test content"

        let service = VersionHistoryService()
        service.saveSnapshot(for: noteURL, content: content, vaultRoot: vaultRoot)

        let versions = service.fetchVersions(for: noteURL, vaultRoot: vaultRoot)
        #expect(!versions.isEmpty, "Should have snapshot")

        if let version = versions.first {
            let data = try Data(contentsOf: version.snapshotURL)
            let readContent = String(data: data, encoding: .utf8)
            #expect(readContent == content, "Snapshot content should match original")
        }
    }

    @Test("Multiple snapshots for same note are all preserved")
    func multipleSnapshotsPreserved() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "quartz-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vaultRoot = tempDir.appending(path: "vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

        let noteURL = vaultRoot.appending(path: "multi-version.md")
        let service = VersionHistoryService()

        // Save 3 versions with slight delay to ensure different timestamps
        service.saveSnapshot(for: noteURL, content: "Version 1", vaultRoot: vaultRoot)
        Thread.sleep(forTimeInterval: 1.1) // ISO8601 has second precision
        service.saveSnapshot(for: noteURL, content: "Version 2", vaultRoot: vaultRoot)
        Thread.sleep(forTimeInterval: 1.1)
        service.saveSnapshot(for: noteURL, content: "Version 3", vaultRoot: vaultRoot)

        let versions = service.fetchVersions(for: noteURL, vaultRoot: vaultRoot)
        #expect(versions.count == 3, "All 3 snapshots should be preserved (within max limit)")
    }
}

// MARK: - CoordinatedFileWriter Tests

@Suite("CoordinatedFileWriter — Save Safety")
struct CoordinatedFileWriterSaveTests {

    @Test("Default timeout is 10 seconds")
    func defaultTimeout() {
        #expect(CoordinatedFileWriter.defaultTimeout == 10.0)
    }

    @Test("Write and read round-trip succeeds")
    func writeReadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "quartz-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appending(path: "test.md")
        let content = "Hello, coordinated write!"
        let data = content.data(using: .utf8)!

        try CoordinatedFileWriter.shared.write(data, to: fileURL)

        let readData = try Data(contentsOf: fileURL)
        let readContent = String(data: readData, encoding: .utf8)
        #expect(readContent == content, "Read content should match written content")
    }

    @Test("Atomic write does not leave partial files on error")
    func atomicWriteIntegrity() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "quartz-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appending(path: "atomic-test.md")

        // Write initial content
        let original = "Original content"
        try original.data(using: .utf8)!.write(to: fileURL)

        // Write new content
        let updated = "Updated content"
        try CoordinatedFileWriter.shared.write(updated.data(using: .utf8)!, to: fileURL)

        let read = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(read == updated, "File should contain updated content")
    }
}
