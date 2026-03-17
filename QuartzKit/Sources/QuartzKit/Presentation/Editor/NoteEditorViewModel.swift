import SwiftUI

/// ViewModel für den Plaintext-Editor.
///
/// Lädt Notiz-Inhalt, tracked Änderungen und speichert
/// automatisch nach 2 Sekunden Inaktivität.
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

    private let vaultProvider: any VaultProviding
    private let frontmatterParser: any FrontmatterParsing
    private var autosaveTask: Task<Void, Never>?

    /// Autosave-Verzögerung in Sekunden.
    private let autosaveDelay: Duration = .seconds(2)

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
    }

    /// Lädt eine Notiz vom Dateisystem.
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

    /// Speichert die aktuelle Notiz sofort.
    public func save() async {
        guard var currentNote = note, isDirty, !isSaving else { return }

        isSaving = true
        currentNote.body = content
        currentNote.frontmatter.modifiedAt = .now

        do {
            try await vaultProvider.saveNote(currentNote)
            note = currentNote
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "An unexpected error occurred.", bundle: .module)
            // Retry autosave after failure to prevent data loss
            scheduleAutosave()
        }

        isSaving = false
    }

    /// Explicit save triggered by user action (Cmd+S, toolbar button).
    /// Triggers haptic feedback on completion unlike autosave.
    public func manualSave() async {
        await save()
        if errorMessage == nil {
            manualSaveCompleted.toggle()
        }
    }

    /// Aktualisiert das Frontmatter und markiert die Notiz als dirty.
    public func updateFrontmatter(_ newFrontmatter: Frontmatter) {
        note?.frontmatter = newFrontmatter
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

    /// Plant Autosave nach Inaktivität.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.note != nil else { return }
            await self.save()
        }
    }

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
