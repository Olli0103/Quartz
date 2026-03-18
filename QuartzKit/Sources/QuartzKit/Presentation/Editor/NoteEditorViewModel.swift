import SwiftUI

/// ViewModel for the plaintext editor.
///
/// Loads note content, tracks changes and saves
/// automatically after 2 seconds of inactivity.
@Observable
@MainActor
public final class NoteEditorViewModel {
    public var content: String = "" {
        didSet {
            guard content != oldValue else { return }
            isDirty = true
            scheduleWordCountUpdate()
            scheduleAutosave()
        }
    }

    public var isDirty: Bool = false
    public var isSaving: Bool = false
    public var errorMessage: String?

    /// Toggled only on explicit manual save (Cmd+S / button tap).
    /// Used to trigger haptic feedback — autosave should not vibrate.
    public var manualSaveCompleted: Bool = false

    /// Cached word count, updated on content change.
    public private(set) var wordCount: Int = 0

    /// Current cursor position in the editor.
    public var cursorPosition: NSRange = NSRange(location: 0, length: 0)

    public private(set) var note: NoteDocument?

    /// Root URL of the current vault, used for backlink scanning.
    public var vaultRootURL: URL?

    /// File tree snapshot for link suggestion.
    public var fileTree: [FileNode] = []

    private let vaultProvider: any VaultProviding
    private let frontmatterParser: any FrontmatterParsing
    private var autosaveTask: Task<Void, Never>?

    private let autosaveDelay: Duration = .seconds(1)

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
    }

    /// Loads a note from the file system.
    public func loadNote(at url: URL) async {
        do {
            let loaded = try await vaultProvider.readNote(at: url)
            note = loaded
            content = loaded.body
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "An unexpected error occurred.", bundle: .module)
        }
    }

    /// Saves the current note immediately.
    /// - Parameter force: When true, writes even if not dirty (e.g. explicit user save).
    public func save(force: Bool = false) async {
        guard var currentNote = note, (isDirty || force), !isSaving else { return }

        isSaving = true
        // Snapshot content before async gap to prevent race condition:
        // user may type while save is in flight.
        let contentSnapshot = content
        currentNote.body = contentSnapshot
        currentNote.frontmatter.modifiedAt = .now

        do {
            try await vaultProvider.saveNote(currentNote)
            note = currentNote
            // Only clear dirty flag if content hasn't changed since snapshot
            if content == contentSnapshot {
                isDirty = false
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            scheduleAutosave()
        }

        isSaving = false
    }

    /// Explicit save triggered by user action (Cmd+S, toolbar button).
    /// Triggers haptic feedback on completion unlike autosave.
    /// Forces a write even when not dirty so the user always gets feedback.
    public func manualSave() async {
        await save(force: true)
        if note != nil, errorMessage == nil {
            manualSaveCompleted.toggle()
        }
    }

    /// Updates the frontmatter and marks the note as dirty.
    public func updateFrontmatter(_ newFrontmatter: Frontmatter) {
        note?.frontmatter = newFrontmatter
        isDirty = true
        scheduleAutosave()
    }

    /// Renames the note by updating the frontmatter title.
    public func renameNote(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        note?.frontmatter.title = trimmed
        isDirty = true
        scheduleAutosave()
    }

    private var wordCountTask: Task<Void, Never>?

    private func scheduleWordCountUpdate() {
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let text = self.content
            // O(1) memory word count via enumerateSubstrings (Unicode-correct)
            let count = await Task.detached(priority: .utility) {
                var wordCount = 0
                text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { _, _, _, _ in
                    wordCount += 1
                }
                return wordCount
            }.value
            guard !Task.isCancelled else { return }
            self.wordCount = count
        }
    }

    /// Schedules autosave after inactivity.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.note != nil else { return }
            await self.save()
        }
    }

    // MARK: - Image Import

    /// Inserts text at the current cursor position, replacing any selection.
    public func insertTextAtCursor(_ text: String) {
        let nsContent = content as NSString
        let location = min(cursorPosition.location, nsContent.length)
        let length = min(cursorPosition.length, nsContent.length - location)
        let range = NSRange(location: location, length: length)
        content = nsContent.replacingCharacters(in: range, with: text)
        cursorPosition = NSRange(location: location + text.count, length: 0)
    }

    /// Imports an image from a file URL into the vault's assets folder
    /// and inserts the resulting Markdown link at the cursor.
    public func importImage(from sourceURL: URL) async {
        guard let note, let vaultRoot = vaultRootURL else {
            errorMessage = String(localized: "No active note or vault.", bundle: .module)
            return
        }
        let assetManager = AssetManager()
        do {
            let markdownLink = try await assetManager.importImage(
                from: sourceURL,
                vaultRoot: vaultRoot,
                noteURL: note.fileURL
            )
            insertTextAtCursor("\n" + markdownLink + "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Task Management

    public func cancelAllTasks() {
        autosaveTask?.cancel()
        autosaveTask = nil
        wordCountTask?.cancel()
        wordCountTask = nil
    }

    // NOTE: No deinit – Task cancellation is handled by cancelAllTasks()
    // called from the view layer (ContentView.openNote). deinit on a
    // @MainActor class is nonisolated in Swift 6, so accessing actor-
    // isolated stored properties here would be a data race.
}
