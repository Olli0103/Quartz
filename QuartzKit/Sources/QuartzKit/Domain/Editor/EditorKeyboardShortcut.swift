import Foundation

public enum EditorKeyboardShortcut: Equatable, Sendable {
    case formatting(FormattingAction)
    case paste(EditorPasteMode)
}

public struct EditorKeyboardShortcutResolver {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let command = Self(rawValue: 1 << 0)
        public static let shift = Self(rawValue: 1 << 1)
        public static let alternate = Self(rawValue: 1 << 2)
    }

    private struct Signature: Hashable {
        let input: String
        let modifiers: Modifiers
    }

    private static let shortcuts: [Signature: EditorKeyboardShortcut] = [
        .init(input: "b", modifiers: .command): .formatting(.bold),
        .init(input: "i", modifiers: .command): .formatting(.italic),
        .init(input: "x", modifiers: [.command, .shift]): .formatting(.strikethrough),
        .init(input: "0", modifiers: .command): .formatting(.paragraph),
        .init(input: "1", modifiers: .command): .formatting(.heading1),
        .init(input: "2", modifiers: .command): .formatting(.heading2),
        .init(input: "3", modifiers: .command): .formatting(.heading3),
        .init(input: "4", modifiers: .command): .formatting(.heading4),
        .init(input: "5", modifiers: .command): .formatting(.heading5),
        .init(input: "6", modifiers: .command): .formatting(.heading6),
        .init(input: "e", modifiers: [.command, .alternate]): .formatting(.code),
        .init(input: "e", modifiers: [.command, .shift]): .formatting(.codeBlock),
        .init(input: "l", modifiers: [.command, .shift]): .formatting(.link),
        .init(input: "q", modifiers: [.command, .shift]): .formatting(.blockquote),
        .init(input: "v", modifiers: [.command, .alternate]): .paste(.smart),
        .init(input: "v", modifiers: [.command, .shift]): .paste(.raw)
    ]

    public static func resolve(input: String, modifiers: Modifiers) -> EditorKeyboardShortcut? {
        shortcuts[.init(input: input.lowercased(), modifiers: modifiers)]
    }
}
