import Foundation

/// Actor-basierter Vault-Service für lokale Dateisystem-Operationen.
///
/// Nutzt `FileManager` für alle I/O-Operationen. Thread-Sicherheit
/// ist durch Actor-Isolation gewährleistet.
public actor FileSystemVaultProvider: VaultProviding {
    private let fileManager = FileManager.default
    private let frontmatterParser: any FrontmatterParsing
    /// Cached vault root URL, set when loadFileTree is called.
    private var vaultRoot: URL?

    public init(frontmatterParser: any FrontmatterParsing) {
        self.frontmatterParser = frontmatterParser
    }

    // MARK: - VaultProviding

    public func loadFileTree(at root: URL) async throws -> [FileNode] {
        vaultRoot = root
        // Move heavy recursive I/O off the actor to avoid blocking other actor calls
        let fm = fileManager
        return try await Task.detached(priority: .userInitiated) {
            try FileSystemVaultProvider.buildTreeStatic(at: root, relativeTo: root, fileManager: fm)
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
        let fileName = name.hasSuffix(".md") ? name : "\(name).md"
        let fileURL = folder.appending(path: fileName)

        guard !fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw FileSystemError.fileAlreadyExists(fileURL)
        }

        let frontmatter = Frontmatter(
            title: name.replacingOccurrences(of: ".md", with: ""),
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

    public func deleteNote(at url: URL) async throws {
        #if os(macOS)
        try fileManager.trashItem(at: url, resultingItemURL: nil)
        #else
        // Use cached vault root; fall back to parent directory if not yet set
        let root = vaultRoot ?? url.deletingLastPathComponent()
        let trashFolder = root.appending(path: ".trash")
        try fileManager.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        let dest = trashFolder.appending(path: url.lastPathComponent)
        if fileManager.fileExists(atPath: dest.path(percentEncoded: false)) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: url, to: dest)
        #endif
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
        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    }

    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        // Allow alphanumerics, whitespace, hyphens, underscores, AND Unicode letters (umlauts, accents, CJK, etc.)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let sanitized = name
            .components(separatedBy: allowedCharacters.inverted)
            .joined()
        guard !sanitized.isEmpty, !sanitized.hasPrefix(".") else {
            throw FileSystemError.invalidName(name)
        }
        let folderURL = parent.appending(path: sanitized)
        guard folderURL.standardizedFileURL.path().hasPrefix(parent.standardizedFileURL.path()) else {
            throw FileSystemError.invalidName(name)
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    // MARK: - File Coordination

    private func coordinatedRead(at url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinatorError: NSError?
                var readData: Data?
                var readError: Error?

                let coordinator = NSFileCoordinator()
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { actualURL in
                    do {
                        readData = try Data(contentsOf: actualURL)
                    } catch {
                        readError = error
                    }
                }

                if let error = coordinatorError ?? readError {
                    continuation.resume(throwing: error)
                } else if let data = readData {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: FileSystemError.fileNotFound(url))
                }
            }
        }
    }

    private func coordinatedWrite(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinatorError: NSError?
                var writeError: Error?

                let coordinator = NSFileCoordinator()
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { actualURL in
                    do {
                        try data.write(to: actualURL, options: .atomic)
                    } catch {
                        writeError = error
                    }
                }

                if let error = coordinatorError ?? writeError {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
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
        // Prevent stack overflow from circular or extremely deep directory structures
        guard depth < 50 else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        return try contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { itemURL -> FileNode? in
                let resourceValues = try itemURL.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey
                ])

                // Skip symlinks to prevent infinite loops
                if resourceValues.isSymbolicLink == true { return nil }

                let isDirectory = resourceValues.isDirectory ?? false
                let metadata = FileMetadata(
                    createdAt: resourceValues.creationDate ?? .now,
                    modifiedAt: resourceValues.contentModificationDate ?? .now,
                    fileSize: Int64(resourceValues.fileSize ?? 0)
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
                    return FileNode(
                        name: itemURL.lastPathComponent,
                        url: itemURL,
                        nodeType: .asset,
                        metadata: metadata
                    )
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
        }
    }
}
