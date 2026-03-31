import Foundation

/// Native vault-local trash management.
///
/// Quartz keeps deleted items in a hidden folder inside the vault so deletion behavior is consistent
/// across platforms and remains fully under the user's control. Items older than 30 days are purged.
public struct VaultTrashService: Sendable {
    public static let folderName = ".quartzTrash"
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    public init() {}

    public func trashFolderURL(for vaultRoot: URL) -> URL {
        vaultRoot.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    public func ensureTrashFolderExists(at vaultRoot: URL) throws -> URL {
        let trashURL = trashFolderURL(for: vaultRoot)
        if !FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) {
            try CoordinatedFileWriter.shared.createDirectory(at: trashURL, withIntermediateDirectories: true)
        }
        return trashURL
    }

    public func moveItemToTrash(_ url: URL, in vaultRoot: URL) throws {
        let trashURL = try ensureTrashFolderExists(at: vaultRoot)
        let destinationURL = uniqueTrashDestination(for: url, trashFolder: trashURL)
        try CoordinatedFileWriter.shared.moveItem(from: url, to: destinationURL)
    }

    /// Restores a trashed item back to the vault root (since original path is unknown).
    public func restoreItem(_ url: URL, to vaultRoot: URL) throws -> URL {
        let baseName = stripTrashTimestamp(from: url.deletingPathExtension().lastPathComponent)
        let ext = url.pathExtension
        let fileName = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        var destinationURL = vaultRoot.appending(path: fileName)

        // Avoid overwriting existing files
        var counter = 2
        while FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            let numberedName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            destinationURL = vaultRoot.appending(path: numberedName)
            counter += 1
        }

        try CoordinatedFileWriter.shared.moveItem(from: url, to: destinationURL)
        return destinationURL
    }

    /// Permanently deletes a single trashed item.
    public func permanentlyDelete(_ url: URL) throws {
        try CoordinatedFileWriter.shared.removeItem(at: url)
    }

    /// Permanently deletes all items in the trash folder.
    public func emptyTrash(in vaultRoot: URL) throws {
        let trashURL = trashFolderURL(for: vaultRoot)
        guard FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) else { return }

        let contents = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents {
            try CoordinatedFileWriter.shared.removeItem(at: item)
        }
    }

    /// Returns all items in the trash folder as FileNode array.
    public func trashedItems(in vaultRoot: URL) -> [FileNode] {
        let trashURL = trashFolderURL(for: vaultRoot)
        guard FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) else { return [] }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url -> FileNode? in
            guard url.pathExtension == "md" else { return nil }
            let name = stripTrashTimestamp(from: url.deletingPathExtension().lastPathComponent)
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return FileNode(
                name: name,
                url: url,
                nodeType: .note,
                metadata: FileMetadata(modifiedAt: mtime)
            )
        }.sorted { $0.metadata.modifiedAt > $1.metadata.modifiedAt }
    }

    /// Checks if a URL is inside the vault's trash folder.
    public func isInTrash(_ url: URL, vaultRoot: URL) -> Bool {
        let trashPath = trashFolderURL(for: vaultRoot).path(percentEncoded: false)
        return url.path(percentEncoded: false).hasPrefix(trashPath)
    }

    public func purgeExpiredItems(in vaultRoot: URL, now: Date = .now) throws {
        let trashURL = trashFolderURL(for: vaultRoot)
        guard FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)) else { return }

        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        let contents = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let modifiedAt = try itemURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
            guard modifiedAt < cutoff else { continue }
            try CoordinatedFileWriter.shared.removeItem(at: itemURL)
        }
    }

    private func uniqueTrashDestination(for sourceURL: URL, trashFolder: URL) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let preferredName = ext.isEmpty
            ? "\(baseName)-\(timestamp)"
            : "\(baseName)-\(timestamp).\(ext)"

        var destinationURL = trashFolder.appending(path: preferredName)
        var counter = 1
        while FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            let uniqueName = ext.isEmpty
                ? "\(baseName)-\(timestamp)-\(counter)"
                : "\(baseName)-\(timestamp)-\(counter).\(ext)"
            destinationURL = trashFolder.appending(path: uniqueName)
            counter += 1
        }
        return destinationURL
    }

    /// Strips the ISO8601 timestamp suffix that `uniqueTrashDestination` appends.
    /// e.g. "Meeting Notes-20260330T141500.000Z" → "Meeting Notes"
    private func stripTrashTimestamp(from name: String) -> String {
        // Pattern: name ends with -YYYYMMDDTHHMMSS.sssZ or -YYYYMMDDTHHMMSS.sssZ-N
        guard let dashRange = name.range(of: #"-\d{4}\d{2}\d{2}T"#, options: .regularExpression) else {
            return name
        }
        return String(name[name.startIndex..<dashRange.lowerBound])
    }
}
