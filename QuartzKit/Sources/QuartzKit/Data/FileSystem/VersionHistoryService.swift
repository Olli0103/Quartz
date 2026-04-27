import Foundation
import os
import CryptoKit

/// Errors specific to version history operations.
public enum VersionHistoryError: LocalizedError, Sendable {
    case snapshotNotFound
    case noteNotFound
    case coordinationFailed(String)
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .snapshotNotFound:
            return String(localized: "The version snapshot no longer exists.", bundle: .module)
        case .noteNotFound:
            return String(localized: "The original note was deleted.", bundle: .module)
        case .coordinationFailed(let reason):
            return String(localized: "File coordination failed: \(reason)", bundle: .module)
        case .decryptionFailed:
            return String(localized: "Failed to decrypt version snapshot.", bundle: .module)
        }
    }
}

/// A displayable version snapshot of a note.
public struct NoteVersion: Identifiable, Sendable {
    public let id: Int
    public let snapshotURL: URL
    public let date: Date
    /// Whether this snapshot is encrypted.
    public let isEncrypted: Bool

    public init(id: Int, snapshotURL: URL, date: Date, isEncrypted: Bool = false) {
        self.id = id
        self.snapshotURL = snapshotURL
        self.date = date
        self.isEncrypted = isEncrypted
    }
}

public extension Notification.Name {
    /// Posted after a note's version-history snapshot set changes.
    /// `object` is the note URL and `userInfo["vaultRoot"]` is the vault root URL.
    static let quartzVersionHistoryDidChange = Notification.Name("quartzVersionHistoryDidChange")
}

/// Lightweight version history for Markdown notes.
///
/// Since `NSFileVersion` only works for iCloud-synced or NSDocument-managed files,
/// Quartz manages its own version snapshots in `{vault}/.quartz/versions/{noteID}/`.
///
/// A snapshot is saved every time the editor auto-saves. Old snapshots beyond the
/// retention limit are pruned automatically.
///
/// ## Thread Safety
///
/// All file operations use `NSFileCoordinator` for iCloud safety.
/// Methods are designed to be called from background threads.
///
/// ## Security
///
/// When an encryption key is provided, snapshots are encrypted with AES-256-GCM
/// before being written to disk. Encrypted snapshots use the `.md.enc` extension
/// while plaintext snapshots use `.md`.
public struct VersionHistoryService: Sendable {
    private static let logger = Logger(subsystem: "com.quartz", category: "VersionHistory")

    /// Maximum snapshots kept per note.
    public static let maxSnapshotsPerNote = 50

    /// Maximum bytes to read for preview (512KB).
    public static let maxPreviewBytes = 512_000

    /// File extension for encrypted snapshots.
    private static let encryptedExtension = "md.enc"

    /// File extension for unencrypted snapshots.
    private static let plainExtension = "md"

    public init() {}

    // MARK: - Snapshot Creation

    /// Saves a snapshot of the current note content.
    /// Called by EditorSession after each save. Runs on a background thread.
    ///
    /// - Parameters:
    ///   - noteURL: The URL of the note being saved.
    ///   - content: The current text content of the note.
    ///   - vaultRoot: The root URL of the vault.
    ///   - encryptionKey: Optional encryption key. If provided, snapshot is encrypted with AES-256-GCM.
    ///
    /// - Note: Uses `NSFileCoordinator` for iCloud safety.
    @discardableResult
    public func saveSnapshot(
        for noteURL: URL,
        content: String,
        vaultRoot: URL,
        encryptionKey: SymmetricKey? = nil
    ) -> Bool {
        let snapshotDir = snapshotDirectory(for: noteURL, vaultRoot: vaultRoot)
        let fm = FileManager.default

        // Ensure directory exists
        do {
            try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Failed to create snapshot directory: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VersionHistory",
                "Failed to create snapshot directory: \(error.localizedDescription)"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "snapshotFailed",
                reasonCode: "version.snapshotFailed",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["error": error.localizedDescription]
            )
            return false
        }

