import Foundation

/// Actor-based vault service for local file system operations.
///
/// Uses `FileManager` for all I/O operations. Thread safety
/// is guaranteed through actor isolation.
public actor FileSystemVaultProvider: VaultProviding {
    private let fileManager = FileManager.default
    private let frontmatterParser: any FrontmatterParsing
    private let trashService = VaultTrashService()
    /// Cached vault root URL, set when loadFileTree is called.
    private var vaultRoot: URL?

    public init(frontmatterParser: any FrontmatterParsing) {
        self.frontmatterParser = frontmatterParser
    }

    // MARK: - VaultProviding

    public func loadFileTree(at root: URL) async throws -> [FileNode] {
        vaultRoot = root
        await purgeTrashOlderThan30Days(at: root)
        // Move heavy recursive I/O off the actor to avoid blocking other actor calls.
        // FileManager.default is used inside the closure instead of capturing the
        // actor's instance (FileManager is not Sendable in Swift 6).
        return try await Task.detached(priority: .userInitiated) {
            try FileSystemVaultProvider.buildTreeStatic(at: root, relativeTo: root)
        }.value
    }

    public func readNote(at url: URL) async throws -> NoteDocument {
        let data = try await coordinatedRead(at: url)
        guard let rawContent = String(data: data, encoding: .utf8) else {
            throw FileSystemError.encodingFailed(url)
        }

        let (frontmatter, body) = try frontmatterParser.parse(from: rawContent)
        let attributes = try fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))

        return NoteDocument(
            fileURL: url,
            frontmatter: frontmatter,
            body: body,
            isDirty: false,
            lastSyncedAt: attributes[.modificationDate] as? Date
        )
    }

    public func saveNote(_ note: NoteDocument) async throws {
        let yamlString = try frontmatterParser.serialize(note.frontmatter)
        let rawContent: String
        if yamlString.isEmpty {
            rawContent = note.body
        } else {
            rawContent = "---\n\(yamlString)---\n\n\(note.body)"
        }

        guard let data = rawContent.data(using: .utf8) else {
            throw FileSystemError.encodingFailed(note.fileURL)
        }
        try await coordinatedWrite(data: data, to: note.fileURL)
    }

    public func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            throw FileSystemError.invalidName(name)
        }

        let baseName = sanitized.hasSuffix(".md") ? String(sanitized.dropLast(3)) : sanitized
        guard !baseName.isEmpty, !baseName.hasPrefix("."), !baseName.contains("/"), !baseName.contains("\\") else {
            throw FileSystemError.invalidName(name)
        }

        let fileName = "\(baseName).md"
        let fileURL = folder.appending(path: fileName)

        guard !fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw FileSystemError.fileAlreadyExists(fileURL)
        }

        let frontmatter = Frontmatter(
            title: baseName,
            createdAt: .now,
            modifiedAt: .now
        )

        let note = NoteDocument(
            fileURL: fileURL,
            frontmatter: frontmatter,
            body: "",
            isDirty: false
        )

        try await saveNote(note)
        return note
    }

    /// Creates a new note with initial body content (e.g. from voice transcription).
    public func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        let base = try await createNote(named: name, in: folder)
        let note = NoteDocument(
            fileURL: base.fileURL,
            frontmatter: base.frontmatter,
            body: initialContent,
            isDirty: false
        )
        try await saveNote(note)
        return note
    }

    public func deleteNote(at url: URL) async throws {
        let root = resolveVaultRoot(for: url)
        let trash = self.trashService
        try await Task.detached(priority: .userInitiated) {
            try trash.moveItemToTrash(url, in: root)
        }.value
    }

    public func rename(at url: URL, to newName: String) async throws -> URL {
        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, !sanitized.hasPrefix("."), !sanitized.contains("/"), !sanitized.contains("\\") else {
            throw FileSystemError.invalidName(newName)
        }
        let parent = url.deletingLastPathComponent()
        let newURL = parent.appending(path: sanitized)
        guard newURL.standardizedFileURL.path().hasPrefix(parent.standardizedFileURL.path()) else {
            throw FileSystemError.invalidName(newName)
        }
        guard !fileManager.fileExists(atPath: newURL.path(percentEncoded: false)) else {
            throw FileSystemError.fileAlreadyExists(newURL)
        }
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.moveItem(from: url, to: newURL)
        }.value
        return newURL
    }

    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        // Allow alphanumerics, whitespace, hyphens, underscores, AND Unicode letters (umlauts, accents, CJK, etc.)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let sanitized = name
            .precomposedStringWithCanonicalMapping // Normalize Unicode to prevent NFC/NFD bypass
            .components(separatedBy: allowedCharacters.inverted)
            .joined()
        guard !sanitized.isEmpty,
              !sanitized.hasPrefix("."),
              sanitized != "..",
              !sanitized.contains("..") else {
            throw FileSystemError.invalidName(name)
        }
        let folderURL = parent.appending(path: sanitized)
        // Resolve symlinks to prevent bypass via symbolic link chains
        guard folderURL.resolvingSymlinksInPath().standardizedFileURL.path()
                .hasPrefix(parent.resolvingSymlinksInPath().standardizedFileURL.path()) else {
            throw FileSystemError.invalidName(name)
        }
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.createDirectory(at: folderURL, withIntermediateDirectories: false)
        }.value
        return folderURL
    }

    // MARK: - File Coordination

    private func coordinatedRead(at url: URL) async throws -> Data {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw FileSystemError.fileNotFound(url)
        }

        // Check iCloud status and trigger download if evicted
        let resourceValues = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ])

        let isEvicted = resourceValues?.ubiquitousItemDownloadingStatus == .notDownloaded
        let isDownloading = resourceValues?.ubiquitousItemIsDownloading ?? false

        if isEvicted || isDownloading {
            // Trigger download if not already downloading
            if isEvicted {
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }

            // Wait for download to complete (30 second timeout)
            let downloadedSuccessfully = try await waitForDownload(at: url, timeout: 30)
            if !downloadedSuccessfully {
                throw FileSystemError.iCloudTimeout(url)
            }
        }

        // File should be local now — read with shorter timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                // First attempt: direct read
                do {
                    return try Data(contentsOf: url)
                } catch {
                    // Second attempt: coordinated read
                    return try CoordinatedFileWriter.shared.read(from: url)
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw FileSystemError.iCloudTimeout(url)
            }

            // Return whichever finishes first; cancel the other.
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Polls download status until file is available or timeout expires.
    /// Returns `true` if file became available, `false` if timeout expired.
    private func waitForDownload(at url: URL, timeout: TimeInterval) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            let resourceValues = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ])

            let status = resourceValues?.ubiquitousItemDownloadingStatus
            let isDownloading = resourceValues?.ubiquitousItemIsDownloading ?? false

            // File is ready when status is current/downloaded and not actively downloading
            if (status == .current || status == .downloaded) && !isDownloading {
                return true
            }

            // Poll every 500ms
            try await Task.sleep(for: .milliseconds(500))
        }

        return false
    }

    private func coordinatedWrite(data: Data, to url: URL) async throws {
        // Create parent directory if needed (e.g. for new notes in new folders)
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path(percentEncoded: false)) {
            try await Task.detached(priority: .userInitiated) {
                try CoordinatedFileWriter.shared.createDirectory(at: parent, withIntermediateDirectories: true)
            }.value
        }
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.write(data, to: url)
        }.value
    }

    // MARK: - Trash Purge

    /// Permanently deletes items in the hidden vault trash that are older than 30 days.
    private func purgeTrashOlderThan30Days(at root: URL) async {
        let trash = self.trashService
        do {
            try await Task.detached(priority: .utility) {
                try trash.purgeExpiredItems(in: root)
            }.value
        } catch {
            // Best-effort housekeeping; never block vault loading because trash cleanup failed.
        }
    }

    private func resolveVaultRoot(for url: URL) -> URL {
        vaultRoot ?? url.deletingLastPathComponent()
    }

    // MARK: - Private

    /// Static, nonisolated tree builder that can run on any thread.
    /// Includes a depth limit to prevent stack overflow from pathological directory structures.
    private static func buildTreeStatic(
        at url: URL,
        relativeTo root: URL,
        depth: Int = 0,
        fileManager: FileManager = .default
    ) throws -> [FileNode] {
        guard depth < 50 else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemHasUnresolvedConflictsKey
            ],
            options: [.skipsHiddenFiles]
        )

        return try contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { itemURL -> FileNode? in
                let resourceValues = try itemURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isSymbolicLinkKey,
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey,
                    .ubiquitousItemHasUnresolvedConflictsKey
                ])

                if resourceValues.isSymbolicLink == true { return nil }

                let isDirectory = resourceValues.isDirectory ?? false

                // Detect iCloud eviction status
                let cloudStatus: CloudStatus
                let isDownloading = resourceValues.ubiquitousItemIsDownloading ?? false
                if isDownloading {
                    cloudStatus = .downloading
                } else if let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus {
                    switch downloadStatus {
                    case .notDownloaded:
                        cloudStatus = .evicted
                    case .current, .downloaded:
                        cloudStatus = .downloaded
                    default:
                        cloudStatus = .local
                    }
                } else {
                    cloudStatus = .local  // Not an iCloud file
                }

                // Detect iCloud conflicts
                let hasConflict = resourceValues.ubiquitousItemHasUnresolvedConflicts ?? false

                let metadata = FileMetadata(
                    createdAt: resourceValues.creationDate ?? .now,
                    modifiedAt: resourceValues.contentModificationDate ?? .now,
                    fileSize: Int64(resourceValues.fileSize ?? 0),
                    cloudStatus: cloudStatus,
                    hasConflict: hasConflict
                )

                if isDirectory {
                    let children = try buildTreeStatic(at: itemURL, relativeTo: root, depth: depth + 1, fileManager: fileManager)
                    return FileNode(
                        name: itemURL.lastPathComponent,
                        url: itemURL,
                        nodeType: .folder,
                        children: children,
                        metadata: metadata
                    )
                } else if itemURL.pathExtension == "md" {
                    return FileNode(
                        name: itemURL.lastPathComponent,
                        url: itemURL,
                        nodeType: .note,
                        metadata: metadata
                    )
                } else {
                    // Skip non-markdown files entirely
                    return nil
                }
            }
    }
}

// MARK: - Errors

public enum FileSystemError: LocalizedError, Sendable {
    case encodingFailed(URL)
    case fileAlreadyExists(URL)
    case fileNotFound(URL)
    case invalidName(String)
    case iCloudTimeout(URL)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let url):
            String(localized: "Unable to read file: \(url.lastPathComponent)", bundle: .module)
        case .fileAlreadyExists(let url):
            String(localized: "File already exists: \(url.lastPathComponent)", bundle: .module)
        case .fileNotFound(let url):
            String(localized: "File not found: \(url.lastPathComponent)", bundle: .module)
        case .invalidName(let name):
            String(localized: "Invalid name: \(name)", bundle: .module)
        case .iCloudTimeout(let url):
            String(localized: "\(url.lastPathComponent) could not be downloaded from iCloud. Check your network connection and try again.", bundle: .module)
        }
    }
}
