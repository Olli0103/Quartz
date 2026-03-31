import Foundation

/// iCloud Drive sync status for a file.
public enum CloudStatus: String, Sendable, Codable, Hashable {
    /// File is local only, not in iCloud Drive.
    case local
    /// iCloud file, fully downloaded and available locally.
    case downloaded
    /// iCloud file, currently downloading.
    case downloading
    /// iCloud file, evicted from local storage (needs download before access).
    case evicted
}

/// Metadata of a file in the vault.
public struct FileMetadata: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var modifiedAt: Date
    public var fileSize: Int64
    public var isEncrypted: Bool
    public var cloudStatus: CloudStatus
    /// Whether the file has unresolved iCloud sync conflicts.
    public var hasConflict: Bool

    public init(
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        fileSize: Int64 = 0,
        isEncrypted: Bool = false,
        cloudStatus: CloudStatus = .local,
        hasConflict: Bool = false
    ) {
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.isEncrypted = isEncrypted
        self.cloudStatus = cloudStatus
        self.hasConflict = hasConflict
    }
}

/// A node in the vault file tree (folder or file).
public struct FileNode: Identifiable, Hashable, Sendable {
    /// Stable identifier derived from the file URL to ensure SwiftUI can correctly
    /// diff the tree across refreshes (e.g., after drag-and-drop moves).
    public var id: String { url.absoluteString }
    public var name: String
    public var url: URL
    public var nodeType: NodeType
    public var children: [FileNode]?
    public var metadata: FileMetadata
    public var frontmatter: Frontmatter?

    public init(
        name: String,
        url: URL,
        nodeType: NodeType,
        children: [FileNode]? = nil,
        metadata: FileMetadata = FileMetadata(),
        frontmatter: Frontmatter? = nil
    ) {
        self.name = name
        self.url = url
        self.nodeType = nodeType
        self.children = children
        self.metadata = metadata
        self.frontmatter = frontmatter
    }

    /// Returns `true` if the node is a folder.
    public var isFolder: Bool { nodeType == .folder }

    /// Returns `true` if the node is a note.
    public var isNote: Bool { nodeType == .note }
}
