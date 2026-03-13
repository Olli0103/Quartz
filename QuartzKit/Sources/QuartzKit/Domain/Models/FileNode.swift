import Foundation

/// Metadaten einer Datei im Vault.
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

/// Ein Knoten im Vault-Dateibaum (Ordner oder Datei).
public struct FileNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var nodeType: NodeType
    public var children: [FileNode]?
    public var metadata: FileMetadata
    public var frontmatter: Frontmatter?

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        nodeType: NodeType,
        children: [FileNode]? = nil,
        metadata: FileMetadata = FileMetadata(),
        frontmatter: Frontmatter? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.nodeType = nodeType
        self.children = children
        self.metadata = metadata
        self.frontmatter = frontmatter
    }

    /// Gibt `true` zurück wenn der Knoten ein Ordner ist.
    public var isFolder: Bool { nodeType == .folder }

    /// Gibt `true` zurück wenn der Knoten eine Notiz ist.
    public var isNote: Bool { nodeType == .note }
}
