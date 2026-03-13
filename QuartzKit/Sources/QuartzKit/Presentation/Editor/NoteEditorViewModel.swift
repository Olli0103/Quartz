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
            scheduleAutosave()
        }
    }

    public var isDirty: Bool = false
    public var isSaving: Bool = false
    public var errorMessage: String?

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
            errorMessage = error.localizedDescription
        }
    }

    /// Speichert die aktuelle Notiz sofort.
    public func save() async {
        guard var currentNote = note, isDirty else { return }

        isSaving = true
        currentNote.body = content
        currentNote.frontmatter.modifiedAt = .now

        do {
            try await vaultProvider.saveNote(currentNote)
            note = currentNote
            isDirty = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    /// Aktualisiert das Frontmatter und markiert die Notiz als dirty.
    public func updateFrontmatter(_ newFrontmatter: Frontmatter) {
        note?.frontmatter = newFrontmatter
        isDirty = true
        scheduleAutosave()
    }

    /// Plant Autosave nach Inaktivität.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autosaveDelay ?? .seconds(2))
            guard !Task.isCancelled, let self, self.note != nil else { return }
            await self.save()
        }
    }

    deinit {
        autosaveTask?.cancel()
    }
}
