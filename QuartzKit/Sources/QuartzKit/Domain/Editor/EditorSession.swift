import SwiftUI
import CryptoKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Authoritative editor state for a single open note.
///
/// **The native text view is the source of truth for text content.**
/// SwiftUI never writes to it after the initial load. External mutations
/// (iCloud merge, AI insertion, list continuation) go through
/// `applyExternalEdit(replacement:range:)` which uses
/// `NSTextStorage.replaceCharacters` for proper undo registration
/// and minimal layout invalidation.
///
/// This breaks the destructive `@Binding var text` → `updateUIView` →
/// `textView.text = text` feedback cycle that caused cursor jitter.
///
/// **Ref:** Master Plan §2.4 — EditorSession actor/object per open note.
@Observable
@MainActor
public final class EditorSession {
    public enum FormattingInvocationSource: String, Sendable {
        case toolbar
        case hardwareKeyboard
        case commandMenu
    }

    /// Captures the user-visible note-open path so startup stays measurable while
    /// non-critical enrichment work is deferred behind first editability.
    public struct EditorLoadMetrics: Sendable, Equatable {
        public let noteURL: URL
        public let bodyLength: Int
        public let readSeconds: Double
        public let applyStateSeconds: Double
        public let totalVisibleSeconds: Double
    }

    // MARK: - State (read by UI, never written back by SwiftUI)

    /// The note currently loaded in this session.
    public private(set) var note: NoteDocument?

    /// Current text content — READ-ONLY snapshot for consumers (autosave, word count).
    /// Updated only by delegate callbacks, never by SwiftUI bindings.
    public private(set) var currentText: String = ""

    /// Last authoritative cursor/selection snapshot.
    ///
    /// Runtime ownership is explicit:
    /// - while the mounted native text view is first responder, its live selection is authoritative
    /// - otherwise this snapshot is the derived fallback used by formatting, restoration, and state persistence
    ///
    /// SwiftUI never writes this back directly.
    public private(set) var cursorPosition: NSRange = .init(location: 0, length: 0)

    /// Current scroll offset — updated by delegate callbacks.
    /// Used to restore scroll position after inspector toggle or layout changes.
    public private(set) var scrollOffset: CGPoint = .zero

    /// Dirty flag — true if text differs from last save.
    public private(set) var isDirty: Bool = false

    /// Saving flag for UI indicators.
    public private(set) var isSaving: Bool = false

    /// Error message for the UI.
    public var errorMessage: String?

    /// Cached word count, updated on content change.
    public private(set) var wordCount: Int = 0

    /// Most recent note-open timing captured for diagnostics and tests.
    public private(set) var lastLoadMetrics: EditorLoadMetrics?

    /// Current formatting state at the cursor position (for toolbar active states).
    public private(set) var formattingState: FormattingState = .empty

    /// Editor-scoped find/replace state for the currently active note only.
    /// This never participates in vault-wide search.
    public let inNoteSearch = InNoteSearchState()

    /// Editor-scoped wiki-link insertion state for the currently active note only.
    /// Typing `[[` opens note suggestions without leaving the active editor.
    public let linkInsertion = InEditorLinkInsertionState()

    /// Root URL of the current vault.
    public var vaultRootURL: URL?

    /// File tree snapshot for link suggestions.
    ///
    /// This must track the sidebar's authoritative note catalog, including late
    /// async tree loads after the editor is already mounted. If the wiki-link
    /// picker is open while the tree arrives, refresh suggestions immediately so
    /// shell/UI flows do not show an empty picker for a valid `[[` trigger.
    public var fileTree: [FileNode] = [] {
        didSet {
            guard fileTree != oldValue else { return }
            refreshLinkInsertionSuggestionsForCurrentEditorState()
            guard note != nil else { return }
            scheduleAnalysis()
            scheduleExplicitRelationshipRefresh(forceGraphPublish: true)
        }
    }

    /// Last published canonical explicit-reference payload for the loaded note.
    /// Prevents redundant live graph invalidations while keeping explicit relationships coherent.
    private var lastPublishedExplicitReferences: [ExplicitNoteReference] = []

    /// Pending cross-note navigation request that should be applied when the target
    /// note becomes the loaded note in this session.
    private var pendingNoteNavigationRequest: WikiLinkNavigationRequest?

    /// Set when an external modification is detected while the user has unsaved edits.
    public var externalModificationDetected: Bool = false

    /// Canonical note identity for the pending external change, when local edits block auto-reload.
    /// This stays nil during clean auto-reloads.
    public private(set) var pendingExternalChangeIdentity: CanonicalNoteIdentity?

    /// The active mutation transaction, set during any text edit.
    /// Used by the undo system and incremental highlighter to determine policy.
    public private(set) var currentTransaction: MutationTransaction?

    /// Guard flag: true while `applyHighlightSpans` is modifying the text storage.
    /// Prevents `textDidChange` from re-triggering highlights during attachment insertion.
    public private(set) var isApplyingHighlights: Bool = false

    /// Guard flag: true while restoring a version from history.
    /// Prevents file watcher from showing spurious "modified externally" banner.
    public private(set) var isRestoringVersion: Bool = false

    /// Guard flag: true while we are saving. Prevents file watcher from reloading
    /// when it detects changes that we ourselves triggered.
    private var isSavingToFileSystem: Bool = false

    /// Set when another save/autosave request arrives while a write is in flight.
    /// The active save replays it after the write completes so edits made during
    /// slow file coordination are not left dirty without a follow-up save.
    private var savePendingAfterCurrentWrite: Bool = false

    /// Consecutive save failures. Drives retry backoff so iCloud coordination
    /// outages do not create a tight autosave loop that competes with recovery.
    public private(set) var consecutiveSaveFailures: Int = 0

    /// True when a save request that arrived during an active save should replay
    /// as an explicit save after the current write completes.
    private var forceSavePendingAfterCurrentWrite = false

    /// Guard flag: true while a programmatic edit is mutating the active text view.
    /// Prevents delegate callbacks from downgrading the mutation origin to `.userTyping`.
    private var isApplyingExternalEdit: Bool = false

    /// SHA-256 hash of the last content we wrote to disk.
    /// Used for content-based echo suppression (replaces timing-based guard).
    private var lastSavedContentHash: SHA256Digest?

    /// SHA-256 hash of the last disk revision successfully loaded or saved into this session.
    /// Used to ignore duplicate file-presenter/file-watcher events for the same on-disk content.
    private var lastKnownDiskContentHash: SHA256Digest?

    // MARK: - Restoration Readiness (F8 fix)

    /// True when the editor is ready for cursor/scroll restoration.
    /// Set after `loadNote` completes and text view is populated.
    /// **Per CODEX.md F8:** Replaces timing-based restoration with explicit handshake.
    public private(set) var isReadyForRestoration: Bool = false

    /// Continuations waiting for restoration readiness.
    /// Multiple callers can await readiness; all are resumed when ready.
    private var readinessContinuations: [CheckedContinuation<Void, Never>] = []

    /// True once the current note body has been loaded into session state.
    private var hasLoadedCurrentNoteForRestoration = false

    /// True while a native text view is mounted for this session.
    private var hasMountedNativeEditor = false

    /// Deferred cursor restoration applied once a mounted editor is available.
    private var pendingRestoredSelection: NSRange?

    /// Deferred scroll restoration applied once a mounted editor is available.
    private var pendingRestoredScrollOffset: CGPoint?

    /// Per-note transient editor state used when switching away and back within the same session.
    private var noteViewStateByURL: [URL: EditorViewState] = [:]

    // MARK: - Active Text View (weak ref)

    /// The native text view managed by the representable. Weak to avoid retain cycle.
    #if canImport(UIKit)
    public weak var activeTextView: UITextView?
    #elseif canImport(AppKit)
    public weak var activeTextView: NSTextView?
    #endif

    // MARK: - Dependencies

    private let vaultProvider: any VaultProviding
    private let frontmatterParser: any FrontmatterParsing
    /// Stored for deinit cleanup of long-lived editor work items.
    /// Swift 6 runs `deinit` nonisolated, and `Task.cancel()` is safe there.
    nonisolated(unsafe) private var autosaveTask: Task<Void, Never>?
    nonisolated(unsafe) private var fileWatchTask: Task<Void, Never>?
    nonisolated(unsafe) private var wordCountTask: Task<Void, Never>?
    nonisolated(unsafe) private var diskHashRefreshTask: Task<Void, Never>?
    nonisolated(unsafe) private var postLoadTask: Task<Void, Never>?

    // MARK: - NSFilePresenter Integration

    /// NSFilePresenter for iCloud-safe file change detection.
    /// Bridges coordinated file system events to the Intelligence Engine.
    private var filePresenter: NoteFilePresenter?

    // MARK: - Inspector Integration

    /// Background analysis service for headings + stats.
    private let analysisService = MarkdownAnalysisService()

    /// Inspector store — drives the right panel UI. Shared across note switches.
    public let inspectorStore: InspectorStore

    /// Stored for deinit cleanup of background analysis.
    nonisolated(unsafe) private var analysisTask: Task<Void, Never>?

    /// Stored for deinit cleanup of current-note explicit-link inspector refreshes.
    nonisolated(unsafe) private var referenceInspectorTask: Task<Void, Never>?

    /// Delay before running analysis (longer than highlighting since ToC doesn't need keystroke-level updates).
    private let analysisDelay: Duration = .milliseconds(300)

    private let autosaveDelay: Duration = .seconds(1)
    private static let saveRecoveryFallbackThreshold = 2
    nonisolated private static let maxEmergencyRecoveryCopies = 50
    private let pasteNormalizer = EditorPasteNormalizer()
    /// Formatting actions are explicit user commands, so they should pay the cost of
    /// a synchronous authoritative rehighlight for every note size that the editor
    /// still renders semantically. Only pathological documents beyond the highlighter's
    /// own semantic-render ceiling remain on the async fallback path.
    private static let synchronousFormattingHighlightThreshold = 500_000

    // MARK: - Version History Throttle

    /// Minimum interval between version snapshots (5 minutes).
    private static let versionSnapshotInterval: TimeInterval = 300

    /// Last time a version snapshot was saved for the current note.
    private var lastSnapshotDate: Date?

    // MARK: - Init

    /// Shared relationship store for explicit link edges, related-note similarity, and AI concepts.
    public var graphEdgeStore: GraphEdgeStore?

