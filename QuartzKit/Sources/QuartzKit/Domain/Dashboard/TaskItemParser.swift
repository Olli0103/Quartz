import Foundation

/// A parsed GFM task item (`- [ ]` or `- [x]`) from a vault note.
public struct DashboardTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let isCompleted: Bool
    public let noteURL: URL
    public let noteTitle: String
    /// 1-based line number for precise in-file replacement.
    public let lineNumber: Int
    /// Full line content for replacement (e.g. `- [ ] task` → `- [x] task`).
    public let lineContent: String

    public init(
        id: UUID = UUID(),
        text: String,
        isCompleted: Bool,
        noteURL: URL,
        noteTitle: String,
        lineNumber: Int,
        lineContent: String
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.noteURL = noteURL
        self.noteTitle = noteTitle
        self.lineNumber = lineNumber
        self.lineContent = lineContent
    }
}

/// Parses `- [ ]` and `- [x]` task items from markdown note bodies.
public enum TaskItemParser: Sendable {
    /// Returns checkbox marker (` `, `x`, or `X`) and task text after `]`, or nil if not a GFM task line.
    private static func parseTaskLine(_ trimmed: String) -> (marker: Character, taskText: String)? {
        let prefix = "- ["
        guard trimmed.hasPrefix(prefix) else { return nil }
        var rest = trimmed.dropFirst(prefix.count)
        guard let marker = rest.first, marker == " " || marker == "x" || marker == "X" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == "]" else { return nil }
        rest = rest.dropFirst()
        while let c = rest.first, c.isWhitespace { rest = rest.dropFirst() }
        let taskText = String(rest)
        guard !taskText.isEmpty else { return nil }
        return (marker, taskText)
    }

    /// Extracts open (unchecked) task items from the given body.
    public static func parseOpenTasks(from body: String, noteURL: URL, noteTitle: String) -> [DashboardTaskItem] {
        var items: [DashboardTaskItem] = []
        let lines = body.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let (marker, taskText) = parseTaskLine(trimmed) else { continue }
            let isCompleted = marker != " "
            guard !isCompleted else { continue }
            items.append(DashboardTaskItem(
                text: taskText,
                isCompleted: false,
                noteURL: noteURL,
                noteTitle: noteTitle,
                lineNumber: index + 1,
                lineContent: line
            ))
        }
        return items
    }
}
