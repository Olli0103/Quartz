import Foundation

/// Actor-basierter Vault-Service für lokale Dateisystem-Operationen.
///
/// Nutzt `FileManager` für alle I/O-Operationen. Thread-Sicherheit
/// ist durch Actor-Isolation gewährleistet.
public actor FileSystemVaultProvider: VaultProviding {
    private let fileManager = FileManager.default
    private let frontmatterParser: any FrontmatterParsing

    public init(frontmatterParser: any FrontmatterParsing) {
        self.frontmatterParser = frontmatterParser
    }

    // MARK: - VaultProviding

    public func loadFileTree(at root: URL) async throws -> [FileNode] {
        try buildTree(at: root, relativeTo: root)
    }

    public func readNote(at url: URL) async throws -> NoteDocument {
        let data = try Data(contentsOf: url)
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
        try data.write(to: note.fileURL, options: .atomic)
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
        try fileManager.removeItem(at: url)
        #endif
    }

    public func rename(at url: URL, to newName: String) async throws -> URL {
        let newURL = url.deletingLastPathComponent().appending(path: newName)
        try fileManager.moveItem(at: url, to: newURL)
        return newURL
    }

    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        let folderURL = parent.appending(path: name)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return folderURL
    }

    // MARK: - Private

    private func buildTree(at url: URL, relativeTo root: URL) throws -> [FileNode] {
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { itemURL -> FileNode? in
                let resourceValues = try itemURL.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey
                ])

                let isDirectory = resourceValues.isDirectory ?? false
                let metadata = FileMetadata(
                    createdAt: resourceValues.creationDate ?? .now,
                    modifiedAt: resourceValues.contentModificationDate ?? .now,
                    fileSize: Int64(resourceValues.fileSize ?? 0)
                )

                if isDirectory {
                    let children = try buildTree(at: itemURL, relativeTo: root)
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

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let url):
            "Failed to encode/decode file: \(url.lastPathComponent)"
        case .fileAlreadyExists(let url):
            "File already exists: \(url.lastPathComponent)"
        case .fileNotFound(let url):
            "File not found: \(url.lastPathComponent)"
        }
    }
}