    /// Stored notification tokens removed during teardown.
    /// Stored notification tokens removed during teardown.
    /// Removing NotificationCenter observers is safe from nonisolated `deinit`.
    nonisolated(unsafe) private var semanticLinkObserver: Any?
    nonisolated(unsafe) private var conceptObserver: Any?
    nonisolated(unsafe) private var scanProgressObserver: Any?

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing, inspectorStore: InspectorStore) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
        self.inspectorStore = inspectorStore
        startSemanticLinkObserver()
        startConceptObserver()
        startScanProgressObserver()
    }

    deinit {
        autosaveTask?.cancel()
        highlightTask?.cancel()
        fileWatchTask?.cancel()
        wordCountTask?.cancel()
        analysisTask?.cancel()
        referenceInspectorTask?.cancel()
        inlineAITask?.cancel()
        diskHashRefreshTask?.cancel()
        postLoadTask?.cancel()

        if let observer = semanticLinkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = conceptObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = scanProgressObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Listens for related-note similarity updates and refreshes the inspector's Related Notes.
    private func startSemanticLinkObserver() {
        semanticLinkObserver = NotificationCenter.default.addObserver(
            forName: .quartzRelatedNotesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let updatedURL = notification.object as? URL
            let updatedVaultRoot = notification.userInfo?["vaultRootURL"] as? URL
            Task { @MainActor [weak self] in
                guard let self,
                      self.relationshipNotificationBelongsToCurrentVault(updatedVaultRoot) else { return }
                if let updatedURL {
                    guard updatedURL == self.note?.fileURL else { return }
                } else if self.note == nil {
                    return
                }
                await self.refreshRelatedNotes()
            }
        }
    }

    /// Listens for `.quartzConceptsUpdated` and refreshes the inspector's AI concepts.
    private func startConceptObserver() {
        conceptObserver = NotificationCenter.default.addObserver(
            forName: .quartzConceptsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let updatedURL = notification.object as? URL
            let updatedVaultRoot = notification.userInfo?["vaultRootURL"] as? URL
            Task { @MainActor [weak self] in
                guard let self,
                      self.relationshipNotificationBelongsToCurrentVault(updatedVaultRoot) else { return }
                if let updatedURL {
                    guard updatedURL == self.note?.fileURL else { return }
                } else if self.note == nil {
                    return
                }
                await self.refreshAIConcepts()
            }
        }
    }

    /// Listens for `.quartzConceptScanProgress` and updates the inspector's scan status.
    private func startScanProgressObserver() {
        scanProgressObserver = NotificationCenter.default.addObserver(
            forName: .quartzConceptScanProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let current = notification.userInfo?["current"] as? Int
            let total = notification.userInfo?["total"] as? Int
            let note = notification.userInfo?["note"] as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let current, let total, let note {
                    self.inspectorStore.aiScanProgress = (current: current, total: total, note: note)
                } else {
                    self.inspectorStore.aiScanProgress = nil
                }
            }
        }
    }

    /// Fetches note-to-note related-note similarity from the edge store and updates the inspector.
    public func refreshRelatedNotes() async {
        guard KnowledgeAnalysisSettings.relatedNotesSimilarityEnabled(),
              let noteURL = note?.fileURL,
              let edgeStore = graphEdgeStore else {
            inspectorStore.relatedNotes = []
            return
        }
        let related = await edgeStore.semanticRelations(for: noteURL)
        inspectorStore.relatedNotes = related.map { url in
            (url: url, title: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Fetches AI concepts from the edge store and updates the inspector.
    public func refreshAIConcepts() async {
        guard KnowledgeAnalysisSettings.aiConceptExtractionEnabled(),
              let noteURL = note?.fileURL,
              let edgeStore = graphEdgeStore else {
            inspectorStore.aiConcepts = []
            return
        }
        inspectorStore.aiConcepts = await edgeStore.concepts(for: noteURL)
    }

    private func relationshipNotificationBelongsToCurrentVault(_ updatedVaultRoot: URL?) -> Bool {
        guard let updatedVaultRoot else { return true }
        guard let vaultRootURL else { return false }
        return updatedVaultRoot.standardizedFileURL == vaultRootURL.standardizedFileURL
    }

    // MARK: - Note Loading

    private struct EditorViewState {
        let selection: NSRange
        let scrollOffset: CGPoint
    }

    /// Loads a note from the file system into the existing session.
    /// Reuses the mounted text view — no view destruction.
    public func loadNote(at url: URL) async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        // Reset readiness state for new note (F8 handshake)
        resetReadinessState()
        saveViewStateForCurrentNote()

        // CRITICAL: Save dirty content before switching notes to prevent data loss
        if isDirty, note != nil {
            await save(force: true)
        }

        // Save a snapshot of the previous note before switching
        if let previousNoteURL = note?.fileURL, let vaultRoot = vaultRootURL, !currentText.isEmpty {
            let content = currentText
            Task.detached(priority: .utility) {
                VersionHistoryService().saveSnapshot(for: previousNoteURL, content: content, vaultRoot: vaultRoot)
            }
        }

        cancelAllTasks()
        stopFileWatching()

        // Reset version history throttle for new note
        lastSnapshotDate = nil

        // Clear undo stack so previous note's history doesn't bleed through
        clearUndoStack()

        do {
            let readStart = CFAbsoluteTimeGetCurrent()
            let loaded = try await vaultProvider.readNote(at: canonicalURL)
            let readSeconds = CFAbsoluteTimeGetCurrent() - readStart
            let applyStart = CFAbsoluteTimeGetCurrent()
            applyLoadedNoteState(
                loaded,
                requestedURL: canonicalURL,
                restoredViewState: viewState(forLoadedNoteAt: canonicalURL),
                restartFileWatching: true,
                clearUndoHistory: true
            )
            let applyStateSeconds = CFAbsoluteTimeGetCurrent() - applyStart
            lastLoadMetrics = EditorLoadMetrics(
                noteURL: canonicalURL,
                bodyLength: (loaded.body as NSString).length,
                readSeconds: readSeconds,
                applyStateSeconds: applyStateSeconds,
                totalVisibleSeconds: CFAbsoluteTimeGetCurrent() - loadStart
            )
            hasLoadedCurrentNoteForRestoration = true
            updateRestorationReadinessIfPossible()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "An unexpected error occurred.", bundle: .module)
            // Still signal ready on error so waiters don't hang
            signalReadyForRestoration()
        }
    }

    /// Closes the current note without destroying the session.
    /// Clears text, note reference, undo stack, and editing state.
    /// The EditorContainerView stays mounted — it shows the empty state based on `note == nil`.
    public func closeNote() {
        // Reset readiness state (F8 handshake)
        resetReadinessState()
        saveViewStateForCurrentNote()

        // Save a final snapshot if there are unsaved changes
        if isDirty, let noteURL = note?.fileURL, let vaultRoot = vaultRootURL {
            let content = currentText
            Task.detached(priority: .utility) {
                VersionHistoryService().saveSnapshot(for: noteURL, content: content, vaultRoot: vaultRoot)
            }
        }

        cancelAllTasks()
        stopFileWatching()
        clearUndoStack()

        note = nil
        currentText = ""
        semanticDocument = .empty
        lastRenderPlan = .empty
        lastAppliedHighlightSpans = []
        lastAppliedHighlightSourceText = ""
        inspectorStore.setHeadings([])
        inspectorStore.updateStats(.empty)
        inspectorStore.suggestedLinks = []
        inspectorStore.setOutgoingLinks([])
        inspectorStore.activeHeadingID = nil
        isDirty = false
        errorMessage = nil
        externalModificationDetected = false
        pendingExternalChangeIdentity = nil
        wordCount = 0
        formattingState = .empty
        lastSavedContentHash = nil
        lastKnownDiskContentHash = nil
        lastPublishedExplicitReferences = []
        pendingNoteNavigationRequest = nil

        // Reset cursor and scroll state for clean restoration on next note open
        cursorPosition = NSRange(location: 0, length: 0)
        scrollOffset = .zero
        pendingRestoredSelection = nil
        pendingRestoredScrollOffset = nil
        inNoteSearch.dismiss()
        linkInsertion.dismiss()

        #if canImport(UIKit)
        activeTextView?.text = ""
        #elseif canImport(AppKit)
        activeTextView?.string = ""
        #endif

        clearUndoStack()
    }

    /// Wipes the native undo manager so histories don't bleed across notes.
    private func clearUndoStack() {
        #if canImport(UIKit)
        activeTextView?.undoManager?.removeAllActions()
        #elseif canImport(AppKit)
        activeTextView?.undoManager?.removeAllActions()
        #endif
    }

    /// Reloads from disk, discarding local edits.
    public func reloadFromDisk(preservingViewState: Bool = true) async {
        guard let currentIdentity = note?.id else { return }
        let restoredViewState = preservingViewState ? clampedViewState(
            EditorViewState(
                selection: resolvedFormattingSelection(),
                scrollOffset: scrollOffset
            ),
            for: currentText
        ) : nil

        cancelTransientTasksPreservingWatchers()

        do {
            let loaded = try await vaultProvider.readNote(at: currentIdentity.fileURL)
            guard note?.id == currentIdentity else { return }
            applyLoadedNoteState(
                loaded,
                requestedURL: currentIdentity.fileURL,
                restoredViewState: restoredViewState,
                restartFileWatching: false,
                clearUndoHistory: true
            )
            hasLoadedCurrentNoteForRestoration = true
            updateRestorationReadinessIfPossible()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "An unexpected error occurred.", bundle: .module)
        }
    }

    /// Reloads from disk after a version restore.
    /// Sets `isRestoringVersion` guard to prevent file watcher from showing spurious warnings.
    public func reloadAfterVersionRestore() async {
        guard let url = note?.fileURL else { return }
        isRestoringVersion = true
        defer { isRestoringVersion = false }
        externalModificationDetected = false
        await loadNote(at: url)
    }

    // MARK: - Text Synchronization (called by delegate)

    /// Called by the text view delegate when the user edits text.
    /// This is the ONLY path that updates `currentText` — SwiftUI never does.
    public func textDidChange(_ newText: String) {
        // Skip feedback from programmatic attachment insertion during highlighting
        guard !isApplyingHighlights else { return }

        let previousText = currentText
        currentText = newText
        synchronizeSemanticSnapshotFromCurrentText()
        refreshInNoteSearchResultsForCurrentEditorState(revealSelection: false, focusEditor: false)
        refreshLinkInsertionSuggestionsForCurrentEditorState()
        let contentChanged = newText != previousText
        scheduleExplicitRelationshipRefresh(forceGraphPublish: contentChanged)
        guard contentChanged else { return }

        if isApplyingExternalEdit {
            updateTypingAttributes()
            isDirty = true
            scheduleAutosave()
            scheduleWordCountUpdate()
            scheduleAnalysis()
            scheduleHighlight()
            return
        }

        // Track mutation origin for undo/highlight policy
        let editLen = (newText as NSString).length - (previousText as NSString).length
        let editLocation = cursorPosition.location - max(editLen, 0)
        currentTransaction = MutationTransaction(
            origin: .userTyping,
            editedRange: NSRange(location: max(editLocation, 0), length: editLen < 0 ? -editLen : 0),
            replacementLength: max(editLen, 0)
        )

        updateTypingAttributes()
        isDirty = true
        scheduleAutosave()
        scheduleWordCountUpdate()
        scheduleAnalysis()
        scheduleHighlight()
    }

    /// Called by the text view delegate when selection changes.
    public func selectionDidChange(_ range: NSRange) {
        applySelectionSnapshot(range)
    }

    /// Captures the authoritative selection immediately before the native text view
    /// resigns first responder, so toolbar/menu interactions can use the exact selection
    /// that was active at the moment focus left the editor.
    public func selectionOwnerWillResignFirstResponder(with range: NSRange) {
        if range.length == 0, cursorPosition.length > 0 {
            return
        }
        applySelectionSnapshot(range, force: true)
    }

    /// Captures the authoritative selection immediately after the native text view
    /// becomes first responder.
    public func selectionOwnerDidBecomeFirstResponder(with range: NSRange) {
        applySelectionSnapshot(range, force: true)
    }

    private func applySelectionSnapshot(_ range: NSRange, force: Bool = false) {
        guard shouldAcceptSelectionSnapshot(range, force: force) else { return }

        let previousRange = cursorPosition
        cursorPosition = range
        updateTypingAttributes()
        formattingState = FormattingState.detect(
            in: currentText,
            semanticDocument: semanticDocument,
            at: range.location
        )
        refreshLinkInsertionSuggestions(for: range)

        guard syntaxVisibilityMode == .hiddenUntilCaret,
              !isApplyingExternalEdit,
              !isApplyingHighlights,
              lastAppliedHighlightSourceText == currentText,
              !lastAppliedHighlightSpans.isEmpty,
              overlayVisibilitySignature(for: previousRange)
                != overlayVisibilitySignature(for: range) else {
            return
        }

        applyHighlightSpansForced(lastAppliedHighlightSpans)
    }

    private func shouldAcceptSelectionSnapshot(_ range: NSRange, force: Bool) -> Bool {
        if force { return true }
        if !hasMountedNativeEditor { return true }
        if activeTextViewIsFirstResponder { return true }
        return range.length > 0
    }

    /// Called by the text view delegate when scroll position changes.
    public func scrollDidChange(_ offset: CGPoint) {
        scrollOffset = offset
    }

    /// Saves current scroll state from the native text view.
    /// Call before operations that may change layout (e.g., inspector toggle).
    public func saveScrollState() {
        #if canImport(UIKit)
        scrollOffset = activeTextView?.contentOffset ?? .zero
        #elseif canImport(AppKit)
        if let scrollView = activeTextView?.enclosingScrollView {
            scrollOffset = scrollView.contentView.bounds.origin
        }
        #endif
    }

    /// Restores previously saved scroll state.
    /// Call after layout changes settle (e.g., after inspector toggle animation).
    public func restoreScrollState() {
        #if canImport(UIKit)
        activeTextView?.setContentOffset(scrollOffset, animated: false)
        #elseif canImport(AppKit)
        if let scrollView = activeTextView?.enclosingScrollView {
            scrollView.contentView.scroll(to: scrollOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        #endif
    }

    // MARK: - State Restoration (App Relaunch)

    /// Restores cursor/selection position after note reload.
    /// Called by the shell after loading a note to restore @SceneStorage state.
    ///
    /// - Parameters:
    ///   - location: The cursor location (character offset).
    ///   - length: The selection length (0 for cursor, >0 for selection).
    public func restoreCursor(location: Int, length: Int = 0) {
        let textLength = currentText.count
        // Clamp to valid range
        let clampedLocation = min(max(0, location), textLength)
        let clampedLength = min(length, textLength - clampedLocation)
        let range = NSRange(location: clampedLocation, length: clampedLength)

        pendingRestoredSelection = range
        applySelectionSnapshot(range, force: true)
        applyPendingRestorationStateIfPossible()
    }

    /// Restores scroll position after note reload.
    /// Called by the shell after loading a note to restore @SceneStorage state.
    ///
    /// - Parameter y: The vertical scroll offset.
    public func restoreScroll(y: Double) {
        let newOffset = CGPoint(x: scrollOffset.x, y: y)
        pendingRestoredScrollOffset = newOffset
        scrollOffset = newOffset
        applyPendingRestorationStateIfPossible()
    }

    /// Awaits until the editor is ready for cursor/scroll restoration.
    /// **Per CODEX.md F8:** Replaces `Task.sleep(100ms)` with explicit handshake.
    ///
    /// - Returns: Immediately if already ready, otherwise suspends until `signalReadyForRestoration()` is called.
    public func awaitReadiness() async {
        if isReadyForRestoration { return }

        await withCheckedContinuation { continuation in
            readinessContinuations.append(continuation)
        }
    }

    /// Signals that the editor is ready for cursor/scroll restoration.
    /// Production code uses `updateRestorationReadinessIfPossible()` so readiness is only
    /// published after both note content and a mounted native editor are available.
    /// This explicit signal remains available for tests and controlled overrides.
    public func signalReadyForRestoration() {
        guard !isReadyForRestoration else { return }
        isReadyForRestoration = true

        // Resume all waiting continuations
        for continuation in readinessContinuations {
            continuation.resume()
        }
        readinessContinuations.removeAll()
    }

    /// Resets the readiness state (called before loading a new note).
    private func resetReadinessState() {
        isReadyForRestoration = false
        hasLoadedCurrentNoteForRestoration = false
        // Any pending continuations are stale — resume them to unblock waiters
        for continuation in readinessContinuations {
            continuation.resume()
        }
        readinessContinuations.removeAll()
    }

    // MARK: - Undo / Redo

    /// Triggers undo on the native text view's undo manager.
    public func undo() {
        #if canImport(UIKit)
        activeTextView?.undoManager?.undo()
        #elseif canImport(AppKit)
        activeTextView?.undoManager?.undo()
        #endif
        synchronizeSnapshotFromActiveTextView()
    }

    /// Triggers redo on the native text view's undo manager.
    public func redo() {
        #if canImport(UIKit)
        activeTextView?.undoManager?.redo()
        #elseif canImport(AppKit)
        activeTextView?.undoManager?.redo()
        #endif
        synchronizeSnapshotFromActiveTextView()
    }

    /// Whether undo is available.
    public var canUndo: Bool {
        #if canImport(UIKit)
        return activeTextView?.undoManager?.canUndo ?? false
        #elseif canImport(AppKit)
        return activeTextView?.undoManager?.canUndo ?? false
        #endif
    }

    /// Whether redo is available.
    public var canRedo: Bool {
        #if canImport(UIKit)
        return activeTextView?.undoManager?.canRedo ?? false
        #elseif canImport(AppKit)
        return activeTextView?.undoManager?.canRedo ?? false
        #endif
    }

    // MARK: - Paste

    /// Pastes from the system pasteboard using the requested normalization mode.
    public func paste(mode: EditorPasteMode = .smart) {
        guard let text = systemPasteboardString() else { return }
        applyPastedText(text, mode: mode)
    }

    /// Applies pasted text using the requested normalization mode.
    public func applyPastedText(_ text: String, mode: EditorPasteMode = .smart) {
        let replacement = pasteNormalizer.normalizedText(text, mode: mode)
        let selection = currentSelectedRangeFromActiveTextView()
        let cursorAfter = NSRange(
            location: selection.location + (replacement as NSString).length,
            length: 0
        )

        applyExternalEdit(
            replacement: replacement,
            range: selection,
            cursorAfter: cursorAfter,
            origin: .pasteOrDrop
        )
    }

    // MARK: - Tag Editing

    /// Updates the note's frontmatter tags and triggers a save.
    /// Called from the inspector panel's tag editor.
    public func updateTags(_ newTags: [String]) {
        guard var currentNote = note else { return }
        currentNote.frontmatter.tags = newTags
        note = currentNote
        isDirty = true
        scheduleAutosave()
    }

    // MARK: - Formatting Commands

    /// Shared authoritative formatting entrypoint.
    /// All user-facing formatting sources must resolve through this method before mutation.
    public func handleFormattingAction(_ action: FormattingAction, source: FormattingInvocationSource) {
        let selection = resolvedFormattingSelection(for: action, source: source)
        prepareFormattingInvocation(selection, source: source)
        applyFormatting(action, selectedRange: selection)
        finalizeFormattingInvocation(source: source)
    }

    /// Applies a formatting action surgically via `applyExternalEdit`.
    /// Guarded by IME composition check.
    public func applyFormatting(_ action: FormattingAction) {
        handleFormattingAction(action, source: .commandMenu)
    }

    /// Applies a formatting action initiated from a toolbar button.
    /// Toolbar clicks can temporarily desynchronize the native text view's visible selection
    /// from the editor's last known cursor snapshot, so we resolve a single command range
    /// and restore it onto the text view before mutating markdown.
    public func applyToolbarFormatting(_ action: FormattingAction) {
        handleFormattingAction(action, source: .toolbar)
    }

    private func applyFormatting(_ action: FormattingAction, selectedRange: NSRange) {
        guard !isComposing else { return }

        ensureSemanticDocumentReadyForFormatting()

        let formatter = MarkdownFormatter()
        guard let edit = formatter.surgicalEdit(
            action,
            in: currentText,
            selectedRange: selectedRange,
            semanticDocument: semanticDocument
        ) else { return }

        if !edit.changesText {
            restoreCursor(location: edit.cursorAfter.location, length: edit.cursorAfter.length)
            selectionDidChange(edit.cursorAfter)
            return
        }

        applyExternalEdit(
            replacement: edit.replacement,
            range: edit.range,
            cursorAfter: edit.cursorAfter,
            origin: .formatting
        )
        formattingState = FormattingState.detect(
            in: currentText,
            semanticDocument: semanticDocument,
            at: edit.cursorAfter.location
        )

        // For small notes, pay the synchronous parse cost immediately so the user sees
        // the styled result now, not one async turn later.
        if currentText.count <= Self.synchronousFormattingHighlightThreshold {
            let spans = MarkdownASTHighlighter.parseImmediately(
                currentText,
                baseFontSize: highlighterBaseFontSize,
                fontFamily: highlighterFontFamily,
                vaultRootURL: vaultRootURL,
                noteURL: note?.fileURL
            )
            applyHighlightSpansForced(spans)
            return
        }

        applyOptimisticFormattingPreview(action: action, edit: edit)

        // Run highlight IMMEDIATELY with NO DIFF for larger notes once parsing completes.
        // Formatting actions are infrequent, so this can bypass the regular debounced path.
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            guard let self, let highlighter = self.highlighter else { return }
            let text = self.currentText
            let spans = await highlighter.parse(text)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.applyHighlightSpansForced(spans)
            }
        }
    }

    private func ensureSemanticDocumentReadyForFormatting() {
        let currentLength = (currentText as NSString).length
        guard !currentText.isEmpty else { return }
        guard lastAppliedHighlightSourceText != currentText || semanticDocument.textLength != currentLength else {
            return
        }

        let spans = MarkdownASTHighlighter.parseImmediately(
            currentText,
            baseFontSize: highlighterBaseFontSize,
            fontFamily: highlighterFontFamily,
            vaultRootURL: vaultRootURL,
            noteURL: note?.fileURL
        )
        applyHighlightSpansForced(spans)
    }

    private func applyOptimisticFormattingPreview(action: FormattingAction, edit: MarkdownFormatEdit) {
        let previewRange = NSRange(location: edit.range.location, length: (edit.replacement as NSString).length)
        guard previewRange.length > 0 else { return }

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        let storage = textView.textStorage
        let labelColor = UIColor.label
        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        let labelColor = NSColor.labelColor
        #endif

        guard previewRange.location >= 0, NSMaxRange(previewRange) <= storage.length else { return }

        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: labelColor]
        let baseFont = EditorFontFactory.makeFont(
            family: highlighterFontFamily,
            size: highlighterBaseFontSize
        )

        switch action {
        case .bold:
            attributes[.font] = EditorFontFactory.makeFont(
                family: highlighterFontFamily,
                size: highlighterBaseFontSize,
                weight: .bold
            )
        case .italic:
            attributes[.font] = EditorFontFactory.makeFont(
                family: highlighterFontFamily,
                size: highlighterBaseFontSize,
                italic: true
            )
        case .strikethrough:
            attributes[.font] = baseFont
            attributes[.strikethroughStyle] = 1
        case .code:
            attributes[.font] = EditorFontFactory.makeCodeFont(size: highlighterBaseFontSize * 0.9)
            #if canImport(UIKit)
            attributes[.backgroundColor] = UIColor.systemFill
            #elseif canImport(AppKit)
            attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.15)
            #endif
        default:
            return
        }

        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        storage.addAttributes(attributes, range: previewRange)
        storage.endEditing()
    }

    private func currentSelectedRangeFromActiveTextView() -> NSRange {
        #if canImport(UIKit)
        return activeTextView?.selectedRange ?? cursorPosition
        #elseif canImport(AppKit)
        return activeTextView?.selectedRange() ?? cursorPosition
        #endif
    }

    private func resolvedFormattingSelection() -> NSRange {
        if hasMountedNativeEditor, activeTextViewIsFirstResponder {
            return currentSelectedRangeFromActiveTextView()
        }
        return cursorPosition
    }

    private func resolvedFormattingSelection(
        for action: FormattingAction,
        source: FormattingInvocationSource
    ) -> NSRange {
        _ = action
        _ = source
        return resolvedFormattingSelection()
    }

    private func prepareFormattingInvocation(_ selection: NSRange, source: FormattingInvocationSource) {
        switch source {
        case .toolbar, .commandMenu:
            synchronizeActiveSelectionForFormatting(selection)
        case .hardwareKeyboard:
            if cursorPosition != selection {
                selectionDidChange(selection)
            }
        }
    }

    private func finalizeFormattingInvocation(source: FormattingInvocationSource) {
        switch source {
        case .toolbar:
            reassertToolbarSelectionAfterFormatting()
        case .hardwareKeyboard, .commandMenu:
            break
        }
    }

    private var activeTextViewIsFirstResponder: Bool {
        #if canImport(UIKit)
        return activeTextView?.isFirstResponder ?? false
        #elseif canImport(AppKit)
        guard let textView = activeTextView else { return false }
        return textView.window?.firstResponder === textView
        #endif
    }

    private func synchronizeActiveSelectionForFormatting(_ range: NSRange) {
        #if canImport(UIKit)
        if let textView = activeTextView {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            if textView.selectedRange != range {
                textView.selectedRange = range
            }
        }
        #elseif canImport(AppKit)
        if let textView = activeTextView {
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
            if textView.selectedRange() != range {
                textView.setSelectedRange(range)
            }
        }
        #endif

        if cursorPosition != range {
            selectionDidChange(range)
        }
    }

    private func reassertToolbarSelectionAfterFormatting() {
        #if canImport(UIKit)
        let expectedSelection = cursorPosition
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.synchronizeActiveSelectionForFormatting(expectedSelection)
        }
        #endif
    }

    #if canImport(UIKit)
    public func bindActiveTextView(_ textView: UITextView) {
        activeTextView = textView
        hasMountedNativeEditor = true
        applyPendingRestorationStateIfPossible()
        updateRestorationReadinessIfPossible()
    }

    public func unbindActiveTextView(_ textView: UITextView) {
        guard activeTextView === textView else { return }
        selectionOwnerWillResignFirstResponder(with: textView.selectedRange)
        activeTextView = nil
        hasMountedNativeEditor = false
    }
    #elseif canImport(AppKit)
    public func bindActiveTextView(_ textView: NSTextView) {
        activeTextView = textView
        hasMountedNativeEditor = true
        applyPendingRestorationStateIfPossible()
        updateRestorationReadinessIfPossible()
    }

    public func unbindActiveTextView(_ textView: NSTextView) {
        guard activeTextView === textView else { return }
        selectionOwnerWillResignFirstResponder(with: textView.selectedRange())
        activeTextView = nil
        hasMountedNativeEditor = false
    }
    #endif

    private func saveViewStateForCurrentNote() {
        guard let noteURL = note?.fileURL else { return }
        noteViewStateByURL[CanonicalNoteIdentity.canonicalFileURL(for: noteURL)] = EditorViewState(
            selection: resolvedFormattingSelection(),
            scrollOffset: scrollOffset
        )
    }

    private func viewState(forLoadedNoteAt url: URL) -> EditorViewState? {
        noteViewStateByURL[CanonicalNoteIdentity.canonicalFileURL(for: url)]
    }

    private func stageViewStateForLoadedNote(at url: URL) {
        if let viewState = viewState(forLoadedNoteAt: url) {
            pendingRestoredSelection = viewState.selection
            pendingRestoredScrollOffset = viewState.scrollOffset
            applySelectionSnapshot(viewState.selection, force: true)
            scrollOffset = viewState.scrollOffset
        } else {
            pendingRestoredSelection = nil
            pendingRestoredScrollOffset = nil
            applySelectionSnapshot(NSRange(location: 0, length: 0), force: true)
            scrollOffset = .zero
        }
    }

    private func clampedViewState(_ viewState: EditorViewState, for text: String) -> EditorViewState {
        let textLength = (text as NSString).length
        let clampedLocation = min(max(0, viewState.selection.location), textLength)
        let clampedLength = min(max(0, viewState.selection.length), textLength - clampedLocation)
        return EditorViewState(
            selection: NSRange(location: clampedLocation, length: clampedLength),
            scrollOffset: viewState.scrollOffset
        )
    }

    private func applyLoadedNoteState(
        _ loaded: NoteDocument,
        requestedURL: URL,
        restoredViewState: EditorViewState?,
        restartFileWatching: Bool,
        clearUndoHistory: Bool
    ) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: requestedURL)
        note = loaded
        currentText = loaded.body
        lastPublishedExplicitReferences = []
        isDirty = false
        errorMessage = nil
        externalModificationDetected = false
        pendingExternalChangeIdentity = nil
        wordCount = Self.countWords(in: loaded.body)
        linkInsertion.dismiss()

        if let restoredViewState {
            let clampedState = clampedViewState(restoredViewState, for: loaded.body)
            noteViewStateByURL[canonicalURL] = clampedState
            pendingRestoredSelection = clampedState.selection
            pendingRestoredScrollOffset = clampedState.scrollOffset
            applySelectionSnapshot(clampedState.selection, force: true)
            scrollOffset = clampedState.scrollOffset
        } else {
            stageViewStateForLoadedNote(at: canonicalURL)
        }

        #if canImport(UIKit)
        activeTextView?.text = loaded.body
        #elseif canImport(AppKit)
        activeTextView?.string = loaded.body
        #endif

        applyPendingRestorationStateIfPossible()
        refreshInNoteSearchResultsForCurrentEditorState(revealSelection: false, focusEditor: false)

        if clearUndoHistory {
            clearUndoStack()
        }

        lastKnownDiskContentHash = nil
        scheduleDeferredPostLoadWork(for: canonicalURL, restartFileWatching: restartFileWatching)

        applyPendingNoteNavigationIfNeeded(for: canonicalURL)
    }

    private func scheduleDeferredPostLoadWork(for canonicalURL: URL, restartFileWatching: Bool) {
        postLoadTask?.cancel()
        postLoadTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self, self.note?.fileURL == canonicalURL else { return }

            self.refreshKnownDiskContentHashAsync(for: canonicalURL)

            await self.highlighter?.updateSettings(
                fontFamily: self.highlighterFontFamily,
                lineSpacing: self.highlighterLineSpacing,
                vaultRootURL: self.vaultRootURL,
                noteURL: canonicalURL
            )

            guard self.note?.fileURL == canonicalURL else { return }
            self.highlightImmediately(priority: .utility)
            self.scheduleAnalysis()
            self.scheduleExplicitRelationshipRefresh(forceGraphPublish: true)
            await self.refreshRelatedNotes()
            await self.refreshAIConcepts()

            guard self.note?.fileURL == canonicalURL else { return }
            if restartFileWatching {
                self.startFileWatching(for: canonicalURL)
            }
        }
    }

    private func applyPendingRestorationStateIfPossible() {
        guard hasMountedNativeEditor else { return }

        #if canImport(UIKit)
        if let selection = pendingRestoredSelection, let textView = activeTextView, textView.selectedRange != selection {
            textView.selectedRange = selection
        }
        if let offset = pendingRestoredScrollOffset {
            activeTextView?.setContentOffset(offset, animated: false)
        }
        #elseif canImport(AppKit)
        if let selection = pendingRestoredSelection, let textView = activeTextView, textView.selectedRange() != selection {
            textView.setSelectedRange(selection)
        }
        if let offset = pendingRestoredScrollOffset, let scrollView = activeTextView?.enclosingScrollView {
            scrollView.contentView.scroll(to: offset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        #endif

        pendingRestoredSelection = nil
        pendingRestoredScrollOffset = nil
    }

    private func updateRestorationReadinessIfPossible() {
        guard hasLoadedCurrentNoteForRestoration, hasMountedNativeEditor else { return }
        signalReadyForRestoration()
    }

    private func systemPasteboardString() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }

    /// Applies highlight spans WITHOUT diffing — forces all attributes to be rewritten.
    /// Used after formatting actions where stale overlay attributes may have shifted.
    private func applyHighlightSpansForced(_ spans: [HighlightSpan]) {
        guard !isComposing else { return }
        isApplyingHighlights = true
        defer { isApplyingHighlights = false }
        lastAppliedHighlightSpans = spans
        lastAppliedHighlightSourceText = currentText
        semanticDocument = EditorSemanticDocument.build(markdown: currentText, spans: spans)
        lastRenderPlan = EditorRenderPlan(spans: spans)
        inspectorStore.setHeadings(authoritativeHeadingItems())
        formattingState = FormattingState.detect(
            in: currentText,
            semanticDocument: semanticDocument,
            at: cursorPosition.location
        )

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let defaultColor: UIColor = .label
        let segments = lastRenderPlan.primarySegments(
            for: semanticDocument,
            defaultFont: defaultFont,
            defaultColor: defaultColor,
            defaultParagraphStyle: { [highlighterLineSpacing] block in
                EditorTypography.paragraphStyle(
                    for: block?.kind,
                    baseFontSize: baseFontSize,
                    lineSpacingMultiplier: highlighterLineSpacing
                )
            }
        ).filter { $0.range.location >= 0 && NSMaxRange($0.range) <= storageLength }

        // Disable undo registration — attribute styling should NOT pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        // NO DIFF — force set all attributes unconditionally
        for segment in segments {
            guard segment.range.length > 0 else { continue }
            storage.setAttributes(segment.attributes, range: segment.range)
        }
        for span in lastRenderPlan.overlaySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                storage.addAttribute(
                    .foregroundColor,
                    value: adjustedOverlayColor(color, overlayVisibilityBehavior: span.overlayVisibilityBehavior),
                    range: r
                )
            }
            if let kern = span.kern {
                storage.addAttribute(.kern, value: kern, range: r)
            }
            if let title = span.wikiLinkTitle {
                storage.addAttribute(.quartzWikiLink, value: title, range: r)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        // Apply inline image attachments — replace first char with U+FFFC
        for span in lastRenderPlan.attachmentSpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            let attachRange = NSRange(location: r.location, length: 1)
            storage.replaceCharacters(in: attachRange, with: "\u{FFFC}")
            storage.addAttribute(.attachment, value: span.attachment!, range: attachRange)
        }
        storage.endEditing()

        if textView.selectedRange != savedSelection {
            let len = (textView.text ?? "").count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.selectedRange = savedSelection
            }
        }
        updateTypingAttributes()

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }

        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange()

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let defaultColor: NSColor = .labelColor
        let segments = lastRenderPlan.primarySegments(
            for: semanticDocument,
            defaultFont: defaultFont,
            defaultColor: defaultColor,
            defaultParagraphStyle: { [highlighterLineSpacing] block in
                EditorTypography.paragraphStyle(
                    for: block?.kind,
                    baseFontSize: baseFontSize,
                    lineSpacingMultiplier: highlighterLineSpacing
                )
            }
        ).filter { $0.range.location >= 0 && NSMaxRange($0.range) <= storageLength }

        // Disable undo registration — attribute styling should NOT pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        // NO DIFF — force set all attributes unconditionally
        for segment in segments {
            guard segment.range.length > 0 else { continue }
            storage.setAttributes(segment.attributes, range: segment.range)
        }
        for span in lastRenderPlan.overlaySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                storage.addAttribute(
                    .foregroundColor,
                    value: adjustedOverlayColor(color, overlayVisibilityBehavior: span.overlayVisibilityBehavior),
                    range: r
                )
            }
            if let kern = span.kern {
                storage.addAttribute(.kern, value: kern, range: r)
            }
            if let title = span.wikiLinkTitle {
                storage.addAttribute(.quartzWikiLink, value: title, range: r)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        // Apply inline image attachments — replace first char with U+FFFC
        for span in lastRenderPlan.attachmentSpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            let attachRange = NSRange(location: r.location, length: 1)
            storage.replaceCharacters(in: attachRange, with: "\u{FFFC}")
            storage.addAttribute(.attachment, value: span.attachment!, range: attachRange)
        }
        storage.endEditing()

        if textView.selectedRange() != savedSelection {
            let len = textView.string.count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.setSelectedRange(savedSelection)
            }
        }
        updateTypingAttributes()
        #endif
    }

    // MARK: - External Edit (Surgical, IME-Safe)

    /// Applies a surgical text edit from an external source (list continuation,
    /// AI insertion, iCloud merge). Uses `NSTextStorage.replaceCharacters`
    /// for proper undo registration and minimal layout invalidation.
    ///
    /// **IME Guard**: Refuses to mutate text during active composition.
    ///
    /// - Parameters:
    ///   - replacement: The text to insert.
    ///   - range: The range to replace.
    ///   - cursorAfter: Optional cursor position after the edit.
    ///   - origin: The mutation origin — determines undo/highlight policy.
    public func applyExternalEdit(
        replacement: String,
        range: NSRange,
        cursorAfter: NSRange? = nil,
        origin: MutationOrigin = .formatting
    ) {
        guard !isComposing else { return }
        isApplyingExternalEdit = true
        defer { isApplyingExternalEdit = false }

        // Track mutation transaction
        currentTransaction = MutationTransaction(
            origin: origin,
            editedRange: range,
            replacementLength: (replacement as NSString).length
        )

        let transaction = currentTransaction!

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        let undoManager = textView.undoManager

        // Undo policy from transaction
        if transaction.clearsUndoStack {
            undoManager?.removeAllActions()
        }
        if !transaction.registersUndo {
            undoManager?.disableUndoRegistration()
        }
        if transaction.needsExplicitUndoGroup {
            undoManager?.beginUndoGrouping()
        }

        let originalText = ((textView.text ?? "") as NSString).substring(with: range)
        let originalSelection = textView.selectedRange
        if transaction.registersUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                target.applyExternalEdit(
                    replacement: originalText,
                    range: NSRange(location: range.location, length: (replacement as NSString).length),
                    cursorAfter: originalSelection,
                    origin: origin
                )
            }
        }

        textView.textStorage.replaceCharacters(in: range, with: replacement)

        if let cursor = cursorAfter {
            if let start = textView.position(from: textView.beginningOfDocument, offset: cursor.location),
               let end = textView.position(from: start, offset: cursor.length) {
                textView.selectedTextRange = textView.textRange(from: start, to: end)
            }
        }

        if transaction.needsExplicitUndoGroup {
            undoManager?.endUndoGrouping()
        }
        if !transaction.registersUndo {
            undoManager?.enableUndoRegistration()
        }

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        let undoManager = textView.undoManager

        // Undo policy from transaction
        if transaction.clearsUndoStack {
            undoManager?.removeAllActions()
        }
        if !transaction.registersUndo {
            undoManager?.disableUndoRegistration()
        }
        if transaction.needsExplicitUndoGroup {
            undoManager?.beginUndoGrouping()
        }

        guard textView.shouldChangeText(in: range, replacementString: replacement) else {
            if transaction.needsExplicitUndoGroup {
                undoManager?.endUndoGrouping()
            }
            if !transaction.registersUndo {
                undoManager?.enableUndoRegistration()
            }
            return
        }

        storage.replaceCharacters(in: range, with: replacement)

        // AppKit's shouldChangeText/didChangeText pipeline owns undo registration.
        // Registering a second custom undo action here corrupts the mounted text system.
        textView.didChangeText()

        if let cursor = cursorAfter {
            textView.setSelectedRange(cursor)
        }

        if transaction.needsExplicitUndoGroup {
            undoManager?.endUndoGrouping()
        }
        if !transaction.registersUndo {
            undoManager?.enableUndoRegistration()
        }

        #endif

        synchronizeSnapshotFromActiveTextView()

        isDirty = true
        scheduleAutosave()
        scheduleWordCountUpdate()
        scheduleAnalysis()
        scheduleHighlight()
    }

    // MARK: - IME Guard

    /// Returns true if the text view is in an active IME composition (CJK, dead keys, etc.).
    /// ALL mutation paths must check this before touching text or attributes.
    public var isComposing: Bool {
        #if canImport(UIKit)
        return activeTextView?.markedTextRange != nil
        #elseif canImport(AppKit)
        return activeTextView?.hasMarkedText() ?? false
        #endif
    }

    // MARK: - Saving

    /// Saves the current note immediately.
    public func save(force: Bool = false) async {
        guard var currentNote = note, (isDirty || force) else { return }
        if isSaving {
            savePendingAfterCurrentWrite = true
            if force {
                forceSavePendingAfterCurrentWrite = true
            }
            return
        }

        let forceVersionSnapshotForThisSave = force
        isSaving = true
        savePendingAfterCurrentWrite = false
        isSavingToFileSystem = true
        defer {
            isSaving = false
            // Delay clearing isSavingToFileSystem to allow NSFilePresenter callback
            // to see the flag before it's cleared. Content hash provides the
            // authoritative echo check; this flag is a fast-path optimization.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.isSavingToFileSystem = false
            }
            if savePendingAfterCurrentWrite || isDirty {
                let replayForce = forceSavePendingAfterCurrentWrite
                savePendingAfterCurrentWrite = false
                forceSavePendingAfterCurrentWrite = false
                scheduleAutosave(force: replayForce)
            }
        }

        // Snapshot from native view (the source of truth)
        let textSnapshot: String
        #if canImport(UIKit)
        textSnapshot = activeTextView?.text ?? currentText
        #elseif canImport(AppKit)
        textSnapshot = activeTextView?.string ?? currentText
        #endif

        currentNote.body = textSnapshot
        currentNote.frontmatter.modifiedAt = .now

        do {
            let savedURL = currentNote.fileURL
            try await vaultProvider.saveNote(currentNote, filePresenter: filePresenter)

            // Compute and store content hash for echo suppression.
            // Hash the FULL serialized content (frontmatter + body) to match what's on disk.
            // If a file-change event arrives and the on-disk hash matches this,
            // we know it's our own write — not an external modification.
            if let yamlString = try? frontmatterParser.serialize(currentNote.frontmatter) {
                let fullContent = yamlString.isEmpty
                    ? textSnapshot
                    : "---\n\(yamlString)---\n\n\(textSnapshot)"
                if let savedData = fullContent.data(using: .utf8) {
                    lastSavedContentHash = SHA256.hash(data: savedData)
                    lastKnownDiskContentHash = lastSavedContentHash
                }
            }

            note = currentNote
            // Only clear dirty if content hasn't changed since snapshot
            let savedSnapshotStillCurrent = currentText == textSnapshot
            if savedSnapshotStillCurrent {
                isDirty = false
            }
            consecutiveSaveFailures = 0
            postSaveHealthChanged(state: "recovered", url: savedURL)
            errorMessage = nil
            QuartzDiagnostics.info(
                category: "EditorSave",
                "save completed url=\(savedURL.lastPathComponent) chars=\((textSnapshot as NSString).length) dirtyAfter=\(isDirty)"
            )

            // Publish via typed event bus (new pattern per CODEX.md F4)
            await DomainEventBus.shared.publish(.noteSaved(url: savedURL, timestamp: Date()))

            // Legacy NotificationCenter for backward compatibility
            NotificationCenter.default.post(name: .quartzNoteSaved, object: savedURL)

            scheduleExplicitRelationshipRefresh(
                forceGraphPublish: true,
                sourceURL: savedURL,
                content: textSnapshot
            )

            if savedSnapshotStillCurrent {
                let forceSnapshot = forceVersionSnapshotForThisSave || forceSavePendingAfterCurrentWrite
                scheduleVersionSnapshotIfNeeded(
                    noteURL: savedURL,
                    content: textSnapshot,
                    force: forceSnapshot
                )
                savePendingAfterCurrentWrite = false
                forceSavePendingAfterCurrentWrite = false
            }
        } catch {
            consecutiveSaveFailures += 1
            let fallbackResult = await attemptEmergencySaveIfNeeded(
                note: currentNote,
                textSnapshot: textSnapshot,
                originalError: error
            )
            var primarySaveRemainsFailed = true
            switch fallbackResult {
            case .primaryFileSaved:
                primarySaveRemainsFailed = false
                updateSavedContentHashes(for: currentNote)
                note = currentNote
                let savedSnapshotStillCurrent = currentText == textSnapshot
                if savedSnapshotStillCurrent {
                    isDirty = false
                }
                consecutiveSaveFailures = 0
                errorMessage = String(localized: "Saved using emergency local file recovery because iCloud coordination timed out.", bundle: .module)
                postSaveHealthChanged(state: "recovered", url: currentNote.fileURL)
                await DomainEventBus.shared.publish(.noteSaved(url: currentNote.fileURL, timestamp: Date()))
                NotificationCenter.default.post(name: .quartzNoteSaved, object: currentNote.fileURL)
                scheduleExplicitRelationshipRefresh(
                    forceGraphPublish: true,
                    sourceURL: currentNote.fileURL,
                    content: textSnapshot
                )
                if savedSnapshotStillCurrent {
                    scheduleVersionSnapshotIfNeeded(
                        noteURL: currentNote.fileURL,
                        content: textSnapshot,
                        force: forceVersionSnapshotForThisSave || forceSavePendingAfterCurrentWrite
                    )
                    savePendingAfterCurrentWrite = false
                    forceSavePendingAfterCurrentWrite = false
                }
            case .recoveryCopySaved(let recoveryURL):
                errorMessage = String(localized: "iCloud save is blocked. Your edits are preserved in an emergency recovery copy: \(recoveryURL.lastPathComponent)", bundle: .module)
                postSaveHealthChanged(state: "failed", url: currentNote.fileURL, error: error)
            case .notAttempted, .failed:
                errorMessage = error.localizedDescription
                postSaveHealthChanged(state: "failed", url: currentNote.fileURL, error: error)
            }
            if primarySaveRemainsFailed {
                if forceVersionSnapshotForThisSave {
                    forceSavePendingAfterCurrentWrite = true
                }
                QuartzDiagnostics.error(
                    category: "EditorSave",
                    "save failed url=\(currentNote.fileURL.lastPathComponent) failures=\(consecutiveSaveFailures) nextRetrySeconds=\(autosaveRetryDelaySeconds()) error=\(error.localizedDescription)"
                )
            } else {
                QuartzDiagnostics.warning(
                    category: "EditorSave",
                    "primary save recovered by emergency direct write url=\(currentNote.fileURL.lastPathComponent)"
                )
            }
        }
    }

    /// Explicit save triggered by user action (Cmd+S, toolbar button).
    public func manualSave() async {
        // Manual save should force a version snapshot, but only after the
        // primary save has succeeded. Under iCloud coordination failure, version
        // history work must not compete with the primary save.
        await save(force: true)
    }

    /// Returns true if enough time has passed since the last snapshot.
    private func shouldSaveVersionSnapshot() -> Bool {
        guard let lastDate = lastSnapshotDate else {
            lastSnapshotDate = Date()
            return true // Create snapshot on first save of this editing session
        }
        return Date().timeIntervalSince(lastDate) >= Self.versionSnapshotInterval
    }

    // MARK: - Highlighting

    /// The highlighter and content manager. Set by the representable after text view creation.
    public var highlighter: MarkdownASTHighlighter?
    public var contentManager: MarkdownTextContentManager?
    /// Base font size for highlighting. Set by the representable.
    public var highlighterBaseFontSize: CGFloat = 14
    /// Font family for highlighting. Set by the representable.
    public var highlighterFontFamily: AppearanceManager.EditorFontFamily = .system
    /// Line spacing multiplier. Set by the representable.
    public var highlighterLineSpacing: CGFloat = 1.5
    /// Syntax visibility mode. Set by the representable from AppearanceManager.
    public var syntaxVisibilityMode: SyntaxVisibilityMode = .hiddenUntilCaret
    /// Semantic editor model derived from the latest markdown parse.
    public private(set) var semanticDocument: EditorSemanticDocument = .empty
    /// Stored for deinit cleanup of debounced highlight work.
    nonisolated(unsafe) private var highlightTask: Task<Void, Never>?
    /// Reused when selection-only changes should refresh concealment without reparsing.
    private var lastAppliedHighlightSpans: [HighlightSpan] = []
    /// Source text for the cached highlight spans.
    private var lastAppliedHighlightSourceText: String = ""
    /// Cached render grouping so the editor applies the latest parsed plan, not ad-hoc filters.
    private var lastRenderPlan: EditorRenderPlan = .empty

    /// Schedules a debounced highlight pass. Skips if IME is composing.
    /// Uses incremental parsing when the current transaction supports it.
    public func scheduleHighlight() {
        guard !isComposing else { return }

        // Capture transaction info for the incremental path
        let transaction = currentTransaction

        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            guard let self, let highlighter = self.highlighter else { return }
            let text = self.currentText

            let spans: [HighlightSpan]
            if let tx = transaction, tx.prefersIncrementalHighlight {
                // Incremental path: re-parse only the dirty region
                let postEditRange = NSRange(
                    location: tx.editedRange.location,
                    length: tx.replacementLength
                )
                spans = await highlighter.parseIncremental(
                    text,
                    editRange: postEditRange,
                    preEditLength: tx.editedRange.length
                )
            } else {
                // Full re-parse path
                spans = await highlighter.parseDebounced(text)
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.applyHighlightSpans(spans)
            }
        }
    }

    /// Immediate (non-debounced) highlight for initial load. No 80ms wait.
    public func highlightImmediately(priority: TaskPriority = .utility) {
        guard !isComposing else { return }

        highlightTask?.cancel()
        highlightTask = Task(priority: priority) { [weak self] in
            guard let self, let highlighter = self.highlighter else { return }
            let text = self.currentText
            let spans = await highlighter.parse(text)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.applyHighlightSpansForced(spans)
            }
        }
    }

    /// Applies highlight spans to the native text view with IME guard.
    private func applyHighlightSpans(_ spans: [HighlightSpan]) {
        guard !isComposing else { return }
        isApplyingHighlights = true
        defer { isApplyingHighlights = false }
        lastAppliedHighlightSpans = spans
        lastAppliedHighlightSourceText = currentText
        semanticDocument = EditorSemanticDocument.build(markdown: currentText, spans: spans)
        lastRenderPlan = EditorRenderPlan(spans: spans)
        inspectorStore.setHeadings(authoritativeHeadingItems())
        formattingState = FormattingState.detect(
            in: currentText,
            semanticDocument: semanticDocument,
            at: cursorPosition.location
        )

        #if canImport(UIKit)
        guard let textView = activeTextView, contentManager != nil else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let defaultColor: UIColor = .label

        let segments = lastRenderPlan.primarySegments(
            for: semanticDocument,
            defaultFont: defaultFont,
            defaultColor: defaultColor,
            defaultParagraphStyle: { [highlighterLineSpacing] block in
                EditorTypography.paragraphStyle(
                    for: block?.kind,
                    baseFontSize: baseFontSize,
                    lineSpacingMultiplier: highlighterLineSpacing
                )
            }
        ).filter { $0.range.location >= 0 && NSMaxRange($0.range) <= storageLength }

        // Disable undo registration — attribute styling should not pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        for segment in segments {
            guard segment.range.length > 0 else { continue }
            if rangeNeedsFullAttributeRewrite(storage, range: segment.range, targetAttrs: segment.attributes) {
                storage.setAttributes(segment.attributes, range: segment.range)
            }
        }
        for span in lastRenderPlan.overlaySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                let adjusted = adjustedOverlayColor(color, overlayVisibilityBehavior: span.overlayVisibilityBehavior)
                let existing = storage.attributes(at: r.location, effectiveRange: nil)
                if !colorsEqual(existing[.foregroundColor] as? UIColor, adjusted) {
                    storage.addAttribute(.foregroundColor, value: adjusted, range: r)
                }
            }
            if let kern = span.kern {
                storage.addAttribute(.kern, value: kern, range: r)
            }
            if let title = span.wikiLinkTitle {
                storage.addAttribute(.quartzWikiLink, value: title, range: r)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        // Apply inline image attachments — replace first char with U+FFFC
        for span in lastRenderPlan.attachmentSpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            let attachRange = NSRange(location: r.location, length: 1)
            storage.replaceCharacters(in: attachRange, with: "\u{FFFC}")
            storage.addAttribute(.attachment, value: span.attachment!, range: attachRange)
        }
        storage.endEditing()

        if textView.selectedRange != savedSelection {
            let len = (textView.text ?? "").count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.selectedRange = savedSelection
            }
        }
        updateTypingAttributes()

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }

        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange()

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let defaultColor: NSColor = .labelColor

        let segments = lastRenderPlan.primarySegments(
            for: semanticDocument,
            defaultFont: defaultFont,
            defaultColor: defaultColor,
            defaultParagraphStyle: { [highlighterLineSpacing] block in
                EditorTypography.paragraphStyle(
                    for: block?.kind,
                    baseFontSize: baseFontSize,
                    lineSpacingMultiplier: highlighterLineSpacing
                )
            }
        ).filter { $0.range.location >= 0 && NSMaxRange($0.range) <= storageLength }

        // Disable undo registration — attribute styling should not pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        for segment in segments {
            guard segment.range.length > 0 else { continue }
            if rangeNeedsFullAttributeRewrite(storage, range: segment.range, targetAttrs: segment.attributes) {
                storage.setAttributes(segment.attributes, range: segment.range)
            }
        }
        for span in lastRenderPlan.overlaySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                let adjusted = adjustedOverlayColor(color, overlayVisibilityBehavior: span.overlayVisibilityBehavior)
                let existing = storage.attributes(at: r.location, effectiveRange: nil)
                if !colorsEqual(existing[.foregroundColor] as? NSColor, adjusted) {
                    storage.addAttribute(.foregroundColor, value: adjusted, range: r)
                }
            }
            if let kern = span.kern {
                storage.addAttribute(.kern, value: kern, range: r)
            }
            if let title = span.wikiLinkTitle {
                storage.addAttribute(.quartzWikiLink, value: title, range: r)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }
        // Apply inline image attachments — replace first char with U+FFFC
        for span in lastRenderPlan.attachmentSpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            let attachRange = NSRange(location: r.location, length: 1)
            storage.replaceCharacters(in: attachRange, with: "\u{FFFC}")
            storage.addAttribute(.attachment, value: span.attachment!, range: attachRange)
        }
        storage.endEditing()

        if textView.selectedRange() != savedSelection {
            let len = textView.string.count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.setSelectedRange(savedSelection)
            }
        }
        updateTypingAttributes()
        #endif
    }

    // MARK: - Typing Attributes

    /// Updates typing attributes based on the current line's markdown context.
    ///
    /// If the cursor is on a heading line (`# `, `## `, etc.), sets the typing font
    /// to the heading's bold scaled font so new characters appear at the correct size
    /// immediately — no flash from default → heading after the debounced highlight.
    ///
    /// Otherwise falls back to reading attributes from the character before the cursor.
    private func updateTypingAttributes() {
        let baseFontSize = highlighterBaseFontSize

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        let text = textView.text ?? ""
        let loc = textView.selectedRange.location
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let typingContext = semanticDocument.typingContext(at: loc)
        let paragraphStyle = EditorTypography.paragraphStyle(
            for: semanticDocument.block(containing: loc)?.kind,
            baseFontSize: baseFontSize,
            lineSpacingMultiplier: highlighterLineSpacing
        )

        if semanticDocument.isBlankBlock(at: loc) || text.isEmpty {
            var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
            typing[.font] = defaultFont
            typing[.foregroundColor] = UIColor.label
            typing[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = typing
            return
        }

        if case let .heading(level) = typingContext,
           let headingFont = headingFont(for: level, baseFontSize: baseFontSize, platform: .uiKit) {
            var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
            typing[.font] = headingFont
            typing[.foregroundColor] = UIColor.label
            typing[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = typing
            return
        }

        // Fallback: read from character before cursor
        guard loc > 0 else { return }
        let attrs = textView.textStorage.attributes(at: max(0, loc - 1), effectiveRange: nil)
        var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
        if let font = attrs[.font] as? UIFont { typing[.font] = font }
        if let color = attrs[.foregroundColor] as? UIColor { typing[.foregroundColor] = color }
        typing[.paragraphStyle] = paragraphStyle
        textView.typingAttributes = typing

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        let text = textView.string
        let loc = textView.selectedRange().location
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)
        let typingContext = semanticDocument.typingContext(at: loc)
        let paragraphStyle = EditorTypography.paragraphStyle(
            for: semanticDocument.block(containing: loc)?.kind,
            baseFontSize: baseFontSize,
            lineSpacingMultiplier: highlighterLineSpacing
        )

        if semanticDocument.isBlankBlock(at: loc) || text.isEmpty {
            var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
            typing[.font] = defaultFont
            typing[.foregroundColor] = NSColor.labelColor
            typing[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = typing
            return
        }

        if case let .heading(level) = typingContext,
           let headingFont = headingFont(for: level, baseFontSize: baseFontSize, platform: .appKit) {
            var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
            typing[.font] = headingFont
            typing[.foregroundColor] = NSColor.labelColor
            typing[.paragraphStyle] = paragraphStyle
            textView.typingAttributes = typing
            return
        }

        // Fallback: read from character before cursor
        guard loc > 0 else { return }
        let attrs = storage.attributes(at: max(0, loc - 1), effectiveRange: nil)
        var typing = sanitizedTypingAttributes(from: textView.typingAttributes)
        if let font = attrs[.font] as? NSFont { typing[.font] = font }
        if let color = attrs[.foregroundColor] as? NSColor { typing[.foregroundColor] = color }
        typing[.paragraphStyle] = paragraphStyle
        textView.typingAttributes = typing
        #endif
    }

    private func sanitizedTypingAttributes(
        from attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var typing = attributes
        typing.removeValue(forKey: .kern)
        typing.removeValue(forKey: .quartzTableRowStyle)
        typing.removeValue(forKey: .backgroundColor)
        typing.removeValue(forKey: .attachment)
        typing.removeValue(forKey: .quartzWikiLink)
        typing.removeValue(forKey: .underlineStyle)
        typing.removeValue(forKey: .strikethroughStyle)
        return typing
    }

    private enum Platform { case uiKit, appKit }

    private func headingFont(for level: Int, baseFontSize: CGFloat, platform: Platform) -> Any? {
        let scale = EditorTypography.headingScale(for: level)

        switch platform {
        case .uiKit:
            #if canImport(UIKit)
            return EditorFontFactory.makeFont(
                family: highlighterFontFamily,
                size: baseFontSize * scale,
                weight: .bold
            )
            #else
            return nil
            #endif
        case .appKit:
            #if canImport(AppKit)
            return EditorFontFactory.makeFont(
                family: highlighterFontFamily,
                size: baseFontSize * scale,
                weight: .bold
            )
            #else
            return nil
            #endif
        }
    }

    /// Test seam for deterministic attributed-string regression coverage.
    func applyHighlightSpansForTesting(_ spans: [HighlightSpan]) {
        applyHighlightSpans(spans)
    }

    // MARK: - Autosave

    private func autosaveRetryDelaySeconds() -> Int {
        guard consecutiveSaveFailures > 0 else { return 1 }
        return min(60, max(5, 5 * (1 << min(consecutiveSaveFailures - 1, 3))))
    }

    private func scheduleVersionSnapshotIfNeeded(noteURL: URL, content: String, force: Bool) {
        guard let vaultRoot = vaultRootURL,
              force || shouldSaveVersionSnapshot() else {
            return
        }
        lastSnapshotDate = Date()
        Task.detached(priority: .utility) {
            VersionHistoryService().saveSnapshot(for: noteURL, content: content, vaultRoot: vaultRoot)
        }
    }

    private func scheduleAutosave(force: Bool = false) {
        autosaveTask?.cancel()
        let capturedNoteURL = note?.fileURL
        let retryDelay = consecutiveSaveFailures == 0 ? autosaveDelay : .seconds(autosaveRetryDelaySeconds())
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else { return }
            // Verify we're still on the same note (prevents saving wrong note after switch)
            guard let self, self.note?.fileURL == capturedNoteURL else { return }
            await self.save(force: force)
        }
    }

    private enum EmergencySaveResult {
        case notAttempted
        case primaryFileSaved
        case recoveryCopySaved(URL)
        case failed
    }

    private func attemptEmergencySaveIfNeeded(
        note: NoteDocument,
        textSnapshot: String,
        originalError: Error
    ) async -> EmergencySaveResult {
        guard isCoordinationTimeout(originalError),
              consecutiveSaveFailures >= Self.saveRecoveryFallbackThreshold,
              let data = serializedData(for: note) else {
            return .notAttempted
        }

        if isSafeEmergencyPrimaryWriteURL(note.fileURL) {
            do {
                let noteURL = note.fileURL
                try await Task.detached(priority: .userInitiated) {
                    try Self.createParentDirectoryIfNeeded(for: noteURL)
                    try data.write(to: noteURL, options: .atomic)
                }.value
                QuartzDiagnostics.warning(
                    category: "EditorSave",
                    "emergency primary write succeeded url=\(note.fileURL.lastPathComponent) after coordination timeout failures=\(consecutiveSaveFailures)"
                )
                return .primaryFileSaved
            } catch {
                return await writeEmergencyRecoveryCopyResult(
                    data: data,
                    sourceURL: note.fileURL,
                    textLength: (textSnapshot as NSString).length,
                    primaryError: error
                )
            }
        }

        QuartzDiagnostics.warning(
            category: "EditorSave",
            "emergency primary write skipped for non-vault note url=\(note.fileURL.lastPathComponent)"
        )
        return await writeEmergencyRecoveryCopyResult(
            data: data,
            sourceURL: note.fileURL,
            textLength: (textSnapshot as NSString).length,
            primaryError: originalError
        )
    }

    private func writeEmergencyRecoveryCopyResult(
        data: Data,
        sourceURL: URL,
        textLength: Int,
        primaryError: Error
    ) async -> EmergencySaveResult {
        do {
            let recoveryURL = try await Task.detached(priority: .userInitiated) {
                try Self.writeEmergencyRecoveryCopy(
                    data: data,
                    sourceURL: sourceURL,
                    textLength: textLength
                )
            }.value
            QuartzDiagnostics.error(
                category: "EditorSave",
                "emergency recovery copy written url=\(sourceURL.lastPathComponent) recovery=\(recoveryURL.path(percentEncoded: false)) primaryError=\(primaryError.localizedDescription)"
            )
            return .recoveryCopySaved(recoveryURL)
        } catch {
            QuartzDiagnostics.error(
                category: "EditorSave",
                "emergency recovery failed url=\(sourceURL.lastPathComponent) error=\(error.localizedDescription)"
            )
            return .failed
        }
    }

    private func serializedData(for note: NoteDocument) -> Data? {
        let yamlString = try? frontmatterParser.serialize(note.frontmatter)
        let rawContent: String
        if let yamlString, !yamlString.isEmpty {
            rawContent = "---\n\(yamlString)---\n\n\(note.body)"
        } else {
            rawContent = note.body
        }
        return rawContent.data(using: .utf8)
    }

    private func updateSavedContentHashes(for note: NoteDocument) {
        guard let data = serializedData(for: note) else { return }
        lastSavedContentHash = SHA256.hash(data: data)
        lastKnownDiskContentHash = lastSavedContentHash
    }

    nonisolated private static func createParentDirectoryIfNeeded(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private func isSafeEmergencyPrimaryWriteURL(_ url: URL) -> Bool {
        guard let vaultRootURL else { return false }
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let canonicalVaultRoot = CanonicalNoteIdentity.canonicalFileURL(for: vaultRootURL)
        guard canonicalURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else {
            return false
        }

        let rootComponents = canonicalVaultRoot.standardizedFileURL.pathComponents
        let noteComponents = canonicalURL.standardizedFileURL.pathComponents
        guard noteComponents.count > rootComponents.count else { return false }
        return zip(rootComponents, noteComponents).allSatisfy(==)
    }

    nonisolated private static func writeEmergencyRecoveryCopy(data: Data, sourceURL: URL, textLength: Int) throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = appSupport
            .appending(path: "olli.QuartzNotes", directoryHint: .isDirectory)
            .appending(path: "EmergencySaves", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let sourceName = sanitizedRecoveryFileStem(sourceURL.deletingPathExtension().lastPathComponent)
        let fileName = "\(timestamp)__\(UUID().uuidString)__\(sourceName)__\(textLength)chars.md"
        let recoveryURL = directory.appending(path: fileName)
        try data.write(to: recoveryURL, options: .withoutOverwriting)
        pruneEmergencyRecoveryCopies(in: directory, keeping: maxEmergencyRecoveryCopies)
        return recoveryURL
    }

    nonisolated private static func pruneEmergencyRecoveryCopies(in directory: URL, keeping maximumCount: Int) {
        guard maximumCount > 0,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ),
              files.count > maximumCount else {
            return
        }

        let sortedFiles = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
            return lhsDate < rhsDate
        }
        let excessCount = files.count - maximumCount
        for staleURL in sortedFiles.prefix(excessCount) {
            try? FileManager.default.removeItem(at: staleURL)
        }
        QuartzDiagnostics.warning(
            category: "EditorSave",
            "emergency recovery copies pruned count=\(excessCount) remainingLimit=\(maximumCount)"
        )
    }

    nonisolated private static func sanitizedRecoveryFileStem(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String((sanitized.isEmpty ? "note" : sanitized).prefix(80))
    }

    private func isCoordinationTimeout(_ error: Error) -> Bool {
        if let writerError = error as? CoordinatedFileWriterError,
           case .timeout = writerError {
            return true
        }
        if let fileError = error as? FileSystemError,
           case .iCloudTimeout = fileError {
            return true
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("File coordination timed out")
    }

    private func postSaveHealthChanged(state: String, url: URL, error: Error? = nil) {
        var userInfo: [AnyHashable: Any] = [
            "state": state,
            "url": url,
            "consecutiveFailures": consecutiveSaveFailures
        ]
        if let error {
            userInfo["error"] = error.localizedDescription
        }
        NotificationCenter.default.post(
            name: .quartzEditorSaveHealthChanged,
            object: url,
            userInfo: userInfo
        )
    }

    // MARK: - Word Count

    private func scheduleWordCountUpdate() {
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let text = self.currentText
            self.wordCount = Self.countWords(in: text)
        }
    }

    private static func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private func cancelTransientTasksPreservingWatchers() {
        autosaveTask?.cancel()
        autosaveTask = nil
        highlightTask?.cancel()
        highlightTask = nil
        wordCountTask?.cancel()
        wordCountTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        referenceInspectorTask?.cancel()
        referenceInspectorTask = nil
        inlineAITask?.cancel()
        inlineAITask = nil
        postLoadTask?.cancel()
        postLoadTask = nil
    }

    nonisolated private func currentDiskContentHash(for url: URL) -> SHA256Digest? {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard let data = try? Data(contentsOf: canonicalURL) else { return nil }
        return SHA256.hash(data: data)
    }

    private func updateKnownDiskContentHash(for url: URL) {
        lastKnownDiskContentHash = currentDiskContentHash(for: url)
    }

    private func refreshKnownDiskContentHashAsync(for url: URL) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        diskHashRefreshTask?.cancel()
        diskHashRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let hash = self?.currentDiskContentHash(for: canonicalURL)
            await MainActor.run { [weak self] in
                guard let self,
                      self.note?.fileURL == canonicalURL else { return }
                self.lastKnownDiskContentHash = hash
            }
        }
    }

    private func handleDetectedExternalChange(at url: URL, diskHash: SHA256Digest?) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard note?.fileURL == canonicalURL else { return }

        if let diskHash {
            if diskHash == lastKnownDiskContentHash {
                return
            }
            if diskHash == lastSavedContentHash {
                lastKnownDiskContentHash = diskHash
                return
            }
        }

        if isDirty {
            pendingExternalChangeIdentity = note?.id
            externalModificationDetected = true
            return
        }

        Task { await reloadFromDisk(preservingViewState: true) }
    }

    // MARK: - Analysis (Inspector Data)

    /// Schedules a debounced analysis pass for headings, stats, and link suggestions.
    /// Cancels any in-flight analysis to avoid 50 concurrent parses.
    private func scheduleAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.analysisDelay)
            guard !Task.isCancelled else { return }

            let text = self.currentText
            let noteURL = self.note?.fileURL
            let tree = self.fileTree

            // 1. Standard analysis (headings, stats)
            let analysis = await self.analysisService.analyze(text)

            // 2. Link suggestions (unlinked mentions)
            var suggestions: [LinkSuggestionService.Suggestion] = []
            if let noteURL {
                let suggestionService = LinkSuggestionService()
                let graphEdgeStore = self.graphEdgeStore
                suggestions = await Task.detached(priority: .utility) {
                    await suggestionService.suggestLinks(
                        for: text,
                        currentNoteURL: noteURL,
                        allNotes: tree,
                        graphEdgeStore: graphEdgeStore
                    )
                }.value
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.inspectorStore.updateStats(analysis.stats)
                self?.inspectorStore.suggestedLinks = suggestions
            }
        }
    }

    // MARK: - Scroll Sync

    /// Called by the text view scroll delegate when the viewport changes.
    /// Updates the inspector's active heading highlight.
    public func viewportDidScroll(topCharacterOffset: Int) {
        inspectorStore.updateActiveHeading(forCharacterOffset: topCharacterOffset)
    }

    /// Scrolls the editor to a specific heading (called when user taps ToC item).
    public func scrollToHeading(_ heading: HeadingItem) {
        let targetRange = resolvedHeadingNavigationRange(for: heading)
            ?? lineRange(containing: heading.characterOffset)
            ?? NSRange(location: heading.characterOffset, length: 0)

        inspectorStore.activeHeadingID = heading.id
        selectAndRevealEditorRange(targetRange, focusEditor: true)
    }

    /// Reveals a resolved note-local navigation range in the mounted editor.
    /// Used by inspector backlinks and other cross-note navigation requests.
    public func revealNavigationRange(_ range: NSRange, focusEditor: Bool = true) {
        let textLength = (currentText as NSString).length
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), max(0, textLength - location))
        selectAndRevealEditorRange(NSRange(location: location, length: length), focusEditor: focusEditor)
    }

    // MARK: - File Watching

    private func startFileWatching(for url: URL) {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        stopFileWatching()

        // Start NSFilePresenter for iCloud-coordinated change detection.
        // This is the primary monitor — it receives all coordinated writes
        // from iCloud daemon, Finder, and other processes.
        filePresenter = NoteFilePresenter(url: canonicalURL, delegate: self)

        // Only use DispatchSource (FileWatcher) for non-iCloud vaults.
        // For iCloud vaults, NSFilePresenter is sufficient and avoids
        // dual-monitoring race conditions (double reload, echo after save).
        let isICloudVault = canonicalURL.path(percentEncoded: false).contains("Mobile Documents")
        guard !isICloudVault else { return }

        let watcher = FileWatcher(url: canonicalURL)
        fileWatchTask = Task { [weak self] in
            let stream = await watcher.startWatching()
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.handleFileChange(event)
            }
        }
    }

    private func stopFileWatching() {
        fileWatchTask?.cancel()
        fileWatchTask = nil

        // Invalidate the file presenter
        filePresenter?.invalidate()
        filePresenter = nil
    }

    private func handleFileChange(_ event: FileChangeEvent) {
        // Ignore file changes during version restore to prevent spurious warnings
        guard !isRestoringVersion else { return }
        // Fast-path: ignore file changes that we triggered by saving
        guard !isSavingToFileSystem else { return }

        switch event {
        case .modified:
            guard let noteURL = note?.fileURL else { return }
            handleDetectedExternalChange(
                at: noteURL,
                diskHash: currentDiskContentHash(for: noteURL)
            )
        case .deleted:
            errorMessage = String(localized: "Note was deleted externally.", bundle: .module)
        case .created:
            break
        }
    }

    // MARK: - Wiki-Link Navigation

    /// Set when the user clicks a wiki-link in the editor.
    /// The view layer observes this and navigates to the linked note.
    public var wikiLinkNavigationRequest: WikiLinkNavigationRequest?

    /// Resolves a wiki-link title to a file URL.
    /// Uses GraphEdgeStore (which delegates to GraphIdentityResolver) for robust
    /// resolution supporting aliases, frontmatter titles, and path-qualified links.
    /// Falls back to simple file tree matching if graph edge store not configured.
    public func resolveWikiLink(title: String) async -> URL? {
        // Prefer the canonical graph-based resolver (supports aliases, frontmatter titles, paths)
        if let store = graphEdgeStore {
            if let url = await store.resolveTitle(title) {
                return url
            }
        }

        // Fallback to simple file tree matching
        let target = title.lowercased().trimmingCharacters(in: .whitespaces)
        for node in fileTree {
            if let url = findNoteURL(matching: target, in: node) {
                return url
            }
        }
        return nil
    }

    /// Triggers navigation to a wiki-link destination.
    /// Posts a notification that the app shell can observe to open the note.
    public func navigateToWikiLink(title: String) {
        Task {
            guard let url = await resolveWikiLink(title: title) else {
                errorMessage = String(localized: "Note \"\(title)\" not found in vault.", bundle: .module)
                return
            }
            let request = WikiLinkNavigationRequest(title: title, url: url)
            wikiLinkNavigationRequest = request
            NotificationCenter.default.post(
                name: .quartzWikiLinkNavigation,
                object: nil,
                userInfo: request.notificationUserInfo
            )
        }
    }

    public func prepareNoteNavigation(_ request: WikiLinkNavigationRequest) {
        pendingNoteNavigationRequest = request.canonicalized()
    }

    private func findNoteURL(matching target: String, in node: FileNode) -> URL? {
        let nodeName = node.url.deletingPathExtension().lastPathComponent.lowercased()
        if nodeName == target && node.url.pathExtension == "md" {
            return node.url
        }
        for child in node.children ?? [] {
            if let found = findNoteURL(matching: target, in: child) {
                return found
            }
        }
        return nil
    }

    private func applyPendingNoteNavigationIfNeeded(for loadedURL: URL) {
        guard let request = pendingNoteNavigationRequest?.canonicalized(),
              request.url == CanonicalNoteIdentity.canonicalFileURL(for: loadedURL) else {
            return
        }

        pendingNoteNavigationRequest = nil
        guard let selectionRange = request.selectionRange else { return }
        revealNavigationRange(selectionRange)
    }

    // MARK: - Cleanup

    public func cancelAllTasks() {
        autosaveTask?.cancel()
        highlightTask?.cancel()
        fileWatchTask?.cancel()
        wordCountTask?.cancel()
        analysisTask?.cancel()
        referenceInspectorTask?.cancel()
        inlineAITask?.cancel()
        diskHashRefreshTask?.cancel()
        postLoadTask?.cancel()
    }

    // MARK: - Inline AI

    /// Stored for deinit cleanup of inline AI work.
    nonisolated(unsafe) private var inlineAITask: Task<Void, Never>?

    /// State for the inline AI operation — observed by the UI for loading/error display.
    public private(set) var isInlineAIProcessing: Bool = false
    public var inlineAIError: OnDeviceWritingToolsService.AIError?

    /// Invokes the dual-path inline AI (custom provider → Apple Intelligence → error).
    /// Replaces the current selection with the AI result via `applyExternalEdit` for proper undo.
    public func invokeInlineAI(instruction: String) {
        let range = cursorPosition
        guard range.length > 0 else { return }

        let nsText = currentText as NSString
        guard range.location + range.length <= nsText.length else { return }

        let selectedText = nsText.substring(with: range)
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isInlineAIProcessing = true
        inlineAIError = nil

        inlineAITask?.cancel()
        inlineAITask = Task { [weak self] in
            let service = OnDeviceWritingToolsService()
            do {
                let result = try await service.invokeInlineAI(
                    instruction: instruction,
                    selectedText: selectedText
                )
                guard !Task.isCancelled, let self else { return }
                self.applyExternalEdit(
                    replacement: result,
                    range: range,
                    cursorAfter: NSRange(
                        location: range.location + (result as NSString).length,
                        length: 0
                    ),
                    origin: .aiInsert
                )
                self.isInlineAIProcessing = false
            } catch let error as OnDeviceWritingToolsService.AIError {
                guard !Task.isCancelled, let self else { return }
                self.inlineAIError = error
                self.isInlineAIProcessing = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.inlineAIError = .processingFailed(error.localizedDescription)
                self.isInlineAIProcessing = false
            }
        }
    }

    // MARK: - Selection Helpers

    /// Returns the currently selected text, or nil if no selection.
    public func getSelectedText() -> String? {
        let range = cursorPosition
        guard range.length > 0 else { return nil }

        let nsText = currentText as NSString
        guard range.location + range.length <= nsText.length else { return nil }

        let text = nsText.substring(with: range)
        return text.isEmpty ? nil : text
    }

    /// Replaces the current selection with new text via `applyExternalEdit`
    /// for proper UndoManager registration and AST highlighter stability.
    public func replaceSelection(with newText: String) {
        let range = cursorPosition
        guard range.length > 0 else { return }

        let nsText = currentText as NSString
        guard range.location + range.length <= nsText.length else { return }

        applyExternalEdit(
            replacement: newText,
            range: range,
            cursorAfter: NSRange(
                location: range.location + (newText as NSString).length,
                length: 0
            )
        )
    }

    // MARK: - Wiki-Link Insertion

    public func handleLinkInsertionMoveUp() -> Bool {
        guard linkInsertion.isPresented else { return false }
        linkInsertion.moveSelection(delta: -1)
        return true
    }

    public func handleLinkInsertionMoveDown() -> Bool {
        guard linkInsertion.isPresented else { return false }
        linkInsertion.moveSelection(delta: 1)
        return true
    }

    public func handleLinkInsertionConfirm() -> Bool {
        guard linkInsertion.isPresented else { return false }
        guard let suggestion = linkInsertion.selectedSuggestion else {
            return dismissLinkInsertion()
        }
        insertWikiLinkSuggestion(suggestion)
        return true
    }

    public func dismissLinkInsertion() -> Bool {
        guard linkInsertion.isPresented else { return false }
        let shouldRestoreEditorFocus = linkInsertion.shouldRestoreEditorFocusOnDismiss
        linkInsertion.dismiss()
        if shouldRestoreEditorFocus {
            focusActiveTextViewPreservingSelection()
        }
        return true
    }

    public func insertWikiLinkSuggestion(_ suggestion: InEditorLinkInsertionState.Suggestion) {
        guard let triggerRange = linkInsertion.triggerRange else { return }
        let replacement = "[[\(suggestion.insertableTarget)]]"
        let cursorAfter = NSRange(location: triggerRange.location + (replacement as NSString).length, length: 0)
        let shouldRestoreEditorFocus = linkInsertion.shouldRestoreEditorFocusOnDismiss
        linkInsertion.dismiss()

        applyExternalEdit(
            replacement: replacement,
            range: triggerRange,
            cursorAfter: cursorAfter,
            origin: .formatting
        )

        if shouldRestoreEditorFocus {
            focusActiveTextViewPreservingSelection()
        }
    }

    public func linkSuggestedMention(_ suggestion: LinkSuggestionService.Suggestion) {
        guard note != nil else { return }

        let nsText = currentText as NSString
        guard suggestion.matchRange.location >= 0,
              NSMaxRange(suggestion.matchRange) <= nsText.length else {
            return
        }

        let catalog = NoteReferenceCatalog(allNotes: fileTree)
        guard let target = catalog.suggestion(for: suggestion.noteURL) else { return }

        let currentMentionText = nsText.substring(with: suggestion.matchRange)
        let replacement: String
        if currentMentionText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == target.insertableTarget.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) {
            replacement = "[[\(target.insertableTarget)]]"
        } else {
            replacement = "[[\(target.insertableTarget)|\(currentMentionText)]]"
        }

        let replacementLength = (replacement as NSString).length
        let remappedSelection = selectionAfterReplacingRange(
            suggestion.matchRange,
            replacementLength: replacementLength,
            preserving: resolvedFormattingSelection()
        )

        applyExternalEdit(
            replacement: replacement,
            range: suggestion.matchRange,
            cursorAfter: remappedSelection,
            origin: .formatting
        )
    }

    // MARK: - In-Note Find / Replace

    /// Presents the editor-scoped find UI for the current note.
    /// Search never escapes the active note/editor session.
    public func presentInNoteSearch() {
        guard note != nil else { return }
        inNoteSearch.beginPresentation(
            selection: resolvedFormattingSelection(),
            shouldRestoreEditorFocusOnDismiss: activeTextViewIsFirstResponder
        )
        refreshInNoteSearchResultsForCurrentEditorState(revealSelection: false, focusEditor: false)
    }

    /// Dismisses the editor-scoped find UI and restores editor usage if the
    /// editor owned first responder before the find UI was presented.
    public func dismissInNoteSearch() {
        let restoreSelection = inNoteSearch.currentMatch == nil ? inNoteSearch.selectionBeforePresentation : nil
        let shouldRestoreEditorFocus = inNoteSearch.shouldRestoreEditorFocusOnDismiss
        inNoteSearch.dismiss()

        if let restoreSelection {
            selectAndRevealEditorRange(restoreSelection, focusEditor: shouldRestoreEditorFocus)
        } else if shouldRestoreEditorFocus {
            focusActiveTextViewPreservingSelection()
        }
    }

    public func toggleInNoteReplaceControls() {
        inNoteSearch.isReplaceVisible.toggle()
    }

    public func setInNoteSearchQuery(_ query: String) {
        inNoteSearch.query = query

        guard !query.isEmpty else {
            inNoteSearch.clearMatches()
            if let selectionBeforePresentation = inNoteSearch.selectionBeforePresentation {
                selectAndRevealEditorRange(selectionBeforePresentation, focusEditor: false)
            }
            return
        }

        refreshInNoteSearchResults(
            preferredRange: resolvedFormattingSelection(),
            preferredLocation: resolvedFormattingSelection().location,
            revealSelection: true,
            focusEditor: false
        )
    }

    public func setInNoteReplaceText(_ replacement: String) {
        inNoteSearch.replacement = replacement
    }

    public func setInNoteSearchCaseSensitive(_ isCaseSensitive: Bool) {
        inNoteSearch.isCaseSensitive = isCaseSensitive
        refreshInNoteSearchResults(
            preferredRange: resolvedFormattingSelection(),
            preferredLocation: resolvedFormattingSelection().location,
            revealSelection: inNoteSearch.hasQuery,
            focusEditor: false
        )
    }

    public func findNextInNote() {
        guard let nextIndex = nextInNoteSearchMatchIndex(direction: .forward) else { return }
        inNoteSearch.updateMatches(inNoteSearch.matches, currentMatchIndex: nextIndex)
        selectAndRevealEditorRange(inNoteSearch.matches[nextIndex], focusEditor: true)
    }

    public func findPreviousInNote() {
        guard let previousIndex = nextInNoteSearchMatchIndex(direction: .backward) else { return }
        inNoteSearch.updateMatches(inNoteSearch.matches, currentMatchIndex: previousIndex)
        selectAndRevealEditorRange(inNoteSearch.matches[previousIndex], focusEditor: true)
    }

    public func replaceCurrentInNote() {
        guard !inNoteSearch.query.isEmpty else { return }

        refreshInNoteSearchResultsForCurrentEditorState(revealSelection: false, focusEditor: false)
        guard let currentMatch = inNoteSearch.currentMatch else { return }

        let replacement = inNoteSearch.replacement
        let replacementLength = (replacement as NSString).length
        let nextAnchor = currentMatch.location + replacementLength

        applyExternalEdit(
            replacement: replacement,
            range: currentMatch,
            cursorAfter: NSRange(location: nextAnchor, length: 0),
            origin: .formatting
        )

        refreshInNoteSearchResults(
            preferredRange: nil,
            preferredLocation: nextAnchor,
            revealSelection: true,
            focusEditor: true
        )
    }

    public func replaceAllInNote() {
        guard !inNoteSearch.query.isEmpty else { return }

        let matches = InNoteSearchState.computeMatches(
            in: currentText,
            query: inNoteSearch.query,
            isCaseSensitive: inNoteSearch.isCaseSensitive
        )
        guard !matches.isEmpty else {
            inNoteSearch.clearMatches()
            return
        }

        let replacement = inNoteSearch.replacement
        let replacementLength = (replacement as NSString).length
        let previousSelection = resolvedFormattingSelection()
        let rebuiltText = InNoteSearchState.replacingMatches(
            in: currentText,
            matches: matches,
            replacement: replacement
        )

        guard rebuiltText != currentText else {
            refreshInNoteSearchResults(
                preferredRange: previousSelection,
                preferredLocation: previousSelection.location,
                revealSelection: true,
                focusEditor: true
            )
            return
        }

        let remappedLocation = remappedSelectionLocation(
            from: previousSelection.location,
            replacingMatches: matches,
            replacementLength: replacementLength
        )

        applyExternalEdit(
            replacement: rebuiltText,
            range: NSRange(location: 0, length: (currentText as NSString).length),
            cursorAfter: NSRange(location: remappedLocation, length: 0),
            origin: .formatting
        )

        refreshInNoteSearchResults(
            preferredRange: nil,
            preferredLocation: remappedLocation,
            revealSelection: true,
            focusEditor: true
        )
    }

    // MARK: - Helpers

    private enum InNoteSearchDirection {
        case forward
        case backward
    }

    private func refreshInNoteSearchResultsForCurrentEditorState(
        revealSelection: Bool,
        focusEditor: Bool
    ) {
        guard inNoteSearch.isPresented else { return }
        let selection = resolvedFormattingSelection()
        refreshInNoteSearchResults(
            preferredRange: selection,
            preferredLocation: selection.location,
            revealSelection: revealSelection,
            focusEditor: focusEditor
        )
    }

    private func refreshInNoteSearchResults(
        preferredRange: NSRange?,
        preferredLocation: Int?,
        revealSelection: Bool,
        focusEditor: Bool
    ) {
        let query = inNoteSearch.query
        guard inNoteSearch.isPresented else { return }
        guard !query.isEmpty else {
            inNoteSearch.clearMatches()
            return
        }

        let matches = InNoteSearchState.computeMatches(
            in: currentText,
            query: query,
            isCaseSensitive: inNoteSearch.isCaseSensitive
        )

        let resolvedIndex = resolvedInNoteSearchMatchIndex(
            matches: matches,
            preferredRange: preferredRange,
            preferredLocation: preferredLocation
        )
        inNoteSearch.updateMatches(matches, currentMatchIndex: resolvedIndex)

        guard revealSelection,
              let resolvedIndex,
              matches.indices.contains(resolvedIndex) else { return }
        selectAndRevealEditorRange(matches[resolvedIndex], focusEditor: focusEditor)
    }

    private func resolvedInNoteSearchMatchIndex(
        matches: [NSRange],
        preferredRange: NSRange?,
        preferredLocation: Int?
    ) -> Int? {
        guard !matches.isEmpty else { return nil }

        if let currentMatch = inNoteSearch.currentMatch,
           let existingIndex = matches.firstIndex(where: { NSEqualRanges($0, currentMatch) }) {
            return existingIndex
        }

        if let preferredRange,
           let exactIndex = matches.firstIndex(where: { NSEqualRanges($0, preferredRange) }) {
            return exactIndex
        }

        if let preferredRange,
           let intersectingIndex = matches.firstIndex(where: { NSIntersectionRange($0, preferredRange).length > 0 }) {
            return intersectingIndex
        }

        let anchor = preferredLocation ?? preferredRange?.location ?? cursorPosition.location

        if let containingIndex = matches.firstIndex(where: { $0.location <= anchor && anchor < NSMaxRange($0) }) {
            return containingIndex
        }

        if let followingIndex = matches.firstIndex(where: { $0.location >= anchor }) {
            return followingIndex
        }

        return 0
    }

    private func nextInNoteSearchMatchIndex(direction: InNoteSearchDirection) -> Int? {
        guard !inNoteSearch.query.isEmpty else { return nil }

        if inNoteSearch.matches.isEmpty {
            refreshInNoteSearchResultsForCurrentEditorState(revealSelection: false, focusEditor: false)
        }
        guard !inNoteSearch.matches.isEmpty else { return nil }

        let currentIndex = inNoteSearch.currentMatchIndex
            ?? resolvedInNoteSearchMatchIndex(
                matches: inNoteSearch.matches,
                preferredRange: resolvedFormattingSelection(),
                preferredLocation: resolvedFormattingSelection().location
            )

        switch direction {
        case .forward:
            return ((currentIndex ?? -1) + 1 + inNoteSearch.matches.count) % inNoteSearch.matches.count
        case .backward:
            return ((currentIndex ?? 0) - 1 + inNoteSearch.matches.count) % inNoteSearch.matches.count
        }
    }

    private func selectAndRevealEditorRange(_ range: NSRange, focusEditor: Bool) {
        applySelectionSnapshot(range, force: true)

        #if canImport(UIKit)
        guard let textView = activeTextView else {
            pendingRestoredSelection = range
            return
        }
        if focusEditor, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        if textView.selectedRange != range {
            textView.selectedRange = range
        }
        textView.scrollRangeToVisible(range)
        #elseif canImport(AppKit)
        guard let textView = activeTextView else {
            pendingRestoredSelection = range
            return
        }
        if focusEditor, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        if textView.selectedRange() != range {
            textView.setSelectedRange(range)
        }
        textView.scrollRangeToVisible(range)
        #endif
    }

    private func focusActiveTextViewPreservingSelection() {
        #if canImport(UIKit)
        if let textView = activeTextView, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        #elseif canImport(AppKit)
        if let textView = activeTextView, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        #endif
    }

    private func remappedSelectionLocation(
        from originalLocation: Int,
        replacingMatches matches: [NSRange],
        replacementLength: Int
    ) -> Int {
        var delta = 0
        for match in matches {
            if match.location >= originalLocation { break }
            delta += replacementLength - match.length
        }
        return max(0, originalLocation + delta)
    }

    private func selectionAfterReplacingRange(
        _ replacedRange: NSRange,
        replacementLength: Int,
        preserving selection: NSRange
    ) -> NSRange {
        let replacementRange = NSRange(location: replacedRange.location, length: replacementLength)

        if NSIntersectionRange(selection, replacedRange).length > 0 {
            return NSRange(location: NSMaxRange(replacementRange), length: 0)
        }

        if selection.location >= NSMaxRange(replacedRange) {
            let delta = replacementLength - replacedRange.length
            return NSRange(location: max(0, selection.location + delta), length: selection.length)
        }

        return selection
    }

    private struct ActiveWikiLinkTriggerContext {
        let triggerRange: NSRange
        let query: String
    }

    private func refreshLinkInsertionSuggestionsForCurrentEditorState() {
        refreshLinkInsertionSuggestions(for: currentSelectedRangeFromActiveTextView())
    }

    private func refreshLinkInsertionSuggestions(for selection: NSRange) {
        guard note != nil else {
            linkInsertion.dismiss()
            return
        }

        guard let trigger = activeWikiLinkTriggerContext(for: selection) else {
            if linkInsertion.isPresented {
                linkInsertion.dismiss()
            }
            return
        }

        let catalog = NoteReferenceCatalog(allNotes: fileTree)
        let suggestions = catalog
            .linkInsertionSuggestions(matching: trigger.query, excluding: note?.fileURL)
            .prefix(8)
            .map {
                InEditorLinkInsertionState.Suggestion(
                    noteURL: $0.noteURL,
                    noteName: $0.noteName,
                    insertableTarget: $0.insertableTarget
                )
            }

        linkInsertion.presentOrUpdate(
            triggerRange: trigger.triggerRange,
            query: trigger.query,
            suggestions: Array(suggestions),
            shouldRestoreEditorFocusOnDismiss: activeTextViewIsFirstResponder
        )
    }

    private func activeWikiLinkTriggerContext(for selection: NSRange) -> ActiveWikiLinkTriggerContext? {
        guard selection.length == 0 else { return nil }

        let nsText = currentText as NSString
        let cursorLocation = min(max(0, selection.location), nsText.length)
        guard cursorLocation <= nsText.length else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let linePrefixLength = cursorLocation - lineRange.location
        guard linePrefixLength >= 2 else { return nil }

        let linePrefixRange = NSRange(location: lineRange.location, length: linePrefixLength)
        let linePrefix = nsText.substring(with: linePrefixRange)
        guard let trigger = linePrefix.range(of: "[[", options: .backwards) else { return nil }

        let queryStartInLine = trigger.upperBound.utf16Offset(in: linePrefix)
        let queryLength = linePrefixRange.length - queryStartInLine
        guard queryLength >= 0 else { return nil }

        let query = nsText.substring(with: NSRange(
            location: lineRange.location + queryStartInLine,
            length: queryLength
        ))
        guard !query.contains("]]"),
              !query.contains("\n"),
              !query.contains("\r"),
              !query.contains("|"),
              !query.contains("#") else {
            return nil
        }

        let triggerLocation = lineRange.location + trigger.lowerBound.utf16Offset(in: linePrefix)
        return ActiveWikiLinkTriggerContext(
            triggerRange: NSRange(location: triggerLocation, length: cursorLocation - triggerLocation),
            query: query
        )
    }

    private func scheduleExplicitRelationshipRefresh(
        forceGraphPublish: Bool = false,
        sourceURL: URL? = nil,
        content: String? = nil
    ) {
        referenceInspectorTask?.cancel()

        guard let resolvedSourceURL = sourceURL ?? note?.fileURL else {
            inspectorStore.setOutgoingLinks([])
            return
        }

        let noteIdentity = note?.id
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: resolvedSourceURL)
        let textSnapshot = content ?? currentText
        let treeSnapshot = fileTree
        let edgeStore = graphEdgeStore

        referenceInspectorTask = Task { [weak self] in
            guard let self else { return }
            let catalog = NoteReferenceCatalog(allNotes: treeSnapshot)
            let references = await catalog.resolvedExplicitReferences(
                in: textSnapshot,
                sourceNoteURL: canonicalSourceURL,
                graphEdgeStore: edgeStore
            )
            guard !Task.isCancelled else { return }

            let outgoingLinks = self.outgoingLinkItems(from: references)
            var shouldPublishGraph = false

            await MainActor.run { [weak self] in
                guard let self,
                      self.note?.id == noteIdentity,
                      self.currentText == textSnapshot else { return }
                self.inspectorStore.setOutgoingLinks(outgoingLinks)
                if forceGraphPublish || self.lastPublishedExplicitReferences != references {
                    self.lastPublishedExplicitReferences = references
                    shouldPublishGraph = true
                }
            }

            guard shouldPublishGraph, let edgeStore else { return }
            await edgeStore.updateExplicitReferences(
                for: canonicalSourceURL,
                references: references
            )

            let resolvedTargets = Array(Set(references.map(\.targetNoteURL)))
            NotificationCenter.default.post(
                name: .quartzReferenceGraphDidChange,
                object: canonicalSourceURL,
                userInfo: ["targetURLs": resolvedTargets]
            )
        }
    }

    private func outgoingLinkItems(from references: [ExplicitNoteReference]) -> [InspectorStore.OutgoingLinkItem] {
        var seen: Set<URL> = []
        return references.compactMap { reference in
            guard seen.insert(reference.targetNoteURL).inserted else { return nil }
            return InspectorStore.OutgoingLinkItem(reference: reference)
        }
    }

    private func resolvedHeadingNavigationRange(for heading: HeadingItem) -> NSRange? {
        semanticDocument.blocks.first { block in
            guard case let .heading(level) = block.kind else { return false }
            return level == heading.level && block.range.location == heading.characterOffset
        }.map { block in
            let contentRange = headingContentRange(for: block)
            return contentRange.length > 0 ? contentRange : block.range
        }
    }

    private func authoritativeHeadingItems() -> [HeadingItem] {
        let nsText = currentText as NSString
        return semanticDocument.blocks.compactMap { block in
            guard case let .heading(level) = block.kind else { return nil }

            let contentRange = headingContentRange(for: block)
            guard contentRange.length > 0,
                  NSMaxRange(contentRange) <= nsText.length else {
                return nil
            }

            let headingText = nsText.substring(with: contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headingText.isEmpty else { return nil }

            return HeadingItem(
                id: "\(level)-\(headingText)-\(block.range.location)",
                level: level,
                text: headingText,
                characterOffset: block.range.location
            )
        }
    }

    private func headingContentRange(for block: EditorBlockNode) -> NSRange {
        guard case .heading = block.kind else { return block.contentRange }
        guard let syntaxRange = block.syntaxRange else { return block.contentRange }

        let contentStart = min(NSMaxRange(syntaxRange), NSMaxRange(block.contentRange))
        let contentLength = max(0, NSMaxRange(block.contentRange) - contentStart)
        if contentLength > 0 {
            return NSRange(location: contentStart, length: contentLength)
        }

        return block.contentRange
    }

    private func lineRange(containing location: Int) -> NSRange? {
        let nsText = currentText as NSString
        guard nsText.length > 0 else { return nil }
        let safeLocation = min(max(0, location), max(0, nsText.length - 1))
        return nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
    }

    private func overlayVisibilitySignature(for selection: NSRange) -> [String] {
        semanticDocument.revealedInlineTokenIDs(for: selection)
    }

    private func synchronizeSnapshotFromActiveTextView() {
        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        currentText = textView.text ?? ""
        applySelectionSnapshot(textView.selectedRange, force: true)
        #elseif canImport(AppKit)
        guard let textView = activeTextView else { return }
        currentText = textView.string
        applySelectionSnapshot(textView.selectedRange(), force: true)
        #endif

        synchronizeSemanticSnapshotFromCurrentText()
        formattingState = FormattingState.detect(
            in: currentText,
            semanticDocument: semanticDocument,
            at: cursorPosition.location
        )
        updateTypingAttributes()
    }

    private func synchronizeSemanticSnapshotFromCurrentText() {
        let spans = cachedHighlightSpansForCurrentText()
        semanticDocument = EditorSemanticDocument.build(markdown: currentText, spans: spans)
        if spans.isEmpty {
            lastRenderPlan = .empty
        }
    }

    private func cachedHighlightSpansForCurrentText() -> [HighlightSpan] {
        guard lastAppliedHighlightSourceText == currentText else { return [] }
        return lastAppliedHighlightSpans
    }

    private func rangeNeedsFullAttributeRewrite(
        _ storage: NSTextStorage,
        range: NSRange,
        targetAttrs: [NSAttributedString.Key: Any]
    ) -> Bool {
        var effectiveRange = NSRange(location: 0, length: 0)
        let existing = storage.attributes(at: range.location, effectiveRange: &effectiveRange)
        let fullyCovered = effectiveRange.location <= range.location
            && NSMaxRange(effectiveRange) >= NSMaxRange(range)

        return !fullyCovered || !primaryAttributesEqual(existing, targetAttrs)
    }

    private func primaryAttributesEqual(
        _ existing: [NSAttributedString.Key: Any],
        _ target: [NSAttributedString.Key: Any]
    ) -> Bool {
        #if canImport(UIKit)
        if !fontsEqual(existing[.font] as? UIFont, target[.font] as? UIFont) { return false }
        if !colorsEqual(existing[.foregroundColor] as? UIColor, target[.foregroundColor] as? UIColor) { return false }
        if !colorsEqual(existing[.backgroundColor] as? UIColor, target[.backgroundColor] as? UIColor) { return false }
        #elseif canImport(AppKit)
        if !fontsEqual(existing[.font] as? NSFont, target[.font] as? NSFont) { return false }
        if !colorsEqual(existing[.foregroundColor] as? NSColor, target[.foregroundColor] as? NSColor) { return false }
        if !colorsEqual(existing[.backgroundColor] as? NSColor, target[.backgroundColor] as? NSColor) { return false }
        #endif

        let existingParagraph = existing[.paragraphStyle] as? NSParagraphStyle
        let targetParagraph = target[.paragraphStyle] as? NSParagraphStyle
        if !(existingParagraph?.isEqual(targetParagraph) ?? (targetParagraph == nil)) { return false }

        if !numberAttributesEqual(existing[.strikethroughStyle], target[.strikethroughStyle]) { return false }
        if !numberAttributesEqual(existing[.quartzTableRowStyle], target[.quartzTableRowStyle]) { return false }
        if !numberAttributesEqual(existing[.underlineStyle], target[.underlineStyle]) { return false }
        if !numberAttributesEqual(existing[.kern], target[.kern]) { return false }

        let existingWikiLink = existing[.quartzWikiLink] as? String
        let targetWikiLink = target[.quartzWikiLink] as? String
        if existingWikiLink != targetWikiLink { return false }

        let existingAttachment = existing[.attachment] as? NSTextAttachment
        let targetAttachment = target[.attachment] as? NSTextAttachment
        if existingAttachment !== targetAttachment {
            if !(existingAttachment == nil && targetAttachment == nil) {
                return false
            }
        }

        return true
    }

    private func numberAttributesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs as NSNumber, rhs as NSNumber):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as CGFloat, rhs as CGFloat):
            return lhs == rhs
        default:
            return false
        }
    }

    #if canImport(UIKit)
    private func fontsEqual(_ a: UIFont?, _ b: UIFont?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.fontName == b.fontName && a.pointSize == b.pointSize
    }
    private func colorsEqual(_ a: UIColor?, _ b: UIColor?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a == b
    }
    #elseif canImport(AppKit)
    private func fontsEqual(_ a: NSFont?, _ b: NSFont?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.fontName == b.fontName && a.pointSize == b.pointSize
    }
    private func colorsEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a == b
    }
    #endif

    // MARK: - Syntax Visibility

    /// Adjusts an overlay color based on the current `syntaxVisibilityMode`.
    /// - `.full`: returns the color unchanged (tertiaryLabel).
    /// - `.gentleFade`: fades only concealable markdown syntax.
    /// - `.hiddenUntilCaret`: hides only concealable markdown syntax unless the
    ///   active selection is touching the owning semantic token.
    private func adjustedOverlayColor(
        _ color: PlatformColor,
        overlayVisibilityBehavior: OverlayVisibilityBehavior
    ) -> PlatformColor {
        switch syntaxVisibilityMode {
        case .full:
            return color
        case .gentleFade:
            switch overlayVisibilityBehavior {
            case .alwaysVisible:
                return color
            case .concealWhenInactive:
                return color.withAlphaComponent(0.4)
            }
        case .hiddenUntilCaret:
            switch overlayVisibilityBehavior {
            case .alwaysVisible:
                return color
            case let .concealWhenInactive(revealRange):
                if semanticDocument.selectionTouchesRevealRange(cursorPosition, revealRange: revealRange) {
                    return color
                }
            }
            #if canImport(UIKit)
            return UIColor.clear
            #elseif canImport(AppKit)
            return NSColor.clear
            #endif
        }
    }
}

