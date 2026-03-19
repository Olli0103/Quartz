import Foundation

/// Toggles a GFM task (`- [ ]` ↔ `- [x]`) in the underlying .md file without opening the note.
///
/// Uses `CoordinatedFileWriter` for iCloud-safe writes.
public struct DashboardTaskToggleService: Sendable {
    private let writer: CoordinatedFileWriter

    public init(writer: CoordinatedFileWriter = .shared) {
        self.writer = writer
    }

    /// Marks the task as completed (`- [x]`) or uncompleted (`- [ ]`).
    /// - Returns: `true` if the file was updated successfully.
    public func toggleTask(_ item: DashboardTaskItem, toCompleted completed: Bool) async throws -> Bool {
        let data = try writer.read(from: item.noteURL)
        guard let content = String(data: data, encoding: .utf8) else { return false }

        let lines = content.components(separatedBy: .newlines)
        let lineIndex = item.lineNumber - 1
        guard lineIndex >= 0, lineIndex < lines.count else { return false }

        let oldLine = lines[lineIndex]
        let newLine: String
        if completed {
            newLine = oldLine.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else {
            newLine = oldLine.replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
        }
        guard newLine != oldLine else { return false }

        var newLines = lines
        newLines[lineIndex] = newLine
        let newContent = newLines.joined(separator: "\n")
        try writer.write((newContent.data(using: .utf8) ?? Data()), to: item.noteURL)
        return true
    }
}
