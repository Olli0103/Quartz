import Foundation

/// YAML-Metadaten einer Notiz, gespeichert im Frontmatter-Block.
public struct Frontmatter: Codable, Equatable, Sendable {
    public var title: String?
    public var tags: [String]
    public var aliases: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var template: String?
    public var ocrText: String?
    public var linkedNotes: [String]
    public var customFields: [String: String]
    public var isEncrypted: Bool

    public init(
        title: String? = nil,
        tags: [String] = [],
        aliases: [String] = [],
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        template: String? = nil,
        ocrText: String? = nil,
        linkedNotes: [String] = [],
        customFields: [String: String] = [:],
        isEncrypted: Bool = false
    ) {
        self.title = title
        self.tags = tags
        self.aliases = aliases
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.template = template
        self.ocrText = ocrText
        self.linkedNotes = linkedNotes
        self.customFields = customFields
        self.isEncrypted = isEncrypted
    }
}