// MARK: - Wiki-Link Navigation Types

/// Represents a pending wiki-link navigation request.
public struct WikiLinkNavigationRequest: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let url: URL
    public let selectionRange: NSRange?

    public init(title: String, url: URL, selectionRange: NSRange? = nil) {
        self.title = title
        self.url = CanonicalNoteIdentity.canonicalFileURL(for: url)
        self.selectionRange = selectionRange
    }

    public func canonicalized() -> WikiLinkNavigationRequest {
        WikiLinkNavigationRequest(title: title, url: url, selectionRange: selectionRange)
    }

    public var notificationUserInfo: [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "url": url,
            "title": title
        ]
        if let selectionRange {
            userInfo["selectionRange"] = NSStringFromRange(selectionRange)
        }
        return userInfo
    }
}

public extension Notification.Name {
    /// Posted when the user clicks a wiki-link in the editor.
    /// `userInfo` contains `"url": URL` and `"title": String`.
    static let quartzWikiLinkNavigation = Notification.Name("quartzWikiLinkNavigation")
}

// MARK: - NoteFilePresenterDelegate

extension EditorSession: NoteFilePresenterDelegate {

    /// Called when the file's contents have changed externally (iCloud sync, Finder, etc.).
    public func filePresenterDidDetectChange(_ presenter: NoteFilePresenter) {
        // Ignore during version restore
        guard !isRestoringVersion else { return }
        // Fast-path: ignore changes we triggered by saving
        guard !isSavingToFileSystem else { return }

        // Post notification so Intelligence Engine can re-index the file
        if let url = presenter.presentedItemURL {
            NotificationCenter.default.post(name: .quartzFilePresenterDidChange, object: url)
            handleDetectedExternalChange(at: url, diskHash: currentDiskContentHash(for: url))
        }
    }

