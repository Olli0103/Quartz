import Foundation
import os

/// Service for fetching, reading, and restoring NSFileVersion snapshots of notes.
///
/// Uses Apple's built-in versioning system (NSFileVersion) which automatically creates
/// snapshots when files are saved. Works with both local and iCloud Drive vaults.
public struct VersionHistoryService: Sendable {
    private static let logger = Logger(subsystem: "com.quartz", category: "VersionHistory")

    public init() {}

    /// Fetches all available versions for a file, sorted newest first.
    /// Includes both resolved versions (auto-saved snapshots) and the current version.
    public func fetchVersions(for url: URL) -> [NoteVersion] {
        guard let others = NSFileVersion.otherVersionsOfItem(at: url) else { return [] }

        return others
            .filter { $0.modificationDate != nil }
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
            .enumerated()
            .map { index, version in
                NoteVersion(
                    id: index,
                    version: version,
                    date: version.modificationDate ?? Date(),
                    deviceName: version.localizedNameOfSavingComputer
                )
            }
    }

    /// Reads the text content of a historical version using coordinated access.
    public func readText(from version: NSFileVersion) throws -> String {
        let url = version.url
        var result: String?
        var readError: Error?

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { actualURL in
            do {
                let data = try Data(contentsOf: actualURL)
                result = String(data: data, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        if let error = coordinatorError ?? readError {
            throw error
        }
        guard let text = result else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    /// Restores a historical version, replacing the current file content.
    /// After calling this, the editor should reload from disk.
    public func restore(version: NSFileVersion, to originalURL: URL) throws {
        var coordinatorError: NSError?
        var restoreError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: originalURL, options: .forReplacing, error: &coordinatorError) { actualURL in
            do {
                try version.replaceItem(at: actualURL, options: [])
            } catch {
                restoreError = error
            }
        }

        if let error = coordinatorError ?? restoreError {
            throw error
        }

        Self.logger.info("Restored version from \(version.modificationDate?.description ?? "unknown") to \(originalURL.lastPathComponent)")
    }
}

/// A displayable version snapshot of a note.
/// `@unchecked Sendable` because `NSFileVersion` is thread-safe for reading but not marked Sendable.
public struct NoteVersion: Identifiable, @unchecked Sendable {
    public let id: Int
    public let version: NSFileVersion
    public let date: Date
    public let deviceName: String?
}
