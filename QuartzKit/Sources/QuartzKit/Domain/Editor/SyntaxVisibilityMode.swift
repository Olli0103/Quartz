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

    /// Delimiters hidden (clear color) until the active selection touches the
    /// owning semantic token. This is the Bear-style default for 4.5.
    case hiddenUntilCaret
}
