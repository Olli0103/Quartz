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
}
