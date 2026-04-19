import Foundation

/// Canonical explicit note-to-note relationship payload.
///
/// KG2 uses this as the one interpreted representation of an explicit wiki-link after
/// parsing and target resolution. Other relationship surfaces may project subsets of it,
/// but they should not reinterpret the source markdown independently.
public struct ExplicitNoteReference: Identifiable, Sendable, Equatable, Codable {
    /// Canonical source note identity where the wiki-link appears.
    public let sourceNoteURL: URL
    /// Canonical target note identity resolved from the wiki-link target.
    public let targetNoteURL: URL
    /// Resolved target note display name used in inspector/UI surfaces.
    public let targetNoteName: String
    /// Canonical insertion target for this note (currently the note name).
    public let insertableTarget: String
    /// Raw inner text of the wiki-link, excluding the surrounding `[[` and `]]`.
    public let rawLinkText: String
    /// Raw target text before alias/display text, excluding any heading fragment.
    public let rawTargetText: String
    /// Display text shown to the user (alias if present, otherwise target text).
    public let displayText: String
    /// Optional heading fragment from `[[Note#Heading]]`.
    public let headingFragment: String?
    /// Exact source range of the wiki-link where available.
    public let matchRange: NSRange?
    /// Source line range containing the wiki-link where available.
    public let lineRange: NSRange?
    /// Trimmed single-line context for inspector/backlink display.
    public let context: String

    public var id: String {
        let matchLocation = matchRange?.location ?? -1
        let matchLength = matchRange?.length ?? 0
        return "\(sourceNoteURL.absoluteString)->\(targetNoteURL.absoluteString)#\(matchLocation)-\(matchLength)"
    }

    public init(
        sourceNoteURL: URL,
        targetNoteURL: URL,
        targetNoteName: String,
        insertableTarget: String,
        rawLinkText: String,
        rawTargetText: String,
        displayText: String,
        headingFragment: String?,
        matchRange: NSRange?,
        lineRange: NSRange?,
        context: String
    ) {
        self.sourceNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceNoteURL)
        self.targetNoteURL = CanonicalNoteIdentity.canonicalFileURL(for: targetNoteURL)
        self.targetNoteName = targetNoteName
        self.insertableTarget = insertableTarget
        self.rawLinkText = rawLinkText
        self.rawTargetText = rawTargetText
        self.displayText = displayText
        self.headingFragment = headingFragment?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matchRange = matchRange
        self.lineRange = lineRange
        self.context = context
    }
}
