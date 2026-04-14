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

    // MARK: - State (read by UI, never written back by SwiftUI)

    /// The note currently loaded in this session.
    public private(set) var note: NoteDocument?

    /// Current text content — READ-ONLY snapshot for consumers (autosave, word count).
    /// Updated only by delegate callbacks, never by SwiftUI bindings.
    public private(set) var currentText: String = ""

    /// Current cursor/selection range — updated by delegate callbacks.
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

    /// Current formatting state at the cursor position (for toolbar active states).
    public private(set) var formattingState: FormattingState = .empty

    /// Root URL of the current vault.
    public var vaultRootURL: URL?

    /// File tree snapshot for link suggestions.
    public var fileTree: [FileNode] = []

    /// Set when an external modification is detected while the user has unsaved edits.
    public var externalModificationDetected: Bool = false

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

    /// SHA-256 hash of the last content we wrote to disk.
    /// Used for content-based echo suppression (replaces timing-based guard).
    private var lastSavedContentHash: SHA256Digest?

    // MARK: - Restoration Readiness (F8 fix)

    /// True when the editor is ready for cursor/scroll restoration.
    /// Set after `loadNote` completes and text view is populated.
    /// **Per CODEX.md F8:** Replaces timing-based restoration with explicit handshake.
    public private(set) var isReadyForRestoration: Bool = false

    /// Continuations waiting for restoration readiness.
    /// Multiple callers can await readiness; all are resumed when ready.
    private var readinessContinuations: [CheckedContinuation<Void, Never>] = []

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
    private var autosaveTask: Task<Void, Never>?
    private var fileWatchTask: Task<Void, Never>?
    private var wordCountTask: Task<Void, Never>?

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
    private var analysisTask: Task<Void, Never>?

    /// Delay before running analysis (longer than highlighting since ToC doesn't need keystroke-level updates).
    private let analysisDelay: Duration = .milliseconds(300)

    private let autosaveDelay: Duration = .seconds(1)

    // MARK: - Version History Throttle

    /// Minimum interval between version snapshots (5 minutes).
    private static let versionSnapshotInterval: TimeInterval = 300

    /// Last time a version snapshot was saved for the current note.
    private var lastSnapshotDate: Date?

    // MARK: - Init

    /// Graph edge store for resolving semantic links in the inspector.
    public var graphEdgeStore: GraphEdgeStore?

    /// Stored notification tokens removed during teardown.
    private var semanticLinkObserver: Any?
    private var conceptObserver: Any?
    private var scanProgressObserver: Any?

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing, inspectorStore: InspectorStore) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
        self.inspectorStore = inspectorStore
        startSemanticLinkObserver()
        startConceptObserver()
        startScanProgressObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            autosaveTask?.cancel()
            highlightTask?.cancel()
            fileWatchTask?.cancel()
            wordCountTask?.cancel()
            analysisTask?.cancel()
            inlineAITask?.cancel()

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
    }

    /// Listens for `.quartzSemanticLinksUpdated` and refreshes the inspector's related notes.
    private func startSemanticLinkObserver() {
        semanticLinkObserver = NotificationCenter.default.addObserver(
            forName: .quartzSemanticLinksUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let updatedURL = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                guard let self, updatedURL == self.note?.fileURL else { return }
                await self.refreshSemanticLinks()
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
            guard let updatedURL = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                guard let self, updatedURL == self.note?.fileURL else { return }
                await self.refreshConcepts()
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

    /// Fetches semantic links from the edge store and updates the inspector.
    public func refreshSemanticLinks() async {
        guard let noteURL = note?.fileURL,
              let edgeStore = graphEdgeStore else {
            inspectorStore.relatedNotes = []
            return
        }
        let related = await edgeStore.semanticRelations(for: noteURL)
        inspectorStore.relatedNotes = related.map { url in
            (url: url, title: url.deletingPathExtension().lastPathComponent)
        }
        // Also refresh concepts while we're at it
        await refreshConcepts()
    }

    /// Fetches AI concepts from the edge store and updates the inspector.
    public func refreshConcepts() async {
        guard let noteURL = note?.fileURL,
              let edgeStore = graphEdgeStore else {
            inspectorStore.aiConcepts = []
            return
        }
        inspectorStore.aiConcepts = await edgeStore.concepts(for: noteURL)
    }

    // MARK: - Note Loading

    /// Loads a note from the file system into the existing session.
    /// Reuses the mounted text view — no view destruction.
    public func loadNote(at url: URL) async {
        // Reset readiness state for new note (F8 handshake)
        resetReadinessState()

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
            let loaded = try await vaultProvider.readNote(at: url)
            note = loaded
            currentText = loaded.body
            isDirty = false
            errorMessage = nil
            externalModificationDetected = false
            wordCount = Self.countWords(in: loaded.body)

            // Update the existing native text view (no view recreation)
            #if canImport(UIKit)
            activeTextView?.text = loaded.body
            #elseif canImport(AppKit)
            activeTextView?.string = loaded.body
            #endif

            // Clear undo stack again after text assignment (assignment may register undo)
            clearUndoStack()

            // Update highlighter with vault/note context for inline image resolution
            Task {
                await highlighter?.updateSettings(
                    fontFamily: highlighterFontFamily,
                    lineSpacing: highlighterLineSpacing,
                    vaultRootURL: vaultRootURL,
                    noteURL: url
                )
            }

            // Trigger highlighting and analysis
            highlightImmediately()
            scheduleAnalysis()

            // Refresh semantic links for the newly loaded note
            Task { await refreshSemanticLinks() }

            startFileWatching(for: url)

            // Signal ready for restoration after all synchronous setup is complete (F8 handshake)
            signalReadyForRestoration()
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
        isDirty = false
        errorMessage = nil
        externalModificationDetected = false
        wordCount = 0
        formattingState = .empty

        // Reset cursor and scroll state for clean restoration on next note open
        cursorPosition = NSRange(location: 0, length: 0)
        scrollOffset = .zero

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
    public func reloadFromDisk() async {
        guard let url = note?.fileURL else { return }
        externalModificationDetected = false
        await loadNote(at: url)
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
        guard newText != previousText else { return }

        // Track mutation origin for undo/highlight policy
        let editLen = (newText as NSString).length - (previousText as NSString).length
        let editLocation = cursorPosition.location - max(editLen, 0)
        currentTransaction = MutationTransaction(
            origin: .userTyping,
            editedRange: NSRange(location: max(editLocation, 0), length: editLen < 0 ? -editLen : 0),
            replacementLength: max(editLen, 0)
        )

        isDirty = true
        scheduleAutosave()
        scheduleWordCountUpdate()
        scheduleAnalysis()
        scheduleHighlight()
    }

    /// Called by the text view delegate when selection changes.
    public func selectionDidChange(_ range: NSRange) {
        let previousRange = cursorPosition
        cursorPosition = range
        updateTypingAttributes()
        formattingState = FormattingState.detect(in: currentText, at: range.location)

        guard syntaxVisibilityMode == .hiddenUntilCaret,
              !isApplyingHighlights,
              !lastAppliedHighlightSpans.isEmpty,
              visibilityContextRange(for: previousRange, in: currentText) != visibilityContextRange(for: range, in: currentText) else {
            return
        }

        applyHighlightSpans(lastAppliedHighlightSpans)
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

        cursorPosition = range

        // Apply to native text view
        #if canImport(UIKit)
        if let textView = activeTextView {
            textView.selectedRange = range
        }
        #elseif canImport(AppKit)
        if let textView = activeTextView {
            textView.setSelectedRange(range)
        }
        #endif
    }

    /// Restores scroll position after note reload.
    /// Called by the shell after loading a note to restore @SceneStorage state.
    ///
    /// - Parameter y: The vertical scroll offset.
    public func restoreScroll(y: Double) {
        let newOffset = CGPoint(x: scrollOffset.x, y: y)
        scrollOffset = newOffset

        // Apply to native text view
        #if canImport(UIKit)
        activeTextView?.setContentOffset(newOffset, animated: false)
        #elseif canImport(AppKit)
        if let scrollView = activeTextView?.enclosingScrollView {
            scrollView.contentView.scroll(to: newOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        #endif
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
    /// Called after `loadNote` completes and the text view is populated.
    /// Resumes all waiting continuations.
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
    }

    /// Triggers redo on the native text view's undo manager.
    public func redo() {
        #if canImport(UIKit)
        activeTextView?.undoManager?.redo()
        #elseif canImport(AppKit)
        activeTextView?.undoManager?.redo()
        #endif
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

    /// Applies a formatting action surgically via `applyExternalEdit`.
    /// Guarded by IME composition check.
    public func applyFormatting(_ action: FormattingAction) {
        guard !isComposing else { return }

        let formatter = MarkdownFormatter()
        guard let edit = formatter.surgicalEdit(action, in: currentText, selectedRange: cursorPosition) else { return }

        applyExternalEdit(
            replacement: edit.replacement,
            range: edit.range,
            cursorAfter: edit.cursorAfter,
            origin: .formatting
        )
        formattingState = FormattingState.detect(in: currentText, at: edit.cursorAfter.location)

        // Run highlight IMMEDIATELY with NO DIFF — force all attributes to be rewritten.
        // Formatting actions are infrequent (user clicks a button) so no perf concern.
        // The diff optimization can miss stale overlay colors after replaceCharacters shifts ranges.
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

    /// Applies highlight spans WITHOUT diffing — forces all attributes to be rewritten.
    /// Used after formatting actions where stale overlay attributes may have shifted.
    private func applyHighlightSpansForced(_ spans: [HighlightSpan]) {
        guard !isComposing else { return }
        isApplyingHighlights = true
        defer { isApplyingHighlights = false }
        lastAppliedHighlightSpans = spans

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = UIFont.systemFont(ofSize: baseFontSize)
        let defaultColor: UIColor = .label

        var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
        let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

        var lastEnd = 0
        for span in primarySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if r.location > lastEnd {
                segments.append((NSRange(location: lastEnd, length: r.location - lastEnd),
                                [.font: defaultFont, .foregroundColor: defaultColor]))
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? UIColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]
            if let ps = span.paragraphStyle { attrs[.paragraphStyle] = ps }
            if let trs = span.tableRowStyle { attrs[.quartzTableRowStyle] = trs.rawValue }
            segments.append((r, attrs))
            lastEnd = r.location + r.length
        }
        if lastEnd < storageLength {
            segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd),
                            [.font: defaultFont, .foregroundColor: defaultColor]))
        }

        // Disable undo registration — attribute styling should NOT pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        // NO DIFF — force set all attributes unconditionally
        for (range, targetAttrs) in segments {
            guard range.length > 0 else { continue }
            storage.setAttributes(targetAttrs, range: range)
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                storage.addAttribute(.foregroundColor, value: adjustedOverlayColor(color, overlayRange: r), range: r)
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
        for span in spans where span.attachment != nil {
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
        let defaultFont = NSFont.systemFont(ofSize: baseFontSize)
        let defaultColor: NSColor = .labelColor

        var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
        let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

        var lastEnd = 0
        for span in primarySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if r.location > lastEnd {
                segments.append((NSRange(location: lastEnd, length: r.location - lastEnd),
                                [.font: defaultFont, .foregroundColor: defaultColor]))
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? NSColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]
            if let ps = span.paragraphStyle { attrs[.paragraphStyle] = ps }
            if let trs = span.tableRowStyle { attrs[.quartzTableRowStyle] = trs.rawValue }
            segments.append((r, attrs))
            lastEnd = r.location + r.length
        }
        if lastEnd < storageLength {
            segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd),
                            [.font: defaultFont, .foregroundColor: defaultColor]))
        }

        // Disable undo registration — attribute styling should NOT pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        // NO DIFF — force set all attributes unconditionally
        for (range, targetAttrs) in segments {
            guard range.length > 0 else { continue }
            storage.setAttributes(targetAttrs, range: range)
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                storage.addAttribute(.foregroundColor, value: adjustedOverlayColor(color, overlayRange: r), range: r)
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
        for span in spans where span.attachment != nil {
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

        // Sync snapshot
        currentText = textView.text ?? ""

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

        storage.replaceCharacters(in: range, with: replacement)

        if let cursor = cursorAfter {
            textView.setSelectedRange(cursor)
        }

        if transaction.needsExplicitUndoGroup {
            undoManager?.endUndoGrouping()
        }
        if !transaction.registersUndo {
            undoManager?.enableUndoRegistration()
        }

        // Sync snapshot
        currentText = textView.string
        #endif

        isDirty = true
        scheduleAutosave()
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
        guard var currentNote = note, (isDirty || force), !isSaving else { return }

        isSaving = true
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
                }
            }

            note = currentNote
            // Only clear dirty if content hasn't changed since snapshot
            if currentText == textSnapshot {
                isDirty = false
            }
            errorMessage = nil

            // Publish via typed event bus (new pattern per CODEX.md F4)
            await DomainEventBus.shared.publish(.noteSaved(url: savedURL, timestamp: Date()))

            // Legacy NotificationCenter for backward compatibility
            NotificationCenter.default.post(name: .quartzNoteSaved, object: savedURL)

            // Save version snapshot only if 5+ minutes since last snapshot
            if let vaultRoot = vaultRootURL, shouldSaveVersionSnapshot() {
                lastSnapshotDate = Date()
                let content = textSnapshot
                let url = savedURL
                Task.detached(priority: .utility) {
                    VersionHistoryService().saveSnapshot(for: url, content: content, vaultRoot: vaultRoot)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            scheduleAutosave()
        }
    }

    /// Explicit save triggered by user action (Cmd+S, toolbar button).
    public func manualSave() async {
        // Always save a snapshot on manual save
        if let vaultRoot = vaultRootURL, let noteURL = note?.fileURL {
            lastSnapshotDate = Date()
            let content = currentText
            Task.detached(priority: .utility) {
                VersionHistoryService().saveSnapshot(for: noteURL, content: content, vaultRoot: vaultRoot)
            }
        }
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
    public var syntaxVisibilityMode: SyntaxVisibilityMode = .full
    /// Stored for deinit cleanup of debounced highlight work.
    private var highlightTask: Task<Void, Never>?
    /// Reused when selection-only changes should refresh concealment without reparsing.
    private var lastAppliedHighlightSpans: [HighlightSpan] = []

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
    public func highlightImmediately() {
        guard !isComposing else { return }

        // Hide text view to prevent flash of unstyled text
        #if canImport(UIKit)
        activeTextView?.alpha = 0
        #elseif canImport(AppKit)
        activeTextView?.alphaValue = 0
        #endif

        highlightTask?.cancel()
        highlightTask = Task(priority: .high) { [weak self] in
            guard let self, let highlighter = self.highlighter else { return }
            let text = self.currentText
            let spans = await highlighter.parse(text)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.applyHighlightSpans(spans)
                // Reveal text view after highlights are applied
                #if canImport(UIKit)
                self?.activeTextView?.alpha = 1
                #elseif canImport(AppKit)
                self?.activeTextView?.alphaValue = 1
                #endif
            }
        }
    }

    /// Applies highlight spans to the native text view with IME guard.
    private func applyHighlightSpans(_ spans: [HighlightSpan]) {
        guard !isComposing else { return }
        isApplyingHighlights = true
        defer { isApplyingHighlights = false }
        lastAppliedHighlightSpans = spans

        #if canImport(UIKit)
        guard let textView = activeTextView, let cm = contentManager else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedSelection = textView.selectedRange

        let baseFontSize = highlighterBaseFontSize
        let defaultFont = UIFont.systemFont(ofSize: baseFontSize)
        let defaultColor: UIColor = .label

        var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
        let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

        var lastEnd = 0
        for span in primarySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if r.location > lastEnd {
                segments.append((NSRange(location: lastEnd, length: r.location - lastEnd),
                                [.font: defaultFont, .foregroundColor: defaultColor]))
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? UIColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]
            if let ps = span.paragraphStyle { attrs[.paragraphStyle] = ps }
            if let trs = span.tableRowStyle { attrs[.quartzTableRowStyle] = trs.rawValue }
            segments.append((r, attrs))
            lastEnd = r.location + r.length
        }
        if lastEnd < storageLength {
            segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd),
                            [.font: defaultFont, .foregroundColor: defaultColor]))
        }

        // Disable undo registration — attribute styling should not pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        for (range, targetAttrs) in segments {
            guard range.length > 0 else { continue }
            if rangeNeedsFullAttributeRewrite(storage, range: range, targetAttrs: targetAttrs) {
                storage.setAttributes(targetAttrs, range: range)
            }
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                let adjusted = adjustedOverlayColor(color, overlayRange: r)
                let existing = storage.attributes(at: r.location, effectiveRange: nil)
                if !colorsEqual(existing[.foregroundColor] as? UIColor, adjusted as? UIColor) {
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
        for span in spans where span.attachment != nil {
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
        let defaultFont = NSFont.systemFont(ofSize: baseFontSize)
        let defaultColor: NSColor = .labelColor

        var segments: [(NSRange, [NSAttributedString.Key: Any])] = []
        let primarySpans = spans.filter { !$0.isOverlay }.sorted { $0.range.location < $1.range.location }

        var lastEnd = 0
        for span in primarySpans {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if r.location > lastEnd {
                segments.append((NSRange(location: lastEnd, length: r.location - lastEnd),
                                [.font: defaultFont, .foregroundColor: defaultColor]))
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? NSColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]
            if let ps = span.paragraphStyle { attrs[.paragraphStyle] = ps }
            if let trs = span.tableRowStyle { attrs[.quartzTableRowStyle] = trs.rawValue }
            segments.append((r, attrs))
            lastEnd = r.location + r.length
        }
        if lastEnd < storageLength {
            segments.append((NSRange(location: lastEnd, length: storageLength - lastEnd),
                            [.font: defaultFont, .foregroundColor: defaultColor]))
        }

        // Disable undo registration — attribute styling should not pollute the undo stack
        textView.undoManager?.disableUndoRegistration()
        defer { textView.undoManager?.enableUndoRegistration() }

        storage.beginEditing()
        for (range, targetAttrs) in segments {
            guard range.length > 0 else { continue }
            if rangeNeedsFullAttributeRewrite(storage, range: range, targetAttrs: targetAttrs) {
                storage.setAttributes(targetAttrs, range: range)
            }
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength else { continue }
            if let color = span.color {
                let adjusted = adjustedOverlayColor(color, overlayRange: r)
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
        for span in spans where span.attachment != nil {
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

    /// Heading font scale factors — must match MarkdownASTHighlighter exactly.
    private static let headingScales: [Int: CGFloat] = [
        1: 1.7, 2: 1.45, 3: 1.25, 4: 1.12, 5: 1.05, 6: 1.05
    ]

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

        if let headingFont = headingFontForCurrentLine(in: text, cursorLocation: loc, baseFontSize: baseFontSize, platform: .uiKit) {
            var typing = textView.typingAttributes
            typing[.font] = headingFont
            textView.typingAttributes = typing
            return
        }

        // A fresh paragraph after a heading/list should start from body styling,
        // not inherit stale attributes from the previous line break.
        if currentLineText(in: text, cursorLocation: loc).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var typing = textView.typingAttributes
            typing[.font] = defaultFont
            typing[.foregroundColor] = UIColor.label
            textView.typingAttributes = typing
            return
        }

        // Fallback: read from character before cursor
        guard loc > 0 else { return }
        let attrs = textView.textStorage.attributes(at: max(0, loc - 1), effectiveRange: nil)
        var typing = textView.typingAttributes
        if let font = attrs[.font] as? UIFont { typing[.font] = font }
        if let color = attrs[.foregroundColor] as? UIColor { typing[.foregroundColor] = color }
        textView.typingAttributes = typing

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        let text = textView.string
        let loc = textView.selectedRange().location
        let defaultFont = EditorFontFactory.makeFont(family: highlighterFontFamily, size: baseFontSize)

        if let headingFont = headingFontForCurrentLine(in: text, cursorLocation: loc, baseFontSize: baseFontSize, platform: .appKit) {
            var typing = textView.typingAttributes
            typing[.font] = headingFont
            textView.typingAttributes = typing
            return
        }

        // A fresh paragraph after a heading/list should start from body styling,
        // not inherit stale attributes from the previous line break.
        if currentLineText(in: text, cursorLocation: loc).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var typing = textView.typingAttributes
            typing[.font] = defaultFont
            typing[.foregroundColor] = NSColor.labelColor
            textView.typingAttributes = typing
            return
        }

        // Fallback: read from character before cursor
        guard loc > 0 else { return }
        let attrs = storage.attributes(at: max(0, loc - 1), effectiveRange: nil)
        var typing = textView.typingAttributes
        if let font = attrs[.font] as? NSFont { typing[.font] = font }
        if let color = attrs[.foregroundColor] as? NSColor { typing[.foregroundColor] = color }
        textView.typingAttributes = typing
        #endif
    }

    private enum Platform { case uiKit, appKit }

    /// Detects if the cursor is on a heading line and returns the appropriately scaled font.
    private func headingFontForCurrentLine(in text: String, cursorLocation: Int, baseFontSize: CGFloat, platform: Platform) -> Any? {
        guard !text.isEmpty, cursorLocation <= text.count else { return nil }

        // Find the start of the current line
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: min(cursorLocation, nsText.length - 1), length: 0))
        let line = nsText.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .newlines)

        // Check for heading prefix
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }

        // Must have a space after the # characters (or be just # characters being typed)
        let afterHashes = String(trimmed.dropFirst(level))
        guard afterHashes.isEmpty || afterHashes.hasPrefix(" ") else { return nil }

        let scale = Self.headingScales[level] ?? 1.05

        switch platform {
        case .uiKit:
            #if canImport(UIKit)
            return UIFont.systemFont(ofSize: baseFontSize * scale, weight: .bold)
            #else
            return nil
            #endif
        case .appKit:
            #if canImport(AppKit)
            return NSFont.systemFont(ofSize: baseFontSize * scale, weight: .bold)
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

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let capturedNoteURL = note?.fileURL
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autosaveDelay ?? .seconds(1))
            guard !Task.isCancelled else { return }
            // Verify we're still on the same note (prevents saving wrong note after switch)
            guard let self, self.note?.fileURL == capturedNoteURL else { return }
            await self.save()
        }
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
                suggestions = await Task.detached(priority: .utility) {
                    suggestionService.suggestLinks(for: text, currentNoteURL: noteURL, allNotes: tree)
                }.value
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.inspectorStore.update(with: analysis)
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
        let range = NSRange(location: heading.characterOffset, length: 0)

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        textView.scrollRangeToVisible(range)
        if let pos = textView.position(from: textView.beginningOfDocument, offset: heading.characterOffset) {
            textView.selectedTextRange = textView.textRange(from: pos, to: pos)
        }
        #elseif canImport(AppKit)
        guard let textView = activeTextView else { return }
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
        #endif
    }

    // MARK: - File Watching

    private func startFileWatching(for url: URL) {
        stopFileWatching()

        // Start NSFilePresenter for iCloud-coordinated change detection.
        // This is the primary monitor — it receives all coordinated writes
        // from iCloud daemon, Finder, and other processes.
        filePresenter = NoteFilePresenter(url: url, delegate: self)

        // Only use DispatchSource (FileWatcher) for non-iCloud vaults.
        // For iCloud vaults, NSFilePresenter is sufficient and avoids
        // dual-monitoring race conditions (double reload, echo after save).
        let isICloudVault = url.path(percentEncoded: false).contains("Mobile Documents")
        guard !isICloudVault else { return }

        let watcher = FileWatcher(url: url)
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
            // Content-hash echo suppression: read the file and compare hash.
            // If it matches what we last wrote, this is our own save echoing back.
            if let noteURL = note?.fileURL, let lastHash = lastSavedContentHash {
                let diskData = try? Data(contentsOf: noteURL)
                if let diskData {
                    let diskHash = SHA256.hash(data: diskData)
                    if diskHash == lastHash {
                        return // Echo from our own save — ignore
                    }
                }
            }

            if isDirty {
                externalModificationDetected = true
            } else {
                Task { await reloadFromDisk() }
            }
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
            wikiLinkNavigationRequest = WikiLinkNavigationRequest(title: title, url: url)
            NotificationCenter.default.post(
                name: .quartzWikiLinkNavigation,
                object: nil,
                userInfo: ["url": url, "title": title]
            )
        }
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

    // MARK: - Cleanup

    public func cancelAllTasks() {
        autosaveTask?.cancel()
        highlightTask?.cancel()
        fileWatchTask?.cancel()
        wordCountTask?.cancel()
        analysisTask?.cancel()
        inlineAITask?.cancel()
    }

    // MARK: - Inline AI

    /// Stored for deinit cleanup of inline AI work.
    private var inlineAITask: Task<Void, Never>?

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

    // MARK: - Helpers

    private func currentLineText(in text: String, cursorLocation: Int) -> String {
        let nsText = text as NSString
        let safeCursor = min(max(cursorLocation, 0), nsText.length)

        var start = safeCursor
        while start > 0 {
            let scalar = nsText.character(at: start - 1)
            if scalar == 10 || scalar == 13 { break }
            start -= 1
        }

        var end = safeCursor
        while end < nsText.length {
            let scalar = nsText.character(at: end)
            if scalar == 10 || scalar == 13 { break }
            end += 1
        }

        return nsText.substring(with: NSRange(location: start, length: end - start))
    }

    private func visibilityContextRange(for selection: NSRange, in text: String) -> NSRange? {
        guard !text.isEmpty else { return nil }
        let nsText = text as NSString
        let clampedLocation = min(max(selection.location, 0), max(nsText.length - 1, 0))

        if selection.length > 0 {
            let safeLength = min(selection.length, max(nsText.length - clampedLocation, 0))
            return nsText.lineRange(for: NSRange(location: clampedLocation, length: safeLength))
        }

        return nsText.lineRange(for: NSRange(location: clampedLocation, length: 0))
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
    /// - `.gentleFade`: returns the color at 0.4 alpha.
    /// - `.hiddenUntilCaret`: hides delimiters unless the active selection is on the same line.
    private func adjustedOverlayColor(_ color: PlatformColor, overlayRange: NSRange) -> PlatformColor {
        switch syntaxVisibilityMode {
        case .full:
            return color
        case .gentleFade:
            return color.withAlphaComponent(0.4)
        case .hiddenUntilCaret:
            if let activeRange = visibilityContextRange(for: cursorPosition, in: currentText),
               NSIntersectionRange(activeRange, overlayRange).length > 0 {
                return color
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

        // Content-hash echo suppression: if the on-disk content matches
        // what we last wrote, this is our own save echoing through NSFilePresenter.
        if let noteURL = presenter.presentedItemURL, let lastHash = lastSavedContentHash {
            let diskData = try? Data(contentsOf: noteURL)
            if let diskData {
                let diskHash = SHA256.hash(data: diskData)
                if diskHash == lastHash {
                    return // Echo from our own save — ignore
                }
            }
        }

        // Post notification so Intelligence Engine can re-index the file
        if let url = presenter.presentedItemURL {
            NotificationCenter.default.post(name: .quartzFilePresenterDidChange, object: url)
        }

        // Handle UI update
        if isDirty {
            externalModificationDetected = true
        } else {
            Task { await reloadFromDisk() }
        }
    }

    /// Called when the file has been moved or renamed.
    public func filePresenter(_ presenter: NoteFilePresenter, didMoveFrom oldURL: URL?, to newURL: URL) {
        // Update our note reference
        if var currentNote = note {
            // Create a new NoteDocument with the updated URL
            currentNote = NoteDocument(
                fileURL: newURL,
                frontmatter: currentNote.frontmatter,
                body: currentNote.body
            )
            note = currentNote
        }

        // Publish via typed event bus (new pattern per CODEX.md F4)
        if let oldURL {
            Task {
                await DomainEventBus.shared.publish(.noteRelocated(from: oldURL, to: newURL))
            }
        }

        // Legacy NotificationCenter for backward compatibility
        NotificationCenter.default.post(
            name: .quartzFilePresenterDidMove,
            object: nil,
            userInfo: ["oldURL": oldURL as Any, "newURL": newURL]
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

        note = noteToSave
        if currentText == textSnapshot {
            isDirty = false
        }
    }
}
