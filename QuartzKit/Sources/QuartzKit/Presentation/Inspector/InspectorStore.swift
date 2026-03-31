import SwiftUI

/// Drives the inspector panel UI.
///
/// Receives `NoteAnalysis` from the `MarkdownAnalysisService` and provides
/// headings, stats, and active-heading tracking to `InspectorSidebar`.
///
/// Owned by `EditorSession` (one per open note).
@Observable
@MainActor
public final class InspectorStore {

    // MARK: - Published State

    /// Parsed headings for the Table of Contents.
    public private(set) var headings: [HeadingItem] = []

    /// Document statistics (word count, char count, reading time).
    public private(set) var stats: NoteStats = .empty

    /// Semantically related notes discovered by background AI analysis.
    /// Each entry is a (URL, display title) pair for rendering in the inspector.
    public var relatedNotes: [(url: URL, title: String)] = []

    /// Unlinked mention suggestions from LinkSuggestionService.
    /// Updated by EditorSession's debounced analysis pass.
    public var suggestedLinks: [LinkSuggestionService.Suggestion] = []

    /// AI-extracted concepts for the current note (from KnowledgeExtractionService).
    public var aiConcepts: [String] = []

    /// AI vault scan progress — shown as a subtle status line in the inspector.
    /// nil when no scan is running.
    public var aiScanProgress: (current: Int, total: Int, note: String)?

    /// ID of the heading currently visible at the top of the editor viewport.
    /// Drives the highlight in the ToC.
    public var activeHeadingID: String?

    /// Whether the inspector panel is visible.
    public var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.visibilityKey)
        }
    }

    /// Whether the version history sheet is presented.
    public var showVersionHistory: Bool = false

    private static let visibilityKey = "quartz.inspectorVisible"

    // MARK: - Init

    public init() {
        if UserDefaults.standard.object(forKey: Self.visibilityKey) != nil {
            self.isVisible = UserDefaults.standard.bool(forKey: Self.visibilityKey)
        } else {
            // Default: visible on macOS (side panel), hidden on iOS (would pop up as sheet)
            #if os(macOS)
            self.isVisible = true
            #else
            self.isVisible = false
            #endif
        }
    }

    // MARK: - Update

    /// Called when the analysis service produces new results.
    /// Only mutates if data actually changed, avoiding unnecessary SwiftUI diffs.
    public func update(with analysis: NoteAnalysis) {
        if headings.map(\.id) != analysis.headings.map(\.id) {
            headings = analysis.headings
        }
        if stats != analysis.stats {
            stats = analysis.stats
        }
    }

    /// Updates the active heading based on the editor's visible character offset.
    /// Called by `EditorSession.viewportDidScroll`.
    public func updateActiveHeading(forCharacterOffset offset: Int) {
        let heading = headings.last { $0.characterOffset <= offset }
        let newID = heading?.id
        if activeHeadingID != newID {
            activeHeadingID = newID
        }
    }
}
