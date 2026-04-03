import Foundation

// MARK: - Syntax Visibility Mode

/// Controls how markdown syntax delimiters (e.g., `**`, `#`, `` ` ``) are displayed.
///
/// Used by `MarkdownASTHighlighter` to determine the overlay color applied to syntax characters.
public enum SyntaxVisibilityMode: String, Sendable, CaseIterable {
    /// Default: delimiters shown in `tertiaryLabel` color (visible but subdued).
    case full

    /// Delimiters shown at reduced opacity (gentler fade than `full`).
    case gentleFade

    /// Delimiters hidden (clear color) until the cursor is on the same line.
    /// When the cursor enters a line, delimiters on that line become visible.
    case hiddenUntilCaret
}
