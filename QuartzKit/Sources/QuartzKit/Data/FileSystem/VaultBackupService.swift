import Foundation
import os

// MARK: - Backup Models

/// Metadata written into each backup for identification and integrity.
public struct BackupManifest: Codable, Sendable {
    public let backupVersion: Int
    public let createdAt: Date
    public let vaultName: String
    public let fileCount: Int
    public let totalSizeBytes: Int64
    public let quartzAppVersion: String
    public let deviceName: String

    public init(
        backupVersion: Int = 1,
        createdAt: Date = Date(),
        vaultName: String,
        fileCount: Int,
        totalSizeBytes: Int64,
        quartzAppVersion: String,
        deviceName: String
    ) {
        self.backupVersion = backupVersion
        self.createdAt = createdAt
        self.vaultName = vaultName
        self.fileCount = fileCount
        self.totalSizeBytes = totalSizeBytes
        self.quartzAppVersion = quartzAppVersion
        self.deviceName = deviceName
    }
}

/// A discovered backup in the .quartz/backups/ directory.
public struct BackupEntry: Identifiable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let createdAt: Date
    public let sizeBytes: Int64
    public let manifest: BackupManifest?

    public init(url: URL, name: String, createdAt: Date, sizeBytes: Int64, manifest: BackupManifest? = nil) {
        self.id = url
        self.url = url
        self.name = name
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.manifest = manifest
    }
}

/// Size estimate before starting a backup.
public struct BackupSizeEstimate: Sendable {
    public let totalFiles: Int
    public let totalSizeBytes: Int64
    public let excludedFiles: Int
    public let excludedSizeBytes: Int64
}

/// Progress update during backup/restore operations.
public struct BackupProgress: Sendable {
    public let currentFile: Int
    public let totalFiles: Int
    public let currentFileName: String

    public var fraction: Double {
        totalFiles > 0 ? Double(currentFile) / Double(totalFiles) : 0
    }
}

/// Errors from backup operations.
public enum BackupError: LocalizedError, Sendable {
    case noVaultRoot
    case backupFailed(String)
    case restoreFailed(String)
    case manifestCorrupted
    case destinationExists

    public var errorDescription: String? {
        switch self {
        case .noVaultRoot:
            String(localized: "No vault is open.", bundle: .module)
        case .backupFailed(let msg):
            String(localized: "Backup failed: \(msg)", bundle: .module)
        case .restoreFailed(let msg):
            String(localized: "Restore failed: \(msg)", bundle: .module)
        case .manifestCorrupted:
            String(localized: "Backup manifest is corrupted or missing.", bundle: .module)
        case .destinationExists:
            String(localized: "A backup with this name already exists.", bundle: .module)
        }
    }
}

// MARK: - Vault Backup Service

