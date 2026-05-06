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

public struct VersionHistoryLookupStatus: Sendable, Equatable {
    public let currentNoteIdentity: String
    public let versionLookupKey: String
    public let snapshotFilesFound: Int
    public let snapshotFilesIgnored: Int
    public let lastSnapshotAt: Date?
    public let nextEligibleAt: Date?
}

private struct VersionSnapshotMetadata: Codable, Sendable, Equatable {
    let noteIdentity: String
    let versionLookupKey: String
    let snapshotStorageKey: String
    let originalRelativePath: String
    let createdAt: Date
    let contentLength: Int
    let snapshotStorage: String
}

private struct VersionLookupIdentityCandidate: Sendable, Equatable {
    let relativePath: String
    let lookupKey: String
    let storageKey: String
    let kind: String
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
        let originalRelativePath = canonicalRelativePath(for: noteURL, vaultRoot: vaultRoot)
        let lookupKey = versionLookupKey(for: noteURL, vaultRoot: vaultRoot)
        let storageKey = stableNoteID(for: noteURL, vaultRoot: vaultRoot)
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotStorageDirectory",
            reasonCode: "version.snapshotStorageDirectory",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "snapshotDirectory": snapshotDir.path(percentEncoded: false),
                "snapshotStorageKey": storageKey,
                "versionLookupKey": lookupKey,
                "originalRelativePath": originalRelativePath
            ]
        )

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
        let createdAt = Date()

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
        let snapshotFileVisibleAfterWrite = fm.fileExists(atPath: snapshotURL.path(percentEncoded: false))
        SubsystemDiagnostics.record(
            level: snapshotFileVisibleAfterWrite ? .info : .error,
            subsystem: .versionHistory,
            name: "version.snapshotFileWritten",
            reasonCode: "version.snapshotFileWritten",
            noteBasename: noteURL.lastPathComponent,
            counts: ["bytes": data.count],
            metadata: [
                "snapshotStorage": snapshotURL.lastPathComponent,
                "snapshotStorageKey": storageKey,
                "snapshotFileExists": String(snapshotFileVisibleAfterWrite)
            ]
        )

        let metadata = VersionSnapshotMetadata(
            noteIdentity: lookupKey,
            versionLookupKey: lookupKey,
            snapshotStorageKey: storageKey,
            originalRelativePath: originalRelativePath,
            createdAt: createdAt,
            contentLength: (content as NSString).length,
            snapshotStorage: snapshotURL.lastPathComponent
        )
        do {
            try writeMetadata(metadata, for: snapshotURL)
            let sidecarURL = metadataURL(for: snapshotURL)
            let sidecarVisible = fm.fileExists(atPath: sidecarURL.path(percentEncoded: false))
            SubsystemDiagnostics.record(
                level: sidecarVisible ? .info : .error,
                subsystem: .versionHistory,
                name: "version.snapshotSidecarWritten",
                reasonCode: "version.snapshotSidecarWritten",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "snapshotStorage": snapshotURL.lastPathComponent,
                    "snapshotStorageKey": storageKey,
                    "sidecarExists": String(sidecarVisible)
                ]
            )
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "version.snapshotMetadataWritten",
                reasonCode: "version.snapshotMetadataWritten",
                noteBasename: noteURL.lastPathComponent,
                counts: ["contentLength": metadata.contentLength],
                metadata: [
                    "noteIdentity": metadata.noteIdentity,
                    "versionLookupKey": metadata.versionLookupKey,
                    "snapshotStorageKey": metadata.snapshotStorageKey,
                    "originalRelativePath": metadata.originalRelativePath,
                    "snapshotStorage": metadata.snapshotStorage
                ]
            )
        } catch {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "version.snapshotMetadataMissing",
                reasonCode: "version.snapshotMetadataMissing",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "error": error.localizedDescription,
                    "snapshotStorage": snapshotURL.lastPathComponent,
                    "snapshotStorageKey": storageKey
                ]
            )
            try? fm.removeItem(at: snapshotURL)
            return false
        }
        recordPostWriteVisibility(
            snapshotURL: snapshotURL,
            snapshotDir: snapshotDir,
            noteURL: noteURL,
            storageKey: storageKey
        )

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
            metadata: [
                "snapshotStorage": snapshotURL.lastPathComponent,
                "snapshotStorageKey": storageKey,
                "noteIdentity": lookupKey,
                "versionLookupKey": lookupKey,
                "originalRelativePath": originalRelativePath
            ]
        )
        let postCreateLookup = fetchVersionsWithStatus(for: noteURL, vaultRoot: vaultRoot)
        SubsystemDiagnostics.record(
            level: postCreateLookup.versions.isEmpty ? .error : .info,
            subsystem: .versionHistory,
            name: postCreateLookup.versions.isEmpty ? "version.snapshotLookupPostCreateFailedDetailed" : "version.snapshotLookupPostCreateVerified",
            reasonCode: postCreateLookup.versions.isEmpty ? "version.snapshotLookupPostCreateFailedDetailed" : "version.snapshotLookupPostCreateVerified",
            noteBasename: noteURL.lastPathComponent,
            counts: ["snapshotFilesFound": postCreateLookup.status.snapshotFilesFound],
            metadata: [
                "versionLookupKey": lookupKey,
                "snapshotStorageKey": storageKey,
                "snapshotStorage": snapshotURL.lastPathComponent,
                "snapshotFileExists": String(fm.fileExists(atPath: snapshotURL.path(percentEncoded: false))),
                "sidecarExists": String(fm.fileExists(atPath: metadataURL(for: snapshotURL).path(percentEncoded: false)))
            ]
        )
        if postCreateLookup.versions.isEmpty {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "version.snapshotLookupPostCreateFailed",
                reasonCode: "version.snapshotLookupPostCreateFailed",
                noteBasename: noteURL.lastPathComponent,
                counts: ["snapshotFilesFound": postCreateLookup.status.snapshotFilesFound],
                metadata: [
                    "versionLookupKey": lookupKey,
                    "snapshotStorageKey": storageKey,
                    "snapshotStorage": snapshotURL.lastPathComponent
                ]
            )
        }
        return true
    }

    // MARK: - Fetch Versions

    /// Returns all saved snapshots for a note, sorted newest first.
    ///
    /// - Note: File system errors are logged but do not throw — returns empty array on failure.
    public func fetchVersions(for noteURL: URL, vaultRoot: URL) -> [NoteVersion] {
        fetchVersionsWithStatus(for: noteURL, vaultRoot: vaultRoot).versions
    }

    public func fetchVersionsWithStatus(for noteURL: URL, vaultRoot: URL) -> (versions: [NoteVersion], status: VersionHistoryLookupStatus) {
        let snapshotDir = snapshotDirectory(for: noteURL, vaultRoot: vaultRoot)
        let fm = FileManager.default
        let identity = versionLookupKey(for: noteURL, vaultRoot: vaultRoot)
        let lookupKey = versionLookupKey(for: noteURL, vaultRoot: vaultRoot)
        let storageKey = stableNoteID(for: noteURL, vaultRoot: vaultRoot)
        let originalRelativePath = canonicalRelativePath(for: noteURL, vaultRoot: vaultRoot)
        let legacyCandidates = legacyIdentityCandidates(for: noteURL, vaultRoot: vaultRoot)
        let acceptedIdentityCandidates = [
            VersionLookupIdentityCandidate(
                relativePath: originalRelativePath,
                lookupKey: lookupKey,
                storageKey: storageKey,
                kind: "current"
            )
        ] + legacyCandidates
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionLookupStarted",
            reasonCode: "version.lookupStarted",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "currentNoteIdentity": identity,
                "versionLookupKey": lookupKey,
                "originalRelativePath": originalRelativePath
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupCurrentIdentity",
            reasonCode: "version.snapshotLookupCurrentIdentity",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "currentNoteIdentity": identity,
                "versionLookupKey": lookupKey,
                "originalRelativePath": originalRelativePath
            ]
        )
        if !legacyCandidates.isEmpty {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "version.legacyIdentityFallbackStarted",
                reasonCode: "version.legacyIdentityFallbackStarted",
                noteBasename: noteURL.lastPathComponent,
                counts: ["legacyIdentityCandidateCount": legacyCandidates.count],
                metadata: ["currentNoteIdentity": identity, "versionLookupKey": lookupKey]
            )
            for candidate in legacyCandidates {
                SubsystemDiagnostics.record(
                    level: .info,
                    subsystem: .versionHistory,
                    name: "version.legacyIdentityCandidate",
                    reasonCode: "version.legacyIdentityCandidate",
                    noteBasename: noteURL.lastPathComponent,
                    metadata: [
                        "legacyRelativePath": candidate.relativePath,
                        "legacyLookupKey": candidate.lookupKey,
                        "legacyStorageKey": candidate.storageKey,
                        "legacyKind": candidate.kind
                    ]
                )
            }
        }
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupDirectory",
            reasonCode: "version.snapshotLookupDirectory",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "snapshotLookupDirectory": snapshotDir.path(percentEncoded: false),
                "snapshotStorageKey": storageKey,
                "versionLookupKey": lookupKey
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupKeyHash",
            reasonCode: "version.snapshotLookupKeyHash",
            noteBasename: noteURL.lastPathComponent,
            metadata: ["versionLookupKey": lookupKey, "snapshotLookupKeyHash": storageKey]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupStorageKey",
            reasonCode: "version.snapshotLookupStorageKey",
            noteBasename: noteURL.lastPathComponent,
            metadata: ["snapshotLookupStorageKey": storageKey]
        )

        let targetDirectoryExists = fm.fileExists(atPath: snapshotDir.path(percentEncoded: false))
        if !targetDirectoryExists {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .versionHistory,
                name: "version.snapshotDirectoryMissing",
                reasonCode: "version.snapshotDirectoryMissing",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "snapshotLookupDirectory": snapshotDir.path(percentEncoded: false),
                    "snapshotStorageKey": storageKey
                ]
            )
        }

        guard targetDirectoryExists || fm.fileExists(atPath: versionsRoot(for: vaultRoot).path(percentEncoded: false)) else {
            let status = VersionHistoryLookupStatus(
                currentNoteIdentity: identity,
                versionLookupKey: lookupKey,
                snapshotFilesFound: 0,
                snapshotFilesIgnored: 0,
                lastSnapshotAt: nil,
                nextEligibleAt: nil
            )
            recordLookupCompleted(status: status, noteURL: noteURL, emptyReason: "snapshotDirectoryMissing")
            recordLookup(status: status, noteURL: noteURL)
            return ([], status)
        }

        let directContents = directoryContentsWithVisibilityRetry(
            in: snapshotDir,
            noteURL: noteURL,
            storageKey: storageKey,
            retryIfEmpty: targetDirectoryExists
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupDirectCandidateCount",
            reasonCode: "version.snapshotLookupDirectCandidateCount",
            noteBasename: noteURL.lastPathComponent,
            counts: ["directCandidateCount": directContents.count],
            metadata: [
                "snapshotStorageKey": storageKey,
                "snapshotLookupDirectory": snapshotDir.path(percentEncoded: false)
            ]
        )
        let legacyContents = legacyCandidates.flatMap { candidate -> [URL] in
            directoryContents(
                in: versionsRoot(for: vaultRoot).appending(path: candidate.storageKey)
            )
        }
        let contents = uniqueSnapshotCandidateURLs(
            directContents + legacyContents + allVersionSnapshotCandidates(in: vaultRoot)
        )
        let snapshotCandidates = contents.filter { url in
            let ext = url.pathExtension
            let name = url.lastPathComponent
            return ext == Self.plainExtension || name.hasSuffix(".\(Self.encryptedExtension)")
        }
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupCandidateCount",
            reasonCode: "version.snapshotLookupCandidateCount",
            noteBasename: noteURL.lastPathComponent,
            counts: ["candidateCount": snapshotCandidates.count],
            metadata: ["snapshotStorageKey": storageKey, "targetDirectoryExists": String(targetDirectoryExists)]
        )

        // Accept both .md (plain) and .md.enc (encrypted) files
        var acceptedTuples: [(URL, Date, Bool)] = []
        var ignoredCount = 0
        var legacyMatchCount = 0
        for url in snapshotCandidates {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "version.snapshotLookupCandidateFile",
                reasonCode: "version.snapshotLookupCandidateFile",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "snapshotStorage": url.lastPathComponent,
                    "candidateDirectory": url.deletingLastPathComponent().lastPathComponent,
                    "expectedStorageKey": storageKey
                ],
                verbose: true
            )
            let metadata = readMetadata(for: url, noteURL: noteURL)
            let parentDirectory = url.deletingLastPathComponent().standardizedFileURL
            let isInTargetDirectory = parentDirectory == snapshotDir.standardizedFileURL
            let directoryMatchedCandidate = acceptedIdentityCandidates.first { candidate in
                parentDirectory.lastPathComponent == candidate.storageKey
            }
            if let metadata {
                let matchedCandidate = acceptedIdentityCandidates.first { candidate in
                    metadata.versionLookupKey == candidate.lookupKey
                        && metadata.snapshotStorageKey == candidate.storageKey
                        && metadata.originalRelativePath == candidate.relativePath
                }
                if matchedCandidate == nil {
                    ignoredCount += 1
                    recordLookupCandidateRejected(
                        url,
                        noteURL: noteURL,
                        reason: "metadataKeyMismatch",
                        metadata: metadata,
                        expectedLookupKey: lookupKey
                    )
                    continue
                }
                if let matchedCandidate, matchedCandidate.kind != "current" {
                    legacyMatchCount += 1
                    SubsystemDiagnostics.record(
                        level: .info,
                        subsystem: .versionHistory,
                        name: "version.legacyIdentityCandidateMatched",
                        reasonCode: "version.legacyIdentityCandidateMatched",
                        noteBasename: noteURL.lastPathComponent,
                        metadata: [
                            "legacyRelativePath": matchedCandidate.relativePath,
                            "legacyLookupKey": matchedCandidate.lookupKey,
                            "legacyStorageKey": matchedCandidate.storageKey,
                            "legacyKind": matchedCandidate.kind,
                            "snapshotStorage": url.lastPathComponent
                        ]
                    )
                }
                SubsystemDiagnostics.record(
                    level: .info,
                    subsystem: .versionHistory,
                    name: "version.snapshotLookupCandidateMatched",
                    reasonCode: "version.snapshotLookupCandidateMatched",
                    noteBasename: noteURL.lastPathComponent,
                    metadata: [
                        "snapshotStorage": url.lastPathComponent,
                        "versionLookupKey": metadata.versionLookupKey,
                        "snapshotStorageKey": metadata.snapshotStorageKey
                    ]
                )
            } else if !isInTargetDirectory {
                if let directoryMatchedCandidate {
                    if directoryMatchedCandidate.kind != "current" {
                        legacyMatchCount += 1
                        SubsystemDiagnostics.record(
                            level: .info,
                            subsystem: .versionHistory,
                            name: "version.legacyIdentityCandidateMatched",
                            reasonCode: "version.legacyIdentityCandidateMatched",
                            noteBasename: noteURL.lastPathComponent,
                            metadata: [
                                "legacyRelativePath": directoryMatchedCandidate.relativePath,
                                "legacyLookupKey": directoryMatchedCandidate.lookupKey,
                                "legacyStorageKey": directoryMatchedCandidate.storageKey,
                                "legacyKind": directoryMatchedCandidate.kind,
                                "snapshotStorage": url.lastPathComponent,
                                "matchSource": "legacyDirectoryWithoutMetadata"
                            ]
                        )
                    }
                } else {
                    ignoredCount += 1
                    recordLookupCandidateRejected(
                        url,
                        noteURL: noteURL,
                        reason: "metadataMissingOutsideLookupDirectory",
                        metadata: nil,
                        expectedLookupKey: lookupKey
                    )
                    continue
                }
            } else if directoryMatchedCandidate == nil {
                ignoredCount += 1
                recordLookupCandidateRejected(
                    url,
                    noteURL: noteURL,
                    reason: "metadataMissingOutsideLookupDirectory",
                    metadata: nil,
                    expectedLookupKey: lookupKey
                )
                continue
            }
            let mdate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let isEncrypted = url.lastPathComponent.hasSuffix(".\(Self.encryptedExtension)")
            acceptedTuples.append((url, mdate, isEncrypted))
        }
        let accepted = acceptedTuples
            .sorted { $0.1 > $1.1 }
            .enumerated()
            .map { index, tuple in
                NoteVersion(id: index, snapshotURL: tuple.0, date: tuple.1, isEncrypted: tuple.2)
            }
        let lastSnapshotAt = accepted.first?.date
        let status = VersionHistoryLookupStatus(
            currentNoteIdentity: identity,
            versionLookupKey: lookupKey,
            snapshotFilesFound: accepted.count,
            snapshotFilesIgnored: ignoredCount,
            lastSnapshotAt: lastSnapshotAt,
            nextEligibleAt: lastSnapshotAt?.addingTimeInterval(300)
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotLookupLegacyIdentityCount",
            reasonCode: "version.snapshotLookupLegacyIdentityCount",
            noteBasename: noteURL.lastPathComponent,
            counts: ["legacyIdentityCount": legacyCandidates.count, "legacyMatchCount": legacyMatchCount],
            metadata: ["currentNoteIdentity": identity, "versionLookupKey": lookupKey]
        )
        if legacyMatchCount > 0 {
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "version.snapshotLookupIncludedLegacySnapshots",
                reasonCode: "version.snapshotLookupIncludedLegacySnapshots",
                noteBasename: noteURL.lastPathComponent,
                counts: ["legacyMatchCount": legacyMatchCount],
                metadata: ["currentNoteIdentity": identity, "versionLookupKey": lookupKey]
            )
        }
        recordLookupCompleted(
            status: status,
            noteURL: noteURL,
            emptyReason: accepted.isEmpty ? "noSnapshotFilesMatchedLookupKey" : nil
        )
        recordLookup(status: status, noteURL: noteURL)
        return (accepted, status)
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
        return versionsRoot(for: vaultRoot)
            .appending(path: noteID)
    }

    private func versionsRoot(for vaultRoot: URL) -> URL {
        vaultRoot
            .appending(path: ".quartz")
            .appending(path: "versions")
    }

    /// Generates a stable, unique identifier for a note based on its relative path.
    ///
    /// This ensures that:
    /// - Same-name files in different folders have different IDs
    /// - IDs are filesystem-safe (no special characters)
    /// - IDs are stable and collision-resistant (SHA256 hash)
    private func stableNoteID(for noteURL: URL, vaultRoot: URL) -> String {
        let lookupKey = versionLookupKey(for: noteURL, vaultRoot: vaultRoot)
        return stableNoteID(forLookupKey: lookupKey, fallbackName: noteURL.deletingPathExtension().lastPathComponent)
    }

    private func stableNoteID(forLookupKey lookupKey: String, fallbackName: String) -> String {
        guard let data = lookupKey.data(using: .utf8) else {
            return sanitizeFilename(fallbackName)
        }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func versionLookupKey(for noteURL: URL, vaultRoot: URL) -> String {
        let relativePath = canonicalRelativePath(for: noteURL, vaultRoot: vaultRoot)
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1, let first = parts.first else {
            return relativePath
        }
        return "\(first)<path:\(parts.dropFirst().joined(separator: "/"))>"
    }

    private func canonicalRelativePath(for noteURL: URL, vaultRoot: URL) -> String {
        let rootPath = vaultRoot.standardizedFileURL.path(percentEncoded: false)
        let notePath = noteURL.standardizedFileURL.path(percentEncoded: false)

        if notePath.hasPrefix(rootPath) {
            return String(notePath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return noteURL.lastPathComponent
    }

    private func legacyIdentityCandidates(for noteURL: URL, vaultRoot: URL) -> [VersionLookupIdentityCandidate] {
        let relativePath = canonicalRelativePath(for: noteURL, vaultRoot: vaultRoot)
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 2, let first = parts.first, let last = parts.last else {
            return []
        }

        let collapsedRelativePath = [first, last].joined(separator: "/")
        guard collapsedRelativePath != relativePath else { return [] }
        let collapsedLookupKey = versionLookupKey(forRelativePath: collapsedRelativePath)
        return [
            VersionLookupIdentityCandidate(
                relativePath: collapsedRelativePath,
                lookupKey: collapsedLookupKey,
                storageKey: stableNoteID(forLookupKey: collapsedLookupKey, fallbackName: last),
                kind: "firstFolderBasename"
            )
        ]
    }

    private func versionLookupKey(forRelativePath relativePath: String) -> String {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1, let first = parts.first else {
            return relativePath
        }
        return "\(first)<path:\(parts.dropFirst().joined(separator: "/"))>"
    }

    private func metadataURL(for snapshotURL: URL) -> URL {
        snapshotURL.deletingLastPathComponent()
            .appending(path: "\(snapshotURL.lastPathComponent).metadata.json")
    }

    private func writeMetadata(_ metadata: VersionSnapshotMetadata, for snapshotURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL(for: snapshotURL), options: .atomic)
    }

    private func readMetadata(for snapshotURL: URL, noteURL: URL) -> VersionSnapshotMetadata? {
        let url = metadataURL(for: snapshotURL)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .versionHistory,
                name: "version.snapshotMetadataMissing",
                reasonCode: "version.snapshotMetadataMissing",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["snapshotStorage": snapshotURL.lastPathComponent]
            )
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(VersionSnapshotMetadata.self, from: Data(contentsOf: url))
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .versionHistory,
                name: "version.snapshotMetadataRead",
                reasonCode: "version.snapshotMetadataRead",
                noteBasename: noteURL.lastPathComponent,
                metadata: [
                    "snapshotStorage": snapshotURL.lastPathComponent,
                    "noteIdentity": metadata.noteIdentity,
                    "versionLookupKey": metadata.versionLookupKey,
                    "snapshotStorageKey": metadata.snapshotStorageKey,
                    "originalRelativePath": metadata.originalRelativePath
                ]
            )
            return metadata
        } catch {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "version.snapshotMetadataMissing",
                reasonCode: "version.snapshotMetadataMissing",
                noteBasename: noteURL.lastPathComponent,
                metadata: ["snapshotStorage": snapshotURL.lastPathComponent, "error": error.localizedDescription]
            )
            return nil
        }
    }

    private func recordPostWriteVisibility(
        snapshotURL: URL,
        snapshotDir: URL,
        noteURL: URL,
        storageKey: String
    ) {
        let contents = directoryContents(in: snapshotDir)
        let fileVisible = FileManager.default.fileExists(atPath: snapshotURL.path(percentEncoded: false))
        let sidecarVisible = FileManager.default.fileExists(atPath: metadataURL(for: snapshotURL).path(percentEncoded: false))
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotPostWriteDirectoryEnumerated",
            reasonCode: "version.snapshotPostWriteDirectoryEnumerated",
            noteBasename: noteURL.lastPathComponent,
            counts: ["fileCount": contents.count],
            metadata: [
                "snapshotStorageKey": storageKey,
                "snapshotDirectory": snapshotDir.path(percentEncoded: false)
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "version.snapshotPostWriteDirectoryFileCount",
            reasonCode: "version.snapshotPostWriteDirectoryFileCount",
            noteBasename: noteURL.lastPathComponent,
            counts: ["fileCount": contents.count],
            metadata: ["snapshotStorageKey": storageKey]
        )
        SubsystemDiagnostics.record(
            level: fileVisible ? .info : .error,
            subsystem: .versionHistory,
            name: "version.snapshotPostWriteFileVisible",
            reasonCode: "version.snapshotPostWriteFileVisible",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "snapshotStorage": snapshotURL.lastPathComponent,
                "snapshotStorageKey": storageKey,
                "visible": String(fileVisible)
            ]
        )
        SubsystemDiagnostics.record(
            level: sidecarVisible ? .info : .error,
            subsystem: .versionHistory,
            name: "version.snapshotPostWriteSidecarVisible",
            reasonCode: "version.snapshotPostWriteSidecarVisible",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "snapshotStorage": snapshotURL.lastPathComponent,
                "snapshotStorageKey": storageKey,
                "visible": String(sidecarVisible)
            ]
        )
    }

    private func directoryContents(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func directoryContentsWithVisibilityRetry(
        in directory: URL,
        noteURL: URL,
        storageKey: String,
        retryIfEmpty: Bool
    ) -> [URL] {
        let first = directoryContents(in: directory)
        guard first.isEmpty, retryIfEmpty else { return first }
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .versionHistory,
            name: "version.snapshotLookupReadAfterWriteRetry",
            reasonCode: "version.snapshotLookupReadAfterWriteRetry",
            noteBasename: noteURL.lastPathComponent,
            metadata: [
                "snapshotStorageKey": storageKey,
                "snapshotDirectory": directory.path(percentEncoded: false),
                "reason": "emptyDirectDirectoryEnumeration"
            ]
        )
        Thread.sleep(forTimeInterval: 0.05)
        return directoryContents(in: directory)
    }

    private func uniqueSnapshotCandidateURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path(percentEncoded: false)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
    }

    private func allVersionSnapshotCandidates(in vaultRoot: URL) -> [URL] {
        let root = versionsRoot(for: vaultRoot)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.flatMap { directory -> [URL] in
            directoryContents(in: directory)
        }
    }

    private func recordLookupCandidateRejected(
        _ url: URL,
        noteURL: URL,
        reason: String,
        metadata: VersionSnapshotMetadata?,
        expectedLookupKey: String
    ) {
        var values = [
            "snapshotStorage": url.lastPathComponent,
            "reason": reason,
            "expectedLookupKey": expectedLookupKey
        ]
        if let metadata {
            values["candidateLookupKey"] = metadata.versionLookupKey
            values["candidateNoteIdentity"] = metadata.noteIdentity
            values["candidateStorageKey"] = metadata.snapshotStorageKey
        }
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .versionHistory,
            name: "version.snapshotLookupCandidateRejectedReason",
            reasonCode: "version.snapshotLookupCandidateRejectedReason",
            noteBasename: noteURL.lastPathComponent,
            metadata: values
        )
        SubsystemDiagnostics.record(
            level: .warning,
            subsystem: .versionHistory,
            name: reason == "metadataKeyMismatch"
                ? "version.snapshotMetadataKeyMismatch"
                : "version.snapshotLookupCandidateRejected",
            reasonCode: reason == "metadataKeyMismatch"
                ? "version.snapshotMetadataKeyMismatch"
                : "version.snapshotLookupCandidateRejected",
            noteBasename: noteURL.lastPathComponent,
            metadata: values
        )
    }

    private func recordLookup(status: VersionHistoryLookupStatus, noteURL: URL) {
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "snapshotLookup",
            reasonCode: "version.snapshotLookup",
            noteBasename: noteURL.lastPathComponent,
            counts: [
                "snapshotFilesFound": status.snapshotFilesFound,
                "snapshotFilesIgnored": status.snapshotFilesIgnored
            ],
            metadata: [
                "currentNoteIdentity": status.currentNoteIdentity,
                "versionLookupKey": status.versionLookupKey,
                "lastSnapshotAt": status.lastSnapshotAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
                "nextEligibleAt": status.nextEligibleAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
            ]
        )
    }

    private func recordLookupCompleted(status: VersionHistoryLookupStatus, noteURL: URL, emptyReason: String?) {
        var metadata = [
            "currentNoteIdentity": status.currentNoteIdentity,
            "versionLookupKey": status.versionLookupKey,
            "lastSnapshotAt": status.lastSnapshotAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
            "nextEligibleAt": status.nextEligibleAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
        ]
        if let emptyReason {
            metadata["versionEmptyStateReason"] = emptyReason
        }
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionLookupCompleted",
            reasonCode: "version.lookupCompleted",
            noteBasename: noteURL.lastPathComponent,
            counts: [
                "snapshotFilesFound": status.snapshotFilesFound,
                "snapshotFilesIgnored": status.snapshotFilesIgnored
            ],
            metadata: metadata
        )
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

        let snapshotFiles = files.filter { url in
            let ext = url.pathExtension
            let name = url.lastPathComponent
            return ext == Self.plainExtension || name.hasSuffix(".\(Self.encryptedExtension)")
        }

        let sorted = snapshotFiles.sorted { a, b in
            // Resource value read failure is non-fatal — use distantPast as fallback
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate > bDate
        }

        // Remove everything beyond the keep limit
        for file in sorted.dropFirst(keep) {
            do {
                try fm.removeItem(at: file)
                try? fm.removeItem(at: metadataURL(for: file))
            } catch {
                Self.logger.warning("Failed to prune old snapshot \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
