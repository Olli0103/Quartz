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
        case .bold: String(localized: "Bold", bundle: .module)
        case .italic: String(localized: "Italic", bundle: .module)
        case .heading: String(localized: "Heading", bundle: .module)
        case .bulletList: String(localized: "Bullet List", bundle: .module)
        case .numberedList: String(localized: "Numbered List", bundle: .module)
        case .checkbox: String(localized: "Checkbox", bundle: .module)
        case .code: String(localized: "Inline Code", bundle: .module)
        case .codeBlock: String(localized: "Code Block", bundle: .module)
        case .link: String(localized: "Link", bundle: .module)
        case .image: String(localized: "Image", bundle: .module)
        case .blockquote: String(localized: "Quote", bundle: .module)
        }
    }

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
    case wrap(String)
    case linePrefix(String)
    case block(String, String)
    case template(String, String)
}

// MARK: - Formatting Toolbar View

/// Toolbar für Markdown-Formatierung – Liquid Glass Stil.
public struct FormattingToolbar: View {
    let onAction: (FormattingAction) -> Void

    private let primaryActions: [FormattingAction] = [
        .bold, .italic, .heading, .bulletList, .checkbox, .code, .link
    ]

    private let secondaryActions: [FormattingAction] = [
        .numberedList, .codeBlock, .image, .blockquote
    ]

    public init(onAction: @escaping (FormattingAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(primaryActions, id: \.self) { action in
                    Button {
                        onAction(action)
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(action.label)
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 4)

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
                        .font(.system(size: 14, weight: .medium))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
    }
}

// MARK: - Markdown Text Formatting Logic

public struct MarkdownFormatter: Sendable {
    public init() {}

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

        let markerLen = marker.count
        let before = selection.location >= markerLen
            ? nsText.substring(with: NSRange(location: selection.location - markerLen, length: markerLen))
            : ""
        let afterEnd = selection.location + selection.length
        let after = afterEnd + markerLen <= nsText.length
            ? nsText.substring(with: NSRange(location: afterEnd, length: markerLen))
            : ""

        if before == marker && after == marker {
            let removeRange = NSRange(location: selection.location - markerLen, length: selection.length + markerLen * 2)
            let newText = nsText.replacingCharacters(in: removeRange, with: selectedText)
            return (newText, NSRange(location: selection.location - markerLen, length: selectedText.count))
        } else {
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
        let lineRange = nsText.lineRange(for: selection)
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            let newLine = String(line.dropFirst(prefix.count))
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            let newLoc = max(selection.location - prefix.count, lineRange.location)
            return (newText, NSRange(location: newLoc, length: 0))
        } else {
            let newLine = prefix + line
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: selection.location + prefix.count, length: 0))
        }
    }
}
