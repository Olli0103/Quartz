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
    public struct OutgoingLinkItem: Identifiable, Sendable, Equatable {
        public let noteURL: URL
        public let noteName: String
        public let displayText: String
        public let context: String
        public let headingFragment: String?
        public let referenceRange: NSRange?

        public var id: URL { noteURL }

        public init(
            noteURL: URL,
            noteName: String,
            displayText: String,
            context: String,
            headingFragment: String? = nil,
            referenceRange: NSRange? = nil
        ) {
            self.noteURL = noteURL
            self.noteName = noteName
            self.displayText = displayText
            self.context = context
            self.headingFragment = headingFragment
            self.referenceRange = referenceRange
        }

        public init(reference: ExplicitNoteReference) {
            self.init(
                noteURL: reference.targetNoteURL,
                noteName: reference.targetNoteName,
                displayText: reference.displayText,
                context: reference.context,
                headingFragment: reference.headingFragment,
                referenceRange: reference.matchRange
            )
        }
    }

    // MARK: - Published State

    /// Parsed headings for the Table of Contents.
    public private(set) var headings: [HeadingItem] = []

    /// Document statistics (word count, char count, reading time).
    public private(set) var stats: NoteStats = .empty

    /// Embedding-based related notes discovered by background analysis.
    /// This is separate from explicit links/backlinks and separate from AI concepts.
    /// Each entry is a (URL, display title) pair for rendering in the inspector.
    public var relatedNotes: [(url: URL, title: String)] = []

    /// Unlinked mention suggestions from LinkSuggestionService.
    /// Updated by EditorSession's debounced analysis pass.
    public var suggestedLinks: [LinkSuggestionService.Suggestion] = []

    /// Explicit wiki-link targets for the current note.
    /// Updated from the editor's authoritative current-note reference model.
    public var outgoingLinks: [OutgoingLinkItem] = []

    /// AI-extracted concepts for the current note (from KnowledgeExtractionService).
    /// These are note annotations, not note-to-note links.
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

    // MARK: - Intelligence Engine Status

    /// Current Intelligence Engine status — drives the status indicator in the inspector.
    public var intelligenceStatus: IntelligenceEngineStatus = .idle

    /// Stored notification token removed during teardown.
    /// Swift 6 runs `deinit` nonisolated, and removing NotificationCenter observers is
    /// safe without forcing a MainActor precondition.
    nonisolated(unsafe) private var statusObserver: Any?

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

        startStatusObserver()
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Observes Intelligence Engine status changes for UI updates.
    private func startStatusObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .quartzIntelligenceEngineStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let status = notification.userInfo?["status"] as? IntelligenceEngineStatus else { return }
            Task { @MainActor [weak self] in
                self?.intelligenceStatus = status
            }
        }
    }

    // MARK: - Update

    /// Called when the analysis service produces new results.
    /// Only mutates if data actually changed, avoiding unnecessary SwiftUI diffs.
    public func update(with analysis: NoteAnalysis) {
        setHeadings(analysis.headings)
        updateStats(analysis.stats)
    }

    /// Updates the inspector headings from the editor's authoritative semantic model.
    /// This keeps ToC navigation aligned with the exact block ranges used for rendering.
    public func setHeadings(_ headings: [HeadingItem]) {
        if self.headings.map(\.id) != headings.map(\.id) {
            self.headings = headings
        }

        if let activeHeadingID, headings.contains(where: { $0.id == activeHeadingID }) == false {
            self.activeHeadingID = nil
        }
    }

    /// Updates document statistics without mutating heading/navigation state.
    public func updateStats(_ stats: NoteStats) {
        if self.stats != stats {
            self.stats = stats
        }
    }

    public func setOutgoingLinks(_ outgoingLinks: [OutgoingLinkItem]) {
        if self.outgoingLinks != outgoingLinks {
            self.outgoingLinks = outgoingLinks
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