/// Manages vault backups: manual export, auto-backup with retention, and restore.
///
/// Backups are stored as timestamped directories in `.quartz/backups/`.
/// Each backup contains a full copy of the vault's Markdown files, the `.quartz/`
/// metadata directory, and a `manifest.json` for identification.
///
/// Uses folder copy (not zip) to avoid external dependencies. This is fast,
/// preserves file metadata, and works reliably across all Apple platforms.
public actor VaultBackupService {
    private let logger = Logger(subsystem: "com.quartz", category: "Backup")

    /// Hidden directory inside the vault for backups.
    public static let backupsFolder = ".quartz/backups"
    private static let manifestFileName = "manifest.json"

    /// Patterns to exclude from backups.
    private static let excludedNames: Set<String> = [
        ".DS_Store", ".git", ".gitignore", ".quartzTrash",
        "backups" // within .quartz — prevents recursive backup-of-backups
    ]

    private static let excludedExtensions: Set<String> = [
        "tmp", "swp"
    ]

    /// Maximum individual file size to include (100MB).
    private static let maxFileSize: Int64 = 100_000_000

    public init() {}

    // MARK: - Estimate

    /// Estimates the size of a vault backup before starting.
    public func estimateBackupSize(vaultRoot: URL) throws -> BackupSizeEstimate {
        let fm = FileManager.default
        var totalFiles = 0
        var totalSize: Int64 = 0
        var excludedFiles = 0
        var excludedSize: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: []
        ) else {
            return BackupSizeEstimate(totalFiles: 0, totalSizeBytes: 0, excludedFiles: 0, excludedSizeBytes: 0)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else {
                if Self.excludedNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let size = Int64(values?.fileSize ?? 0)
            if Self.shouldExclude(fileURL, relativeTo: vaultRoot, fileSize: size) {
                excludedFiles += 1
                excludedSize += size
            } else {
                totalFiles += 1
                totalSize += size
            }
        }

        return BackupSizeEstimate(
            totalFiles: totalFiles,
            totalSizeBytes: totalSize,
            excludedFiles: excludedFiles,
            excludedSizeBytes: excludedSize
        )
    }

    // MARK: - Create Backup

    /// Creates a backup of the vault as a timestamped directory.
    ///
    /// Returns the URL of the created backup directory.
    public func createBackup(
        vaultRoot: URL,
        destination: URL? = nil,
        progress: (@Sendable (BackupProgress) -> Void)? = nil
    ) async throws -> URL {
        let fm = FileManager.default
        let vaultName = vaultRoot.lastPathComponent

        // Determine destination
        let backupsDir = destination ?? vaultRoot
            .appending(path: Self.backupsFolder, directoryHint: .isDirectory)

        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        let timestamp = dateFormatter.string(from: Date())
        let backupName = "quartz-backup-\(timestamp)"
        let backupDir = backupsDir.appending(path: backupName, directoryHint: .isDirectory)

        guard !fm.fileExists(atPath: backupDir.path(percentEncoded: false)) else {
            throw BackupError.destinationExists
        }

        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Collect files to copy
        let filesToCopy = try collectBackupFiles(vaultRoot: vaultRoot)
        let totalFiles = filesToCopy.count

        logger.info("Creating backup: \(totalFiles) files from '\(vaultName)'")

        // Copy files preserving directory structure
        var copiedCount = 0
        var totalBytes: Int64 = 0

        for (sourceURL, relativePath) in filesToCopy {
            guard !Task.isCancelled else {
                // Clean up partial backup
                try? fm.removeItem(at: backupDir)
                throw CancellationError()
            }

            let destURL = backupDir.appending(path: relativePath)
            let destParent = destURL.deletingLastPathComponent()

            if !fm.fileExists(atPath: destParent.path(percentEncoded: false)) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            try fm.copyItem(at: sourceURL, to: destURL)

            let size = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            totalBytes += Int64(size)
            copiedCount += 1

            progress?(BackupProgress(
                currentFile: copiedCount,
                totalFiles: totalFiles,
                currentFileName: sourceURL.lastPathComponent
            ))
        }

        // Write manifest
        let manifest = BackupManifest(
            vaultName: vaultName,
            fileCount: copiedCount,
            totalSizeBytes: totalBytes,
            quartzAppVersion: Self.appVersion,
            deviceName: Self.deviceName
        )

        let manifestData = try JSONEncoder.quartzPretty.encode(manifest)
        let manifestURL = backupDir.appending(path: Self.manifestFileName)
        try manifestData.write(to: manifestURL)

        logger.info("Backup complete: \(copiedCount) files, \(totalBytes) bytes → \(backupDir.lastPathComponent)")

        return backupDir
    }

    // MARK: - Auto-Backup

    /// Runs an automatic backup if needed, pruning old backups to retain only `retainCount`.
    public func runAutoBackup(vaultRoot: URL, retainCount: Int = 7) async throws {
        let backupsDir = vaultRoot.appending(path: Self.backupsFolder, directoryHint: .isDirectory)

        // Check if a recent backup already exists (within 24h)
        let existing = listBackupsSync(backupsDir: backupsDir)
        if let latest = existing.first, latest.createdAt.timeIntervalSinceNow > -86400 {
            logger.debug("Auto-backup skipped: last backup is \(Int(-latest.createdAt.timeIntervalSinceNow / 3600))h old")
            return
        }

        logger.info("Running auto-backup for \(vaultRoot.lastPathComponent)")

        _ = try await createBackup(vaultRoot: vaultRoot)

        // Prune old backups
        let allBackups = listBackupsSync(backupsDir: backupsDir)
        if allBackups.count > retainCount {
            let toDelete = allBackups.suffix(from: retainCount)
            for entry in toDelete {
                try? FileManager.default.removeItem(at: entry.url)
                logger.debug("Pruned old backup: \(entry.name)")
            }
        }
    }

    // MARK: - List Backups

    /// Lists available backups for a vault, sorted newest first.
    public func listBackups(vaultRoot: URL) -> [BackupEntry] {
        let backupsDir = vaultRoot.appending(path: Self.backupsFolder, directoryHint: .isDirectory)
        return listBackupsSync(backupsDir: backupsDir)
    }

    private func listBackupsSync(backupsDir: URL) -> [BackupEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupsDir.path(percentEncoded: false)) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.creationDateKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [BackupEntry] = []

        for url in contents {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            guard url.lastPathComponent.hasPrefix("quartz-backup-") else { continue }

            let createdAt = values?.creationDate ?? Date.distantPast
            let size = Self.directorySize(at: url)

            // Try to read manifest
            let manifestURL = url.appending(path: Self.manifestFileName)
            let manifest: BackupManifest? = {
                guard let data = try? Data(contentsOf: manifestURL) else { return nil }
                return try? JSONDecoder().decode(BackupManifest.self, from: data)
            }()

            entries.append(BackupEntry(
                url: url,
                name: url.lastPathComponent,
                createdAt: manifest?.createdAt ?? createdAt,
                sizeBytes: size,
                manifest: manifest
            ))
        }

        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Restore

    /// Restores a backup directory to a user-chosen destination.
    ///
    /// Does NOT overwrite the current vault. Extracts to `{destination}/{vaultName}/`.
    public func restoreBackup(
        from backupURL: URL,
        to destinationFolder: URL,
        progress: (@Sendable (BackupProgress) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default

        // Read manifest to get vault name
        let manifestURL = backupURL.appending(path: Self.manifestFileName)
        let vaultName: String
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) {
            vaultName = manifest.vaultName
        } else {
            vaultName = backupURL.lastPathComponent
                .replacingOccurrences(of: "quartz-backup-", with: "")
        }

        let restoreDir = destinationFolder.appending(path: "\(vaultName)-restored", directoryHint: .isDirectory)

        guard !fm.fileExists(atPath: restoreDir.path(percentEncoded: false)) else {
            throw BackupError.destinationExists
        }

        // Collect files from backup (excluding manifest itself)
        guard let enumerator = fm.enumerator(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            throw BackupError.restoreFailed("Cannot read backup directory")
        }

        var filesToRestore: [(source: URL, relativePath: String)] = []
        let backupPath = backupURL.path(percentEncoded: false)

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            // Skip manifest
            guard fileURL.lastPathComponent != Self.manifestFileName else { continue }

            let fullPath = fileURL.path(percentEncoded: false)
            let relative = String(fullPath.dropFirst(backupPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            filesToRestore.append((source: fileURL, relativePath: relative))
        }

        let total = filesToRestore.count
        logger.info("Restoring backup: \(total) files → \(restoreDir.lastPathComponent)")

        try fm.createDirectory(at: restoreDir, withIntermediateDirectories: true)

        for (i, (source, relativePath)) in filesToRestore.enumerated() {
            guard !Task.isCancelled else {
                try? fm.removeItem(at: restoreDir)
                throw CancellationError()
            }

            let destURL = restoreDir.appending(path: relativePath)
            let destParent = destURL.deletingLastPathComponent()

            if !fm.fileExists(atPath: destParent.path(percentEncoded: false)) {
                try fm.createDirectory(at: destParent, withIntermediateDirectories: true)
            }

            try fm.copyItem(at: source, to: destURL)

            progress?(BackupProgress(
                currentFile: i + 1,
                totalFiles: total,
                currentFileName: source.lastPathComponent
            ))
        }

        logger.info("Restore complete: \(total) files to \(restoreDir.lastPathComponent)")
    }

    // MARK: - Private Helpers

    /// Collects all files to include in a backup, with their relative paths.
    private func collectBackupFiles(vaultRoot: URL) throws -> [(url: URL, relativePath: String)] {
        let fm = FileManager.default
        let rootPath = vaultRoot.path(percentEncoded: false)
        var files: [(url: URL, relativePath: String)] = []

        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey],
            options: []
        ) else { return [] }

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else {
                // Skip excluded directories entirely
                let name = fileURL.lastPathComponent
                if Self.excludedNames.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let size = Int64(values?.fileSize ?? 0)
            guard !Self.shouldExclude(fileURL, relativeTo: vaultRoot, fileSize: size) else { continue }

            let fullPath = fileURL.path(percentEncoded: false)
            let relative = String(fullPath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append((url: fileURL, relativePath: relative))
        }

        return files
    }

    /// Determines if a file should be excluded from backup.
    private static func shouldExclude(_ url: URL, relativeTo vaultRoot: URL, fileSize: Int64) -> Bool {
        let name = url.lastPathComponent

        // Excluded names
        if excludedNames.contains(name) { return true }

        // Excluded extensions
        let ext = url.pathExtension.lowercased()
        if excludedExtensions.contains(ext) { return true }

        // Files ending with ~
        if name.hasSuffix("~") { return true }

        // Too large
        if fileSize > maxFileSize { return true }

        // Inside .quartz/backups (prevent recursive backup)
        let relativePath = url.path(percentEncoded: false)
            .replacingOccurrences(of: vaultRoot.path(percentEncoded: false), with: "")
        if relativePath.contains(".quartz/backups") { return true }

        // Inside .quartzTrash
        if relativePath.contains(".quartzTrash") { return true }

        return false
    }

    /// Calculates the total size of a directory recursively.
    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #elseif os(iOS)
        UIDevice.current.name
        #else
        "Apple Device"
        #endif
    }
}

// MARK: - JSON Encoder Extension

private extension JSONEncoder {
    static let quartzPretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
