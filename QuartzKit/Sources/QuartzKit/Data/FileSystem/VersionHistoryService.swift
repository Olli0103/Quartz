import Foundation
import os

/// Lightweight version history for Markdown notes.
///
/// Since `NSFileVersion` only works for iCloud-synced or NSDocument-managed files,
/// Quartz manages its own version snapshots in `{vault}/.quartz/versions/{noteID}/`.
///
/// A snapshot is saved every time the editor auto-saves. Old snapshots beyond the
/// retention limit are pruned automatically.
public struct VersionHistoryService: Sendable {
    private static let logger = Logger(subsystem: "com.quartz", category: "VersionHistory")

    /// Maximum snapshots kept per note.
    public static let maxSnapshotsPerNote = 50

    public init() {}

    // MARK: - Snapshot Creation

    /// Saves a snapshot of the current note content.
    /// Called by EditorSession after each save.
    public func saveSnapshot(for noteURL: URL, content: String, vaultRoot: URL) {
        let snapshotDir = snapshotDirectory(for: noteURL, vaultRoot: vaultRoot)
        let fm = FileManager.default

        // Ensure directory exists
        try? fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        // Create snapshot with ISO8601 timestamp filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let snapshotURL = snapshotDir.appending(path: "\(timestamp).md")

        guard let data = content.data(using: .utf8) else { return }
        try? data.write(to: snapshotURL, options: .atomic)

        // Prune old snapshots
        pruneSnapshots(in: snapshotDir, keep: Self.maxSnapshotsPerNote)
    }

    // MARK: - Fetch Versions

    /// Returns all saved snapshots for a note, sorted newest first.
    public func fetchVersions(for noteURL: URL, vaultRoot: URL) -> [NoteVersion] {
        let snapshotDir = snapshotDirectory(for: noteURL, vaultRoot: vaultRoot)
        let fm = FileManager.default

        guard fm.fileExists(atPath: snapshotDir.path(percentEncoded: false)) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: snapshotDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> (URL, Date)? in
                let mdate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return (url, mdate)
            }
            .sorted { $0.1 > $1.1 }
            .enumerated()
            .map { index, pair in
                NoteVersion(id: index, snapshotURL: pair.0, date: pair.1)
            }
    }

    // MARK: - Read Version

    /// Reads the text content of a snapshot.
    public func readText(from version: NoteVersion) throws -> String {
        let data = try Data(contentsOf: version.snapshotURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    // MARK: - Restore Version

    /// Restores a snapshot by overwriting the current note file.
    public func restore(version: NoteVersion, to noteURL: URL) throws {
        let data = try Data(contentsOf: version.snapshotURL)
        try data.write(to: noteURL, options: .atomic)
        Self.logger.info("Restored version from \(version.date.formatted()) to \(noteURL.lastPathComponent)")
    }

    // MARK: - Helpers

    /// Directory for a note's snapshots: `{vault}/.quartz/versions/{noteID}/`
    private func snapshotDirectory(for noteURL: URL, vaultRoot: URL) -> URL {
        let noteID = noteURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
        return vaultRoot
            .appending(path: ".quartz")
            .appending(path: "versions")
            .appending(path: noteID)
    }

    /// Removes oldest snapshots beyond the keep limit.
    private func pruneSnapshots(in directory: URL, keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = files.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate > bDate
        }

        // Remove everything beyond the keep limit
        for file in sorted.dropFirst(keep) {
            try? fm.removeItem(at: file)
        }
    }
}

/// A displayable version snapshot of a note.
public struct NoteVersion: Identifiable, Sendable {
    public let id: Int
    public let snapshotURL: URL
    public let date: Date
}
