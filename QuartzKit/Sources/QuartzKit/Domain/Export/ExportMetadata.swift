import Foundation

/// Supported export formats for notes.
public enum ExportFormat: String, CaseIterable, Sendable {
    case pdf
    case html
    case rtf
    case markdown

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .html: "html"
        case .rtf: "rtf"
        case .markdown: "md"
        }
    }

    public var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .html: "HTML"
        case .rtf: "Rich Text (RTF)"
        case .markdown: "Markdown"
        }
    }

    public var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .html: "doc.text.fill"
        case .rtf: "doc.richtext.fill"
        case .markdown: "doc.plaintext"
        }
    }

    public var mimeType: String {
        switch self {
        case .pdf: "application/pdf"
        case .html: "text/html"
        case .rtf: "application/rtf"
        case .markdown: "text/markdown"
        }
    }
}

/// Optional metadata enriching an export.
public struct ExportMetadata: Sendable {
    public let author: String?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let tags: [String]
    public let vaultRootURL: URL?

    public init(
        author: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        tags: [String] = [],
        vaultRootURL: URL? = nil
    ) {
        self.author = author
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.vaultRootURL = vaultRootURL
    }
}