        if encryptionKey == nil,
           let latest = fetchVersions(for: noteURL, vaultRoot: vaultRoot).first,
           (try? readFullText(from: latest)) == content {
            QuartzDiagnostics.info(
                category: "VersionHistory",
                "Skipped duplicate snapshot for \(noteURL.lastPathComponent)"
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "snapshotSkippedDuplicate",
                reasonCode: "version.snapshotSkippedDuplicate",
                noteBasename: noteURL.lastPathComponent
            )
            return false
        }

        // Create snapshot with ISO8601 timestamp filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        // Use different extension for encrypted vs plain snapshots
        let fileExtension = encryptionKey != nil ? Self.encryptedExtension : Self.plainExtension
        let snapshotURL = snapshotDir.appending(path: "\(timestamp)__\(UUID().uuidString).\(fileExtension)")

        guard var data = content.data(using: .utf8) else {
            Self.logger.error("Failed to encode snapshot content as UTF-8")
            QuartzDiagnostics.error(
                category: "VersionHistory",
                "Failed to encode snapshot content as UTF-8"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "snapshotFailed",
                reasonCode: "version.snapshotFailed",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["error": "utf8EncodingFailed"]
            )
            return false
        }

        // Encrypt if key is provided
        if let key = encryptionKey {
            do {
                let sealedBox = try AES.GCM.seal(data, using: key)
                guard let combined = sealedBox.combined else {
                    Self.logger.error("Failed to combine encrypted snapshot data")
                    QuartzDiagnostics.error(
                        category: "VersionHistory",
                        "Failed to combine encrypted snapshot data"
                    )
                    return false
                }
                data = combined
            } catch {
                Self.logger.error("Failed to encrypt snapshot: \(error.localizedDescription)")
                QuartzDiagnostics.error(
                    category: "VersionHistory",
                    "Failed to encrypt snapshot: \(error.localizedDescription)"
                )
                return false
            }
        }

        // Use file coordination for iCloud safety
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeSucceeded = false