    /// Called when the file has been moved or renamed.
    public func filePresenter(_ presenter: NoteFilePresenter, didMoveFrom oldURL: URL?, to newURL: URL) {
        let canonicalOldURL = oldURL.map(CanonicalNoteIdentity.canonicalFileURL(for:))
        let canonicalNewURL = CanonicalNoteIdentity.canonicalFileURL(for: newURL)

        if let canonicalOldURL,
           let viewState = noteViewStateByURL.removeValue(forKey: canonicalOldURL) {
            noteViewStateByURL[canonicalNewURL] = viewState
        }

        if pendingExternalChangeIdentity?.fileURL == canonicalOldURL {
            pendingExternalChangeIdentity = CanonicalNoteIdentity(fileURL: canonicalNewURL)
        }

        // Update our note reference
        if var currentNote = note {
            currentNote.fileURL = canonicalNewURL
            note = currentNote
        }

        startFileWatching(for: canonicalNewURL)
        updateKnownDiskContentHash(for: canonicalNewURL)

        // Publish via typed event bus (new pattern per CODEX.md F4)
        if let canonicalOldURL {
            Task {
                await DomainEventBus.shared.publish(.noteRelocated(from: canonicalOldURL, to: canonicalNewURL))
            }
        }

        // Legacy NotificationCenter for backward compatibility
        NotificationCenter.default.post(
            name: .quartzFilePresenterDidMove,
            object: nil,
            userInfo: ["oldURL": canonicalOldURL as Any, "newURL": canonicalNewURL]
        )
        NotificationCenter.default.post(
            name: .quartzSpotlightNoteRelocated,
            object: nil,
            userInfo: ["old": canonicalOldURL as Any, "new": canonicalNewURL]
        )
    }

