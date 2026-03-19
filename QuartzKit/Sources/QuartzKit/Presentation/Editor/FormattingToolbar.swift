import SwiftUI

/// Markdown formatting actions.
public enum FormattingAction: String, CaseIterable, Sendable {
    case bold, italic, strikethrough, heading, bulletList, numberedList, checkbox
    case code, codeBlock, link, image, blockquote, highlight
    case table, math, footnote, mermaid

    var icon: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .heading: "textformat.size.larger"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checkbox: "checklist"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "terminal"
        case .link: "link"
        case .image: "photo"
        case .blockquote: "text.quote"
        case .highlight: "highlighter"
        case .table: "tablecells"
        case .math: "function"
        case .footnote: "number"
        case .mermaid: "chart.bar.doc.horizontal"
        }
    }

    /// Keyboard shortcut for help text, e.g. "⌘B".
    var shortcut: String? {
        switch self {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .strikethrough: "⌘⇧X"
        case .heading: "⌘⇧H"
        case .code: "⌘E"
        case .link: "⌘⇧L"
        case .blockquote: "⌘⇧Q"
        default: nil
        }
    }

    var label: String {
        switch self {
        case .bold: String(localized: "Bold", bundle: .module)
        case .italic: String(localized: "Italic", bundle: .module)
        case .strikethrough: String(localized: "Strikethrough", bundle: .module)
        case .heading: String(localized: "Heading", bundle: .module)
        case .bulletList: String(localized: "Bullet List", bundle: .module)
        case .numberedList: String(localized: "Numbered List", bundle: .module)
        case .checkbox: String(localized: "Checkbox", bundle: .module)
        case .code: String(localized: "Inline Code", bundle: .module)
        case .codeBlock: String(localized: "Code Block", bundle: .module)
        case .link: String(localized: "Link", bundle: .module)
        case .image: String(localized: "Image", bundle: .module)
        case .blockquote: String(localized: "Quote", bundle: .module)
        case .highlight: String(localized: "Highlight", bundle: .module)
        case .table: String(localized: "Table", bundle: .module)
        case .math: String(localized: "Math", bundle: .module)
        case .footnote: String(localized: "Footnote", bundle: .module)
        case .mermaid: String(localized: "Mermaid Diagram", bundle: .module)
        }
    }

    var markdownSyntax: MarkdownSyntax {
        switch self {
        case .bold: .wrap("**")
        case .italic: .wrap("*")
        case .strikethrough: .wrap("~~")
        case .heading: .linePrefix("# ")
        case .bulletList: .linePrefix("- ")
        case .numberedList: .linePrefix("1. ")
        case .checkbox: .linePrefix("- [ ] ")
        case .code: .wrap("`")
        case .codeBlock: .block("```\n", "\n```")
        case .link: .template("[", "](url)")
        case .image: .template("![", "](path)")
        case .blockquote: .linePrefix("> ")
        case .highlight: .wrap("==")
        case .table: .insert("| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell 1 | Cell 2 | Cell 3 |\n")
        case .math: .wrap("$")
        case .footnote: .template("[^", "]: ")
        case .mermaid: .block("```mermaid\n", "\n```")
        }
    }
}

public enum MarkdownSyntax: Sendable {
    case wrap(String)
    case linePrefix(String)
    case block(String, String)
    case template(String, String)
    case insert(String)
}

// MARK: - Formatting Toolbar View

/// Icon and divider sizes – larger on macOS for better legibility.
private var formatBarIconSize: CGFloat {
    #if os(macOS)
    17
    #else
    14
    #endif
}

private var formatBarIconWeight: Font.Weight {
    #if os(macOS)
    .semibold
    #else
    .medium
    #endif
}

private var formatBarDividerHeight: CGFloat {
    #if os(macOS)
    22
    #else
    18
    #endif
}

public struct FormattingToolbar: View {
    let onAction: (FormattingAction) -> Void

    private let primaryActions: [FormattingAction] = [
        .bold, .italic, .strikethrough, .heading, .bulletList, .checkbox, .code, .link
    ]
    private let secondaryActions: [FormattingAction] = [
        .numberedList, .codeBlock, .image, .blockquote, .highlight, .table, .math, .footnote, .mermaid
    ]

    public init(onAction: @escaping (FormattingAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryActions, id: \.self) { action in
                    FormatButton(action: action) {
                        onAction(action)
                    }
                }

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: formatBarDividerHeight)
                    .padding(.horizontal, 8)

                Menu {
                    ForEach(secondaryActions, id: \.self) { action in
                        Button { onAction(action) } label: {
                            Label(action.label, systemImage: action.icon)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: formatBarIconSize, weight: formatBarIconWeight))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(String(localized: "More formatting options", bundle: .module))
                .help(String(localized: "More formatting options", bundle: .module))
            }
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 44)
    }
}

/// Individual formatting button with explicit hover + press visual feedback.
private struct FormatButton: View {
    let action: FormattingAction
    let onTap: () -> Void
    @Environment(\.appearanceManager) private var appearance
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: action.icon)
            .font(.system(size: formatBarIconSize, weight: formatBarIconWeight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPressed ? appearance.accentColor : isHovered ? .primary : .secondary)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in isHovered = hovering }
            .onTapGesture { onTap() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel(action.label)
            .help(helpText)
    }

    private var helpText: String {
        if let shortcut = action.shortcut {
            return "\(action.label) (\(shortcut))"
        }
        return action.label
    }

    private var backgroundColor: Color {
        if isPressed { return appearance.accentColor.opacity(0.2) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
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
            return (newText, NSRange(location: selectedRange.location + open.count, length: selectedText.count))
        case .template(let before, let after):
            let replacement = "\(before)\(selectedText)\(after)"
            let newText = nsText.replacingCharacters(in: selectedRange, with: replacement)
            if selectedText.isEmpty {
                return (newText, NSRange(location: selectedRange.location + before.count, length: 0))
            } else {
                return (newText, NSRange(location: selectedRange.location + before.count + selectedText.count + after.count, length: 0))
            }
        case .insert(let raw):
            let newText = nsText.replacingCharacters(in: selectedRange, with: raw)
            return (newText, NSRange(location: selectedRange.location + raw.count, length: 0))
        }
    }

    private func applyWrap(_ marker: String, text: String, selection: NSRange, selectedText: String) -> (String, NSRange) {
        let nsText = text as NSString
        let mLen = marker.count
        let before = selection.location >= mLen
            ? nsText.substring(with: NSRange(location: selection.location - mLen, length: mLen)) : ""
        let afterEnd = selection.location + selection.length
        let after = afterEnd + mLen <= nsText.length
            ? nsText.substring(with: NSRange(location: afterEnd, length: mLen)) : ""

        if before == marker && after == marker {
            let removeRange = NSRange(location: selection.location - mLen, length: selection.length + mLen * 2)
            let newText = nsText.replacingCharacters(in: removeRange, with: selectedText)
            return (newText, NSRange(location: selection.location - mLen, length: selectedText.count))
        } else {
            let replacement = "\(marker)\(selectedText)\(marker)"
            let newText = nsText.replacingCharacters(in: selection, with: replacement)
            return (newText, NSRange(location: selection.location + mLen, length: selectedText.count))
        }
    }

    private func applyLinePrefix(_ prefix: String, text: String, selection: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: selection)
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            let newLine = String(line.dropFirst(prefix.count))
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: max(selection.location - prefix.count, lineRange.location), length: 0))
        } else {
            let newLine = prefix + line
            let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
            return (newText, NSRange(location: selection.location + prefix.count, length: 0))
        }
    }
}