        coordinator.coordinate(writingItemAt: snapshotURL, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
                writeSucceeded = true
            } catch {
                Self.logger.error("Failed to write snapshot: \(error.localizedDescription)")
                QuartzDiagnostics.error(
                    category: "VersionHistory",
                    "Failed to write snapshot: \(error.localizedDescription)"
                )
            }
        }

        if let error = coordinatorError {
            Self.logger.error("File coordination failed for snapshot: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VersionHistory",
                "File coordination failed for snapshot: \(error.localizedDescription)"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "snapshotFailed",
                reasonCode: "version.snapshotFailed",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["error": error.localizedDescription]
            )
            return false
        }

        guard writeSucceeded else {
            QuartzDiagnostics.error(
                category: "VersionHistory",
                "Snapshot write did not complete for \(noteURL.lastPathComponent)"
            )
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "snapshotFailed",
                reasonCode: "version.snapshotFailed",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["error": "writeDidNotComplete"]
            )
            return false
        }

        // Prune old snapshots (async to avoid blocking)
        Task.detached(priority: .utility) { [self] in
            self.pruneSnapshots(in: snapshotDir, keep: Self.maxSnapshotsPerNote)
        }

        NotificationCenter.default.post(
            name: .quartzVersionHistoryDidChange,
            object: noteURL,
            userInfo: ["vaultRoot": vaultRoot]
        )
        QuartzDiagnostics.info(
            category: "VersionHistory",
            "Created snapshot for \(noteURL.lastPathComponent)"
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "snapshotCreated",
            reasonCode: "version.snapshotCreated",
            noteBasename: noteURL.lastPathComponent,
            metadata: ["snapshotStorage": snapshotURL.lastPathComponent]
        )
        return true
    }

    // MARK: - Fetch Versions

    /// Returns all saved snapshots for a note, sorted newest first.
    ///
    /// - Note: File system errors are logged but do not throw — returns empty array on failure.
    public func fetchVersions(for noteURL: URL, vaultRoot: URL) -> [NoteVersion] {
        let snapshotDir = snapshotDirectory(for: noteURL, vaultRoot: vaultRoot)
        let fm = FileManager.default

        guard fm.fileExists(atPath: snapshotDir.path(percentEncoded: false)) else { return [] }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: snapshotDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.error("Failed to list version snapshots: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "VersionHistory",
                "Failed to list version snapshots: \(error.localizedDescription)"
            )
            return []
        }

        // Accept both .md (plain) and .md.enc (encrypted) files
        return contents
            .filter { url in
                let ext = url.pathExtension
                let name = url.lastPathComponent
                return ext == Self.plainExtension || name.hasSuffix(".\(Self.encryptedExtension)")
            }
            .compactMap { url -> (URL, Date, Bool)? in
                // Resource value read failure is non-fatal — use current date as fallback
                let mdate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let isEncrypted = url.lastPathComponent.hasSuffix(".\(Self.encryptedExtension)")
                return (url, mdate, isEncrypted)
            }
            .sorted { $0.1 > $1.1 }
            .enumerated()
            .map { index, tuple in
                NoteVersion(id: index, snapshotURL: tuple.0, date: tuple.1, isEncrypted: tuple.2)
            }
    }

    // MARK: - Read Version

    /// Reads the text content of a snapshot with bounded size for preview safety.
    ///
    /// - Parameters:
    ///   - version: The version to read.
    ///   - encryptionKey: Optional decryption key. Required if the snapshot is encrypted.
    ///   - maxBytes: Maximum bytes to read (default 512KB). Pass `Int.max` for full content.
    /// - Returns: The text content, truncated if larger than `maxBytes`.
    /// - Throws: `VersionHistoryError.decryptionFailed` if the snapshot is encrypted but no key is provided.
    public func readText(
        from version: NoteVersion,
        encryptionKey: SymmetricKey? = nil,
        maxBytes: Int = maxPreviewBytes
    ) throws -> String {
        // For encrypted files, we need to read the whole file to decrypt
        if version.isEncrypted {
            guard let key = encryptionKey else {
                throw VersionHistoryError.decryptionFailed
            }

            let encryptedData = try Data(contentsOf: version.snapshotURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)

            guard var text = String(data: decryptedData, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            // Truncate if needed
            if decryptedData.count > maxBytes {
                let truncatedData = decryptedData.prefix(maxBytes)
                if let truncatedText = String(data: truncatedData, encoding: .utf8) {
                    text = truncatedText
                    if let lastNewline = text.lastIndex(of: "\n") {
                        text = String(text[..<lastNewline])
                    }
                    text += "\n\n---\n*[Preview truncated — file exceeds 500KB]*"
                }
            }

            return text
        }

        // Unencrypted file — use streaming read for large file safety
        let handle = try FileHandle(forReadingFrom: version.snapshotURL)
        defer { try? handle.close() }

        guard let data = try handle.read(upToCount: maxBytes) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard var text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Check if we hit the limit (file is larger)
        if data.count == maxBytes {
            // Try to find a good break point (end of line)
            if let lastNewline = text.lastIndex(of: "\n") {
                text = String(text[..<lastNewline])
            }
            text += "\n\n---\n*[Preview truncated — file exceeds 500KB]*"
        }

        return text
    }

    /// Reads the full text content of a snapshot (for restore operations).
    ///
    /// - Parameters:
    ///   - version: The version to read.
    ///   - encryptionKey: Optional decryption key. Required if the snapshot is encrypted.
    /// - Throws: `VersionHistoryError.decryptionFailed` if the snapshot is encrypted but no key is provided.
    public func readFullText(from version: NoteVersion, encryptionKey: SymmetricKey? = nil) throws -> String {
        var data = try Data(contentsOf: version.snapshotURL)

        // Decrypt if needed
        if version.isEncrypted {
            guard let key = encryptionKey else {
                throw VersionHistoryError.decryptionFailed
            }
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            data = try AES.GCM.open(sealedBox, using: key)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    // MARK: - Restore Version

    /// Restores a snapshot by overwriting the current note file.
    ///
    /// Uses `NSFileCoordinator` for iCloud safety and to prevent race conditions
    /// with Finder, other apps, or sync operations.
    ///
    /// - Parameters:
    ///   - version: The version to restore.
    ///   - noteURL: The URL of the note to overwrite.
    ///   - encryptionKey: Optional decryption key. Required if the snapshot is encrypted.
    ///
    /// - Throws: File system errors, coordination errors, or if files don't exist.
    public func restore(version: NoteVersion, to noteURL: URL, encryptionKey: SymmetricKey? = nil) async throws {
        let fm = FileManager.default

        // Validate snapshot exists
        guard fm.fileExists(atPath: version.snapshotURL.path(percentEncoded: false)) else {
            throw VersionHistoryError.snapshotNotFound
        }

        // Validate target note exists
        guard fm.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            throw VersionHistoryError.noteNotFound
        }

        // Read snapshot content (full, not truncated)
        var data = try Data(contentsOf: version.snapshotURL)

        // Decrypt if needed
        if version.isEncrypted {
            guard let key = encryptionKey else {
                throw VersionHistoryError.decryptionFailed
            }
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            data = try AES.GCM.open(sealedBox, using: key)
        }

        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.write(data, to: noteURL)
        }.value
        Self.logger.info("Restored version from \(version.date.formatted()) to \(noteURL.lastPathComponent)")
    }

    // MARK: - Helpers

    /// Directory for a note's snapshots: `{vault}/.quartz/versions/{noteID}/`
    ///
    /// Uses a hash of the relative path to ensure uniqueness — two notes named
    /// "Meeting Notes.md" in different folders will have different version histories.
    private func snapshotDirectory(for noteURL: URL, vaultRoot: URL) -> URL {
        let noteID = stableNoteID(for: noteURL, vaultRoot: vaultRoot)
        return vaultRoot
            .appending(path: ".quartz")
            .appending(path: "versions")
            .appending(path: noteID)
    }

    /// Generates a stable, unique identifier for a note based on its relative path.
    ///
    /// This ensures that:
    /// - Same-name files in different folders have different IDs
    /// - IDs are filesystem-safe (no special characters)
    /// - IDs are stable and collision-resistant (SHA256 hash)
    private func stableNoteID(for noteURL: URL, vaultRoot: URL) -> String {
        let rootPath = vaultRoot.standardizedFileURL.path(percentEncoded: false)
        let notePath = noteURL.standardizedFileURL.path(percentEncoded: false)

        // Get relative path from vault root
        let relativePath: String
        if notePath.hasPrefix(rootPath) {
            relativePath = String(notePath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relativePath = noteURL.lastPathComponent
        }

        // Create a stable SHA256 hash of the relative path
        guard let data = relativePath.data(using: .utf8) else {
            return sanitizeFilename(noteURL.deletingPathExtension().lastPathComponent)
        }

        let hash = SHA256.hash(data: data)
        // Use full hex representation (64 chars) for collision resistance
        let hexString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return hexString
    }

    /// Sanitizes a filename for use as a directory name.
    private func sanitizeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    /// Removes oldest snapshots beyond the keep limit.
    ///
    /// - Note: Runs on a background thread. Errors are logged but do not propagate.
    private func pruneSnapshots(in directory: URL, keep: Int) {
        let fm = FileManager.default

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.warning("Failed to list snapshots for pruning: \(error.localizedDescription)")
            return
        }

        let sorted = files.sorted { a, b in
            // Resource value read failure is non-fatal — use distantPast as fallback
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate > bDate
        }

        // Remove everything beyond the keep limit
        for file in sorted.dropFirst(keep) {
            do {
                try fm.removeItem(at: file)
            } catch {
                Self.logger.warning("Failed to prune old snapshot \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
