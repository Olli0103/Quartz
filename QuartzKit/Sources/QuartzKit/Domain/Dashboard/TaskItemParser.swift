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
    /// Regex for GFM task list: `- [ ]` or `- [x]` or `- [X]` followed by task text.
    private static let taskPattern = #/- \[([ xX])\]\s*(.+)/

    /// Extracts open (unchecked) task items from the given body.
    public static func parseOpenTasks(from body: String, noteURL: URL, noteTitle: String) -> [DashboardTaskItem] {
        var items: [DashboardTaskItem] = []
        let lines = body.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: taskPattern) {
                let checked = String(match.1)
                let isCompleted = checked.lowercased() == "x"
                guard !isCompleted else { continue }
                let taskText = String(match.2).trimmingCharacters(in: .whitespaces)
                guard !taskText.isEmpty else { continue }
                items.append(DashboardTaskItem(
                    text: taskText,
                    isCompleted: false,
                    noteURL: noteURL,
                    noteTitle: noteTitle,
                    lineNumber: index + 1,
                    lineContent: line
                ))
            }
        }
        return items
    }
}
