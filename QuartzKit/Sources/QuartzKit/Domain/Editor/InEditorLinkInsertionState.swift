import Foundation
import Observation

/// Editor-local state for wiki-link note insertion triggered by typing `[[`.
///
/// The query lives in the markdown buffer itself. This state only tracks the
/// currently active trigger range and the suggestion list for the mounted editor.
@Observable
@MainActor
public final class InEditorLinkInsertionState {
    public struct Suggestion: Identifiable, Equatable, Sendable {
        public let noteURL: URL
        public let noteName: String
        public let insertableTarget: String

        public var id: URL { noteURL }

        public init(noteURL: URL, noteName: String, insertableTarget: String) {
            self.noteURL = noteURL
            self.noteName = noteName
            self.insertableTarget = insertableTarget
        }
    }

    public var isPresented: Bool = false
    public var query: String = ""
    public private(set) var triggerRange: NSRange?
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var selectedIndex: Int = 0
    public private(set) var shouldRestoreEditorFocusOnDismiss: Bool = false

    public init() {}

    public var selectedSuggestion: Suggestion? {
        guard suggestions.indices.contains(selectedIndex) else { return nil }
        return suggestions[selectedIndex]
    }

    public func presentOrUpdate(
        triggerRange: NSRange,
        query: String,
        suggestions: [Suggestion],
        shouldRestoreEditorFocusOnDismiss: Bool
    ) {
        let previousSelection = selectedSuggestion
        isPresented = true
        self.triggerRange = triggerRange
        self.query = query
        self.suggestions = suggestions
        self.shouldRestoreEditorFocusOnDismiss = shouldRestoreEditorFocusOnDismiss

        if let previousSelection,
           let previousIndex = suggestions.firstIndex(of: previousSelection) {
            selectedIndex = previousIndex
        } else {
            selectedIndex = suggestions.isEmpty ? 0 : min(selectedIndex, suggestions.count - 1)
        }
    }

    public func moveSelection(delta: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + suggestions.count) % suggestions.count
    }

    public func dismiss() {
        isPresented = false
        query = ""
        triggerRange = nil
        suggestions = []
        selectedIndex = 0
        shouldRestoreEditorFocusOnDismiss = false
    }
}
