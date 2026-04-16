import Foundation
import Observation

/// Editor-local state for current-note find/replace.
///
/// This is intentionally scoped to a single mounted ``EditorSession`` and never
/// reaches vault-wide search or cross-note mutation flows.
@Observable
@MainActor
public final class InNoteSearchState {
    public var isPresented: Bool = false
    public var query: String = ""
    public var replacement: String = ""
    public var isReplaceVisible: Bool = false
    public var isCaseSensitive: Bool = false

    /// Token used by the SwiftUI surface to refocus the query field when the
    /// search UI is explicitly opened again via command or toolbar.
    public var focusRequestToken: UUID = UUID()

    public private(set) var matches: [NSRange] = []
    public private(set) var currentMatchIndex: Int?
    public private(set) var selectionBeforePresentation: NSRange?
    public private(set) var shouldRestoreEditorFocusOnDismiss: Bool = false

    public init() {}

    public var currentMatch: NSRange? {
        guard let currentMatchIndex,
              matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    public var matchCount: Int {
        matches.count
    }

    public var currentMatchDisplayIndex: Int? {
        guard let currentMatchIndex, matches.indices.contains(currentMatchIndex) else { return nil }
        return currentMatchIndex + 1
    }

    public var hasQuery: Bool {
        !query.isEmpty
    }

    public var hasMatches: Bool {
        currentMatch != nil
    }

    public var hasReplaceableCurrentMatch: Bool {
        hasMatches && !query.isEmpty
    }

    public func beginPresentation(
        selection: NSRange,
        shouldRestoreEditorFocusOnDismiss: Bool
    ) {
        isPresented = true
        selectionBeforePresentation = selection
        self.shouldRestoreEditorFocusOnDismiss = shouldRestoreEditorFocusOnDismiss
        focusRequestToken = UUID()
    }

    public func updateMatches(_ matches: [NSRange], currentMatchIndex: Int?) {
        self.matches = matches
        self.currentMatchIndex = currentMatchIndex
    }

    public func clearMatches() {
        matches = []
        currentMatchIndex = nil
    }

    public func dismiss() {
        isPresented = false
        clearMatches()
        isReplaceVisible = false
        selectionBeforePresentation = nil
        shouldRestoreEditorFocusOnDismiss = false
    }

    nonisolated static func computeMatches(
        in text: String,
        query: String,
        isCaseSensitive: Bool
    ) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let nsText = text as NSString
        let nsQuery = query as NSString
        guard nsQuery.length > 0 else { return [] }

        let options: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.length > 0 {
            let found = nsText.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            matches.append(found)

            let nextLocation = found.location + max(found.length, 1)
            guard nextLocation <= nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return matches
    }

    nonisolated static func replacingMatches(
        in text: String,
        matches: [NSRange],
        replacement: String
    ) -> String {
        guard !matches.isEmpty else { return text }

        let nsText = text as NSString
        var rebuilt = ""
        var cursor = 0

        for match in matches {
            guard match.location >= cursor, NSMaxRange(match) <= nsText.length else { continue }
            rebuilt += nsText.substring(with: NSRange(location: cursor, length: match.location - cursor))
            rebuilt += replacement
            cursor = NSMaxRange(match)
        }

        rebuilt += nsText.substring(from: cursor)
        return rebuilt
    }
}
