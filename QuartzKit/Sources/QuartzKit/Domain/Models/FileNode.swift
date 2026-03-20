import Foundation

/// Metadata of a file in the vault.
public struct FileMetadata: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var modifiedAt: Date
    public var fileSize: Int64
    public var isEncrypted: Bool

    public init(
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        fileSize: Int64 = 0,
        isEncrypted: Bool = false
    ) {
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.isEncrypted = isEncrypted
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
