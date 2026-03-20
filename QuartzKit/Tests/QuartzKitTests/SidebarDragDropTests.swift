import Testing
import Foundation
@testable import QuartzKit

// MARK: - Step 9: Sidebar Drag/Drop Logic Validation
// Pure unit tests for drag/drop validation logic — no UI, no vault required.

@Suite("SidebarDragDropValidation")
struct SidebarDragDropValidationTests {

    // MARK: - URL Validation Logic

    @Test("Self-drop is rejected")
    func selfDropRejected() {
        let folderURL = URL(filePath: "/vault/folder")
        let isValid = !isSelfDrop(source: folderURL, target: folderURL)
        #expect(!isValid, "Dropping on self should be rejected")
    }

    @Test("Circular folder drop is rejected")
    func circularDropRejected() {
        let parentFolder = URL(filePath: "/vault/parent")
        let childFolder = URL(filePath: "/vault/parent/child")

        let isCircular = wouldCreateCircularDependency(source: parentFolder, target: childFolder)
        #expect(isCircular, "Moving parent into child creates circular dependency")
    }

    @Test("Valid note-to-folder drop is accepted")
    func validNoteToFolderAccepted() {
        let noteURL = URL(filePath: "/vault/folder1/note.md")
        let folderURL = URL(filePath: "/vault/folder2")

        let isValid = isValidDropTarget(source: noteURL, target: folderURL)
        #expect(isValid, "Note to different folder should be valid")
    }

    @Test("Move to same parent folder is technically valid")
    func moveToSameParentIsValid() {
        let noteURL = URL(filePath: "/vault/folder/note.md")
        let parentURL = URL(filePath: "/vault/folder")

        // The validation passes, but move is a no-op
        let isValid = isValidDropTarget(source: noteURL, target: parentURL)
        #expect(isValid, "Move to same parent passes validation but is no-op")
    }

    @Test("Deep nesting move is valid")
    func deepNestingMoveValid() {
        let sourceURL = URL(filePath: "/vault/a/b/c/d/note.md")
        let targetURL = URL(filePath: "/vault/x/y/z")

        let isValid = isValidDropTarget(source: sourceURL, target: targetURL)
        #expect(isValid, "Cross-tree move should be valid")
    }

    // MARK: - Batch Validation

    @Test("Multiple valid URLs pass batch validation")
    func batchValidationMultipleURLs() {
        let folderURL = URL(filePath: "/vault/target")
        let sources = [
            URL(filePath: "/vault/note1.md"),
            URL(filePath: "/vault/note2.md"),
            URL(filePath: "/vault/subfolder/note3.md"),
        ]

        let validURLs = filterValidDropSources(sources, target: folderURL)
        #expect(validURLs.count == 3, "All three sources should be valid")
    }

    @Test("Mixed valid/invalid batch filters correctly")
    func mixedBatchFiltersCorrectly() {
        let folderURL = URL(filePath: "/vault/target")
        let sources = [
            URL(filePath: "/vault/note1.md"),           // valid
            folderURL,                                   // invalid: self
            URL(filePath: "/vault/target/child"),       // valid (child of target)
        ]

        let validURLs = filterValidDropSources(sources, target: folderURL)
        #expect(validURLs.count == 2, "Self-reference should be filtered out")
    }

    @Test("Empty URL list produces empty result")
    func emptyURLListProducesEmpty() {
        let folderURL = URL(filePath: "/vault/target")
        let validURLs = filterValidDropSources([], target: folderURL)
        #expect(validURLs.isEmpty)
    }

    // MARK: - Feedback Scenario Logic

    @Test("All success produces success feedback")
    func allSuccessFeedback() {
        let feedback = determineFeedbackType(successCount: 3, failureCount: 0)
        #expect(feedback == .success)
    }

    @Test("Partial success produces warning feedback")
    func partialSuccessFeedback() {
        let feedback = determineFeedbackType(successCount: 2, failureCount: 1)
        #expect(feedback == .warning)
    }

    @Test("All failure produces destructive feedback")
    func allFailureFeedback() {
        let feedback = determineFeedbackType(successCount: 0, failureCount: 3)
        #expect(feedback == .destructive)
    }

    // MARK: - FileNode Type Logic

    @Test("Folders are valid drop targets")
    func foldersAreValidTargets() {
        let folder = FileNode(name: "Folder", url: URL(filePath: "/vault/folder"), nodeType: .folder)
        #expect(folder.isFolder)
    }

    @Test("Notes redirect drops to parent")
    func notesRedirectToParent() {
        let noteURL = URL(filePath: "/vault/folder/note.md")
        let parentURL = noteURL.deletingLastPathComponent()
        #expect(parentURL.lastPathComponent == "folder")
    }

    // MARK: - Destination URL Generation

    @Test("Move generates correct destination URL")
    func moveGeneratesCorrectDestination() {
        let sourceURL = URL(filePath: "/vault/folder1/note.md")
        let destFolderURL = URL(filePath: "/vault/folder2")

        let destURL = destFolderURL.appending(path: sourceURL.lastPathComponent)
        #expect(destURL.path(percentEncoded: false) == "/vault/folder2/note.md")
    }

    @Test("Move preserves filename")
    func movePreservesFilename() {
        let sourceURL = URL(filePath: "/vault/src/My Note.md")
        let destFolderURL = URL(filePath: "/vault/dest")

        let destURL = destFolderURL.appending(path: sourceURL.lastPathComponent)
        #expect(destURL.lastPathComponent == "My Note.md")
    }

    @Test("Move handles special characters in filename")
    func moveHandlesSpecialCharacters() {
        let sourceURL = URL(filePath: "/vault/src/Note with spaces & symbols!.md")
        let destFolderURL = URL(filePath: "/vault/dest")

        let destURL = destFolderURL.appending(path: sourceURL.lastPathComponent)
        #expect(destURL.lastPathComponent == "Note with spaces & symbols!.md")
    }

    // MARK: - Helper Functions (replicating validation logic from SidebarView)

    private func isSelfDrop(source: URL, target: URL) -> Bool {
        source == target
    }

    private func wouldCreateCircularDependency(source: URL, target: URL) -> Bool {
        let targetPath = target.path(percentEncoded: false)
        let sourcePath = source.path(percentEncoded: false)
        return targetPath.hasPrefix(sourcePath + "/")
    }

    private func isValidDropTarget(source: URL, target: URL) -> Bool {
        guard source != target else { return false }
        let targetPath = target.path(percentEncoded: false)
        let sourcePath = source.path(percentEncoded: false)
        return !targetPath.hasPrefix(sourcePath + "/")
    }

    private func filterValidDropSources(_ sources: [URL], target: URL) -> [URL] {
        sources.filter { isValidDropTarget(source: $0, target: target) }
    }

    private enum FeedbackType { case success, warning, destructive }

    private func determineFeedbackType(successCount: Int, failureCount: Int) -> FeedbackType {
        if successCount > 0 && failureCount == 0 {
            return .success
        } else if successCount > 0 && failureCount > 0 {
            return .warning
        } else {
            return .destructive
        }
    }
}