    /// Called before the file is deleted.
    public func filePresenterWillDelete(_ presenter: NoteFilePresenter) async throws {
        // Publish via typed event bus (new pattern per CODEX.md F4)
        if let url = presenter.presentedItemURL {
            await DomainEventBus.shared.publish(.noteDeleted(url: url))
        }

        // Legacy NotificationCenter for backward compatibility
        if let url = presenter.presentedItemURL {
            NotificationCenter.default.post(name: .quartzFilePresenterWillDelete, object: url)
        }

        // Update UI
        errorMessage = String(localized: "Note was deleted externally.", bundle: .module)
    }

    /// Called when we should save pending changes before another process writes.
    ///
    /// **Critical**: When `savePresentedItemChanges` is called by the system,
    /// NSFileCoordinator already holds a lock on the file. We MUST NOT create
    /// another NSFileCoordinator here — that would self-coordinate and deadlock.
    /// Instead, write directly to the file using atomic Data.write().
    public func filePresenterShouldSave(_ presenter: NoteFilePresenter) async throws {
        guard let currentNote = note, isDirty else { return }

        // Snapshot from native view (the source of truth)
        let textSnapshot: String
        #if canImport(UIKit)
        textSnapshot = activeTextView?.text ?? currentText
        #elseif canImport(AppKit)
        textSnapshot = activeTextView?.string ?? currentText
        #endif

        var noteToSave = currentNote
        noteToSave.body = textSnapshot
        noteToSave.frontmatter.modifiedAt = .now

        // Serialize frontmatter
        let yamlString = try frontmatterParser.serialize(noteToSave.frontmatter)
        let rawContent: String
        if yamlString.isEmpty {
            rawContent = noteToSave.body
        } else {
            rawContent = "---\n\(yamlString)---\n\n\(noteToSave.body)"
        }

        guard let data = rawContent.data(using: .utf8) else { return }

        // Write DIRECTLY — the system already holds coordination for this file.
        // Creating a new NSFileCoordinator here would deadlock (Apple TN3151).
        try data.write(to: noteToSave.fileURL, options: .atomic)

        // Update echo suppression hash so file watcher ignores our own write
        lastSavedContentHash = SHA256.hash(data: data)
        lastKnownDiskContentHash = lastSavedContentHash

        note = noteToSave
        if currentText == textSnapshot {
            isDirty = false
        }
    }
}
