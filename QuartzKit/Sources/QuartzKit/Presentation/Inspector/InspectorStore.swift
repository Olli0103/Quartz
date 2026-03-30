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

    /// ID of the heading currently visible at the top of the editor viewport.
    /// Drives the highlight in the ToC.
    public var activeHeadingID: String?

    /// Whether the inspector panel is visible.
    public var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.visibilityKey)
        }
    }

    private static let visibilityKey = "quartz.inspectorVisible"

    // MARK: - Init

    public init() {
        self.isVisible = UserDefaults.standard.object(forKey: Self.visibilityKey) != nil
            ? UserDefaults.standard.bool(forKey: Self.visibilityKey)
            : true // Default to visible on first launch
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
