import SwiftUI

/// Renders AI response text with inline `[Source N]` citation badges.
///
/// Parses the raw text for `[Source N]` markers and replaces them with
/// colored inline badges that match the source card color palette.
/// Non-citation text is rendered with `AttributedString(markdown:)` for
/// inline formatting (bold, italic, code).
///
/// **Ref:** Phase F4 Spec — VaultCitationRenderer
struct VaultCitationRenderer: View {
    let text: String
    let citations: [Citation]

    /// Parsed segments: alternating between plain text and citation markers.
    private var segments: [Segment] {
        Self.parse(text)
    }

    var body: some View {
        segments.reduce(Text("")) { result, segment in
            switch segment {
            case .text(let str):
                let rendered: Text = {
                    if let attributed = try? AttributedString(
                        markdown: str,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        return Text(attributed)
                    }
                    return Text(str)
                }()
                return result + rendered
            case .citation(let n):
                let color = VaultSourceCard.color(for: n)
                return result + Text(" \(n) ")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundColor(color)
                    .baselineOffset(2)
            }
        }
    }

    // MARK: - Parsing

    enum Segment {
        case text(String)
        case citation(Int)
    }

    /// Parses text for `[Source N]` patterns and splits into segments.
    static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = text[text.startIndex...]

        // Match [Source N] or [Source  N] (flexible whitespace)
        while let range = remaining.range(of: #"\[Source\s+(\d+)\]"#, options: .regularExpression) {
            // Text before the match
            let before = remaining[remaining.startIndex..<range.lowerBound]
            if !before.isEmpty {
                segments.append(.text(String(before)))
            }

            // Extract the number
            let matchText = String(remaining[range])
            if let numStr = matchText.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter({ !$0.isEmpty }).first,
               let num = Int(numStr) {
                segments.append(.citation(num))
            } else {
                segments.append(.text(matchText))
            }

            remaining = remaining[range.upperBound...]
        }

        // Remaining text after last match
        if !remaining.isEmpty {
            segments.append(.text(String(remaining)))
        }

        return segments
    }
}
