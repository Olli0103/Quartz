import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    /// Set when an external modification is detected while the user has unsaved edits.
    /// The view should prompt: reload (discard local) or keep editing (save overwrites).
    public var externalModificationDetected: Bool = false

    /// Set by the app shell when a widget / Control Center requests the document scanner.
    public var requestDocumentScannerPresentation: Bool = false

    private let vaultProvider: any VaultProviding
    private let frontmatterParser: any FrontmatterParsing
    private var autosaveTask: Task<Void, Never>?
    private var fileWatchTask: Task<Void, Never>?

    private let autosaveDelay: Duration = .seconds(1)

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
    }

    /// Loads a note from the file system.
    public func loadNote(at url: URL) async {
        stopFileWatching()
        do {
            let loaded = try await vaultProvider.readNote(at: url)
            note = loaded
            content = loaded.body
            isDirty = false
            errorMessage = nil
            externalModificationDetected = false
            startFileWatching(for: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "An unexpected error occurred.", bundle: .module)
        }
    }

    /// Reloads from disk, discarding local edits. Call when user chooses "Reload" after external modification.
    public func reloadFromDisk() async {
        guard let url = note?.fileURL else { return }
        externalModificationDetected = false
        await loadNote(at: url)
    }

    /// Clears the external modification flag. Call when user chooses to keep editing (save will overwrite).
    public func dismissExternalModificationWarning() {
        externalModificationDetected = false
    }

    /// Snapshot of the note body on disk (for merge UI). Does not mutate editor state.
    public func diskBodySnapshot() async -> String? {
        guard let url = note?.fileURL else { return nil }
        guard let doc = try? await vaultProvider.readNote(at: url) else { return nil }
        return doc.body
    }

    /// Applies merged text from the conflict sheet, saves, and clears the external-edit flag.
    public func applyMergedContentResolvingExternalEdit(_ merged: String) async {
        content = merged
        externalModificationDetected = false
        await save(force: true)
    }

    /// Saves the current note immediately.
    /// - Parameter force: When true, writes even if not dirty (e.g. explicit user save).
    public func save(force: Bool = false) async {
        guard var currentNote = note, (isDirty || force), !isSaving else { return }

        isSaving = true
        // Snapshot content and cursor before async gap to prevent race condition:
        // user may type while save is in flight.
        let contentSnapshot = content
        let cursorSnapshot = cursorPosition
        currentNote.body = contentSnapshot
        currentNote.frontmatter.modifiedAt = .now

        do {
            let savedURL = currentNote.fileURL
            try await vaultProvider.saveNote(currentNote)
            note = currentNote
            // Only clear dirty flag if content hasn't changed since snapshot
            if content == contentSnapshot {
                isDirty = false
                // Restore cursor position if it was displaced during save
                if cursorPosition != cursorSnapshot && content == contentSnapshot {
                    cursorPosition = cursorSnapshot
                }
            }
            errorMessage = nil
            NotificationCenter.default.post(name: .quartzNoteSaved, object: savedURL)
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

    #if canImport(UIKit)
    /// Imports a UIImage (e.g. from camera) into the vault and inserts the Markdown link.
    public func importImage(_ image: UIImage) async {
        guard let note, let vaultRoot = vaultRootURL else {
            errorMessage = String(localized: "No active note or vault.", bundle: .module)
            return
        }
        let assetManager = AssetManager()
        do {
            let markdownLink = try await assetManager.importImage(
                image,
                vaultRoot: vaultRoot,
                noteURL: note.fileURL
            )
            insertTextAtCursor("\n" + markdownLink + "\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    // MARK: - File Watching (External Modification Detection)

    private func startFileWatching(for url: URL) {
        stopFileWatching()
        let watcher = FileWatcher(url: url)
        fileWatchTask = Task { [weak self] in
            let stream = await watcher.startWatching()
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .modified(let changedURL):
                    guard changedURL == self.note?.fileURL else { continue }
                    await MainActor.run {
                        if self.isDirty {
                            self.externalModificationDetected = true
                        } else {
                            Task { await self.loadNote(at: changedURL) }
                        }
                    }
                case .deleted:
                    await MainActor.run {
                        self.errorMessage = String(localized: "Note was deleted externally.", bundle: .module)
                        self.stopFileWatching()
                    }
                case .created:
                    break
                }
            }
        }
    }

    private func stopFileWatching() {
        fileWatchTask?.cancel()
        fileWatchTask = nil
    }

    // MARK: - Task Management

    public func cancelAllTasks() {
        autosaveTask?.cancel()
        autosaveTask = nil
        wordCountTask?.cancel()
        wordCountTask = nil
        stopFileWatching()
    }

    // MARK: - PDF Export

    /// Generates PDF data for the given title and body.
    /// Moved out of the view layer for separation of concerns.
    public func generatePDFData(title: String, body: String) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 54
        let contentWidth = pageSize.width - 2 * margin
        let contentHeight = pageSize.height - 2 * margin

        #if os(macOS)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        #else
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.black,
        ]
        #endif

        let fullText = NSMutableAttributedString()
        fullText.append(NSAttributedString(string: title + "\n\n", attributes: titleAttributes))
        fullText.append(NSAttributedString(string: body, attributes: bodyAttributes))

        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(fullText as CFAttributedString)
        var currentIndex = 0

        while currentIndex < fullText.length {
            ctx.beginPage(mediaBox: &mediaBox)

            let frameRect = CGRect(x: margin, y: margin, width: contentWidth, height: contentHeight)
            let framePath = CGPath(rect: frameRect, transform: nil)
            let ctFrame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: currentIndex, length: 0), framePath, nil
            )

            CTFrameDraw(ctFrame, ctx)

            let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
            if visibleRange.length == 0 { break }
            currentIndex += visibleRange.length

            ctx.endPage()
        }

        ctx.closePDF()
        return mutableData as Data
    }

    // MARK: - Link Suggestions

    /// Computes link suggestions on a background thread to avoid blocking the main actor.
    /// Use when opening the link suggestion sheet or after applying a suggestion.
    public func computeLinkSuggestions() async -> [LinkSuggestionService.Suggestion] {
        guard let note else { return [] }
        let contentSnapshot = content
        let currentNoteURL = note.fileURL
        let fileTreeSnapshot = fileTree

        return await Task.detached(priority: .userInitiated) {
            let service = LinkSuggestionService()
            return service.suggestLinks(
                for: contentSnapshot,
                currentNoteURL: currentNoteURL,
                allNotes: fileTreeSnapshot
            )
        }.value
    }

    // NOTE: No deinit – Task cancellation is handled by cancelAllTasks()
    // called from the view layer (ContentView.openNote). deinit on a
    // @MainActor class is nonisolated in Swift 6, so accessing actor-
    // isolated stored properties here would be a data race.
}
