import Foundation

// MARK: - Editor Paste Policy

/// Controls how pasted text is normalized before it is inserted into the editor.
public enum EditorPasteMode: String, Sendable, CaseIterable {
    /// Normalizes pasted text in calm, predictable ways while preserving markdown semantics.
    case smart
    /// Inserts the pasted text exactly as provided.
    case raw
}

struct EditorPasteNormalizer: Sendable {
    func normalizedText(_ text: String, mode: EditorPasteMode) -> String {
        switch mode {
        case .raw:
            return text
        case .smart:
            return normalizeSmartPaste(text)
        }
    }

    private func normalizeSmartPaste(_ text: String) -> String {
        let unifiedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        return unifiedLineEndings
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(normalizeLine)
            .joined(separator: "\n")
    }

    private func normalizeLine<S: StringProtocol>(_ line: S) -> String {
        let rawLine = String(line)
        let leading = rawLine.prefix { $0 == " " || $0 == "\t" }
        let trimmedBody = rawLine.dropFirst(leading.count)
        let normalizedLeading = leading.reduce(into: "") { buffer, character in
            if character == "\t" {
                buffer.append("    ")
            } else {
                buffer.append(character)
            }
        }
        let normalizedBody = trimmedBody.replacingOccurrences(
            of: #"[ \t]+$"#,
            with: "",
            options: .regularExpression
        )
        return normalizedLeading + normalizedBody
    }
}
