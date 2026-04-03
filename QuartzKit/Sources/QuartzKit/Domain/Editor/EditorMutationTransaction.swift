import Foundation

// MARK: - Mutation Origin

/// Classifies every text mutation by origin.
/// Used to determine undo policy, selection semantics, and highlight strategy.
public enum MutationOrigin: String, Sendable, CaseIterable {
    /// Keystroke-by-keystroke user typing — native undo grouping.
    case userTyping
    /// Enter key list continuation — single undo group.
    case listContinuation
    /// Toolbar/shortcut formatting (bold, italic, etc.) — single undo group.
    case formatting
    /// AI writing tools replacement — single undo group.
    case aiInsert
    /// iCloud or external sync merge — does not register undo.
    case syncMerge
    /// Paste or drag-and-drop content — single undo group.
    case pasteOrDrop
    /// Apple system Writing Tools (.complete) — system-managed undo.
    case writingTools
    /// Task checkbox toggle — single undo group.
    case taskToggle
    /// Table navigation (Tab inserts new row) — single undo group.
    case tableNavigation
}

// MARK: - Mutation Transaction

/// A single text mutation with its origin, range, and policies.
/// Created at the start of a mutation, consumed by undo/highlight systems.
public struct MutationTransaction: Sendable {
    /// What triggered this mutation.
    public let origin: MutationOrigin

    /// The range in the document that was replaced.
    public let editedRange: NSRange

    /// The replacement text length (for computing dirty region after edit).
    public let replacementLength: Int

    /// When this transaction was created.
    public let timestamp: Date

    public init(
        origin: MutationOrigin,
        editedRange: NSRange,
        replacementLength: Int,
        timestamp: Date = Date()
    ) {
        self.origin = origin
        self.editedRange = editedRange
        self.replacementLength = replacementLength
        self.timestamp = timestamp
    }

    // MARK: - Undo Policy

    /// Whether this mutation should register with the undo manager.
    /// `syncMerge` and `writingTools` bypass the undo manager.
    public var registersUndo: Bool {
        switch origin {
        case .syncMerge: return false
        case .writingTools: return false
        default: return true
        }
    }

    /// Whether this mutation should clear the undo stack entirely.
    /// Only sync merges invalidate the undo history.
    public var clearsUndoStack: Bool {
        origin == .syncMerge
    }

    /// Whether this mutation should be grouped with the previous undo action.
    /// Only `userTyping` uses native character-by-character undo coalescing.
    /// All other origins that register undo get their own explicit group.
    public var groupsWithPrevious: Bool {
        origin == .userTyping
    }

    /// Whether the edit should be wrapped in explicit `beginUndoGrouping` / `endUndoGrouping`.
    /// This makes multi-step operations (list continuation, formatting) undo as a single step.
    public var needsExplicitUndoGroup: Bool {
        switch origin {
        case .listContinuation, .formatting, .aiInsert, .pasteOrDrop, .taskToggle, .tableNavigation:
            return true
        case .userTyping, .syncMerge, .writingTools:
            return false
        }
    }

    // MARK: - Highlight Policy

    /// Whether this mutation should use the incremental (range-scoped) highlight path.
    /// Full re-parse is used for formatting (which shifts ranges) and sync merges.
    public var prefersIncrementalHighlight: Bool {
        switch origin {
        case .userTyping, .listContinuation, .pasteOrDrop, .taskToggle, .tableNavigation:
            return true
        case .formatting, .aiInsert, .syncMerge, .writingTools:
            return false
        }
    }
}
