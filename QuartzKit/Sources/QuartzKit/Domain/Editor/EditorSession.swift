import SwiftUI
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
    private var autosaveTask: Task<Void, Never>?
    private var fileWatchTask: Task<Void, Never>?
    private var wordCountTask: Task<Void, Never>?

    // MARK: - Inspector Integration

    /// Background analysis service for headings + stats.
    private let analysisService = MarkdownAnalysisService()

    /// Inspector store — drives the right panel UI. Shared across note switches.
    public let inspectorStore: InspectorStore

    /// Task for the debounced analysis pass.
    private var analysisTask: Task<Void, Never>?

    /// Delay before running analysis (longer than highlighting since ToC doesn't need keystroke-level updates).
    private let analysisDelay: Duration = .milliseconds(300)

    private let autosaveDelay: Duration = .seconds(1)

    // MARK: - Init

    public init(vaultProvider: any VaultProviding, frontmatterParser: any FrontmatterParsing, inspectorStore: InspectorStore) {
        self.vaultProvider = vaultProvider
        self.frontmatterParser = frontmatterParser
        self.inspectorStore = inspectorStore
    }

    // MARK: - Note Loading

    /// Loads a note from the file system into the existing session.
    /// Reuses the mounted text view — no view destruction.
    public func loadNote(at url: URL) async {
        cancelAllTasks()
        stopFileWatching()

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

            // Trigger highlighting and analysis
            highlightImmediately()
            scheduleAnalysis()

            startFileWatching(for: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "An unexpected error occurred.", bundle: .module)
        }
    }

    /// Closes the current note without destroying the session.
    /// Clears text, note reference, and undo stack. The EditorContainerView
    /// stays mounted — it shows the empty state based on `note == nil`.
    public func closeNote() {
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

    // MARK: - Text Synchronization (called by delegate)

    /// Called by the text view delegate when the user edits text.
    /// This is the ONLY path that updates `currentText` — SwiftUI never does.
    public func textDidChange(_ newText: String) {
        let previousText = currentText
        currentText = newText
        guard newText != previousText else { return }
        isDirty = true
        scheduleAutosave()
        scheduleWordCountUpdate()
        scheduleAnalysis()
        scheduleHighlight()
    }

    /// Called by the text view delegate when selection changes.
    public func selectionDidChange(_ range: NSRange) {
        cursorPosition = range
        updateTypingAttributes()
        formattingState = FormattingState.detect(in: currentText, at: range.location)
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
            cursorAfter: edit.cursorAfter
        )

        // Update formatting state after the edit
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

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedTypingAttrs = textView.typingAttributes
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
            segments.append((r, [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? UIColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]))
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
            guard r.location >= 0, r.location + r.length <= storageLength, let color = span.color else { continue }
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
        storage.endEditing()

        textView.typingAttributes = savedTypingAttrs
        if textView.selectedRange != savedSelection {
            let len = (textView.text ?? "").count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.selectedRange = savedSelection
            }
        }

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }

        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedTypingAttrs = textView.typingAttributes
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
            segments.append((r, [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? NSColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]))
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
            guard r.location >= 0, r.location + r.length <= storageLength, let color = span.color else { continue }
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
        storage.endEditing()

        textView.typingAttributes = savedTypingAttrs
        if textView.selectedRange() != savedSelection {
            let len = textView.string.count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.setSelectedRange(savedSelection)
            }
        }
        #endif
    }

    // MARK: - External Edit (Surgical, IME-Safe)

    /// Applies a surgical text edit from an external source (list continuation,
    /// AI insertion, iCloud merge). Uses `NSTextStorage.replaceCharacters`
    /// for proper undo registration and minimal layout invalidation.
    ///
    /// **IME Guard**: Refuses to mutate text during active composition.
    public func applyExternalEdit(
        replacement: String,
        range: NSRange,
        cursorAfter: NSRange? = nil
    ) {
        guard !isComposing else { return }

        #if canImport(UIKit)
        guard let textView = activeTextView else { return }
        textView.textStorage.replaceCharacters(in: range, with: replacement)

        if let cursor = cursorAfter {
            if let start = textView.position(from: textView.beginningOfDocument, offset: cursor.location),
               let end = textView.position(from: start, offset: cursor.length) {
                textView.selectedTextRange = textView.textRange(from: start, to: end)
            }
        }

        // Sync snapshot
        currentText = textView.text ?? ""

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        storage.replaceCharacters(in: range, with: replacement)

        if let cursor = cursorAfter {
            textView.setSelectedRange(cursor)
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
            try await vaultProvider.saveNote(currentNote)
            note = currentNote
            // Only clear dirty if content hasn't changed since snapshot
            if currentText == textSnapshot {
                isDirty = false
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
    public func manualSave() async {
        await save(force: true)
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
    private var highlightTask: Task<Void, Never>?

    /// Schedules a debounced highlight pass. Skips if IME is composing.
    public func scheduleHighlight() {
        guard !isComposing else { return }

        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            guard let self, let highlighter = self.highlighter else { return }
            let text = self.currentText
            let spans = await highlighter.parseDebounced(text)
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
        highlightTask = Task(priority: .userInteractive) { [weak self] in
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

        #if canImport(UIKit)
        guard let textView = activeTextView, let cm = contentManager else { return }
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedTypingAttrs = textView.typingAttributes
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
            segments.append((r, [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? UIColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]))
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
            let existing = storage.attributes(at: range.location, effectiveRange: nil)
            if !fontsEqual(existing[.font] as? UIFont, targetAttrs[.font] as? UIFont) ||
               !colorsEqual(existing[.foregroundColor] as? UIColor, targetAttrs[.foregroundColor] as? UIColor) {
                storage.setAttributes(targetAttrs, range: range)
            }
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength, let color = span.color else { continue }
            let existing = storage.attributes(at: r.location, effectiveRange: nil)
            if !colorsEqual(existing[.foregroundColor] as? UIColor, color as? UIColor) {
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
        storage.endEditing()

        textView.typingAttributes = savedTypingAttrs
        if textView.selectedRange != savedSelection {
            let len = (textView.text ?? "").count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.selectedRange = savedSelection
            }
        }

        #elseif canImport(AppKit)
        guard let textView = activeTextView, let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }

        let storageLength = storage.length
        guard storageLength > 0 else { return }

        let savedTypingAttrs = textView.typingAttributes
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
            segments.append((r, [
                .font: span.font, .foregroundColor: span.color ?? defaultColor,
                .backgroundColor: span.backgroundColor ?? NSColor.clear,
                .strikethroughStyle: span.strikethrough ? 1 : 0
            ]))
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
            let existing = storage.attributes(at: range.location, effectiveRange: nil)
            if !fontsEqual(existing[.font] as? NSFont, targetAttrs[.font] as? NSFont) ||
               !colorsEqual(existing[.foregroundColor] as? NSColor, targetAttrs[.foregroundColor] as? NSColor) {
                storage.setAttributes(targetAttrs, range: range)
            }
        }
        for span in spans where span.isOverlay {
            let r = span.range
            guard r.location >= 0, r.location + r.length <= storageLength, let color = span.color else { continue }
            let existing = storage.attributes(at: r.location, effectiveRange: nil)
            if !colorsEqual(existing[.foregroundColor] as? NSColor, color as? NSColor) {
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
        storage.endEditing()

        textView.typingAttributes = savedTypingAttrs
        if textView.selectedRange() != savedSelection {
            let len = textView.string.count
            if savedSelection.location <= len && savedSelection.location + savedSelection.length <= len {
                textView.setSelectedRange(savedSelection)
            }
        }
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

        if let headingFont = headingFontForCurrentLine(in: text, cursorLocation: loc, baseFontSize: baseFontSize, platform: .uiKit) {
            var typing = textView.typingAttributes
            typing[.font] = headingFont
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

        if let headingFont = headingFontForCurrentLine(in: text, cursorLocation: loc, baseFontSize: baseFontSize, platform: .appKit) {
            var typing = textView.typingAttributes
            typing[.font] = headingFont
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

    // MARK: - Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autosaveDelay ?? .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.save()
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

    /// Schedules a debounced analysis pass for headings + stats.
    /// Cancels any in-flight analysis to avoid 50 concurrent parses.
    private func scheduleAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.analysisDelay)
            guard !Task.isCancelled else { return }
            let text = self.currentText
            let analysis = await self.analysisService.analyze(text)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.inspectorStore.update(with: analysis)
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
        let watcher = FileWatcher(url: url)
        fileWatchTask = Task { [weak self] in
            let stream = await watcher.startWatching()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handleFileChange(event)
            }
        }
    }

    private func stopFileWatching() {
        fileWatchTask?.cancel()
        fileWatchTask = nil
    }

    private func handleFileChange(_ event: FileChangeEvent) {
        switch event {
        case .modified:
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

    // MARK: - Cleanup

    public func cancelAllTasks() {
        autosaveTask?.cancel()
        highlightTask?.cancel()
        fileWatchTask?.cancel()
        wordCountTask?.cancel()
        analysisTask?.cancel()
    }

    // MARK: - Helpers

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
}
