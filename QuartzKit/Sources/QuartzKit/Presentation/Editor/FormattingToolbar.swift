import SwiftUI

/// Markdown-Formatierungsaktionen.
public enum FormattingAction: String, CaseIterable, Sendable {
    case bold
    case italic
    case heading
    case bulletList
    case numberedList
    case checkbox
    case code
    case codeBlock
    case link
    case image
    case blockquote

    var icon: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .heading: "textformat.size.larger"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checkbox: "checklist"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "terminal"
        case .link: "link"
        case .image: "photo"
        case .blockquote: "text.quote"
        }
    }

    var label: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .heading: "Heading"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .checkbox: "Checkbox"
        case .code: "Inline Code"
        case .codeBlock: "Code Block"
        case .link: "Link"
        case .image: "Image"
        case .blockquote: "Quote"
        }
    }

    /// Das Markdown-Prefix/Wrapper für diese Aktion.
    var markdownSyntax: MarkdownSyntax {
        switch self {
        case .bold: .wrap("**")
        case .italic: .wrap("*")
        case .heading: .linePrefix("# ")
        case .bulletList: .linePrefix("- ")
        case .numberedList: .linePrefix("1. ")
        case .checkbox: .linePrefix("- [ ] ")
        case .code: .wrap("`")
        case .codeBlock: .block("```\n", "\n```")
        case .link: .template("[", "](url)")
        case .image: .template("![", "](path)")
        case .blockquote: .linePrefix("> ")
        }
    }
}

/// Beschreibt wie Markdown-Syntax auf Text angewandt wird.
public enum MarkdownSyntax: Sendable {
    /// Umschließt ausgewählten Text: `**text**`
    case wrap(String)
    /// Prefix am Zeilenanfang: `# text`
    case linePrefix(String)
    /// Block-Syntax: ```\ntext\n```
    case block(String, String)
    /// Template mit Cursor-Platzierung: `[text](url)`
    case template(String, String)
}

// MARK: - Formatting Toolbar View

/// Toolbar für Markdown-Formatierung.
///
/// iOS: Wird über der Tastatur angezeigt.
/// macOS: Wird in der Toolbar des Editors angezeigt.
public struct FormattingToolbar: View {
    let onAction: (FormattingAction) -> Void

    /// Die primären Aktionen die direkt sichtbar sind.
    private let primaryActions: [FormattingAction] = [
        .bold, .italic, .heading, .bulletList, .checkbox, .code, .link
    ]

    /// Sekundäre Aktionen im Overflow-Menü.
    private let secondaryActions: [FormattingAction] = [
        .numberedList, .codeBlock, .image, .blockquote
    ]

    public init(onAction: @escaping (FormattingAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(primaryActions, id: \.self) { action in
                Button {
                    onAction(action)
                } label: {
                    Image(systemName: action.icon)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.label)
            }

            Divider()
                .frame(height: 20)

            Menu {
                ForEach(secondaryActions, id: \.self) { action in
                    Button {
                        onAction(action)
                    } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Markdown Text Formatting Logic

/// Wendet Markdown-Formatierung auf Text an.
public struct MarkdownFormatter: Sendable {
    public init() {}

    /// Wendet eine Formatierungsaktion auf den gegebenen Text an.
    ///
    /// - Parameters:
    ///   - action: Die Formatierungsaktion
    ///   - text: Der gesamte Text
    ///   - selectedRange: Der ausgewählte Bereich (NSRange)
    /// - Returns: Neuer Text und neue Cursor-Position
    public func apply(
        _ action: FormattingAction,
        to text: String,
        selectedRange: NSRange
    ) -> (text: String, newSelection: NSRange) {
        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)

        switch action.markdownSyntax {
        case .wrap(let marker):
            return applyWrap(marker, text: text, selection: selectedRange, selectedText: selectedText)

        case .linePrefix(let prefix):
            return applyLinePrefix(prefix, text: text, selection: selectedRange)

        case .block(let open, let close):
            let replacement = "\(open)\(selectedText)\(close)"
            let newText = nsText.replacingCharacters(in: selectedRange, with: replacement)
            let cursorPos = selectedRange.location + open.count
            return (newText, NSRange(location: cursorPos, length: selectedText.count))

        case .template(let before, let after):
            let replacement = "\(before)\(selectedText)\(after)"
            let newText = nsText.replacingCharacters(in: selectedRange, with: replacement)
            if selectedText.isEmpty {
                // Cursor zwischen before und after
                let cursorPos = selectedRange.location + before.count
                return (newText, NSRange(location: cursorPos, length: 0))
            } else {
                let cursorPos = selectedRange.location + before.count + selectedText.count + after.count
                return (newText, NSRange(location: cursorPos, length: 0))
            }
        }
    }

    private func applyWrap(
        _ marker: String,
        text: String,
        selection: NSRange,
        selectedText: String
    ) -> (String, NSRange) {
        let nsText = text as NSString

        // Toggle: Wenn bereits gewrappt, entferne den Wrapper
        let markerLen = marker.count
        let before = selection.location >= markerLen
            ? nsText.substring(with: NSRange(location: selection.location - markerLen, length: markerLen))
            : ""
        let afterEnd = selection.location + selection.length
        let after = afterEnd + markerLen <= nsText.length
            ? nsText.substring(with: NSRange(location: afterEnd, length: markerLen))
            : ""

        if before == marker && after == marker {
            // Entfernen
            let removeRange = NSRange(location: selection.location - markerLen, length: selection.length + markerLen * 2)
            let newText = nsText.replacingCharacters(in: removeRange, with: selectedText)
            return (newText, NSRange(location: selection.location - markerLen, length: selectedText.count))
        } else {
            // Hinzufügen
            let replacement = "\(marker)\(selectedText)\(marker)"
            let newText = nsText.replacingCharacters(in: selection, with: replacement)
            return (newText, NSRange(location: selection.location + markerLen, length: selectedText.count))
        }
    }

    private func applyLinePrefix(
        _ prefix: String,
        text: String,
        selection: NSRange
    ) -> (String, NSRange) {
        let nsText = text as NSString

        // Finde den Anfang der aktuellen Zeile
        let lineRange = nsText.lineRange(for: selection)
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            // Toggle: Prefix entfernen
            let newLine = String(line.dropFirst(prefix.count))
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            let newLoc = max(selection.location - prefix.count, lineRange.location)
            return (newText, NSRange(location: newLoc, length: 0))
        } else {
            // Prefix hinzufügen
            let newLine = prefix + line
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: selection.location + prefix.count, length: 0))
        }
    }
}
