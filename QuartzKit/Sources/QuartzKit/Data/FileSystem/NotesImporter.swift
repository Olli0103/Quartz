import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

/// Imports notes from various file formats (HTML, TXT, RTF, PDF, MD) into a Quartz vault.
///
/// Usage: Point at a folder containing exported notes from any source.
/// Each file is converted to Markdown and placed in the vault.
public actor NotesImporter {
    private let fileManager = FileManager.default
    private let writer = CoordinatedFileWriter.shared

    public init() {}

    public struct ImportResult: Sendable {
        public let imported: Int
        public let skipped: Int
        public let foldersCreated: Int
        public let errors: [String]
    }

    /// Import all supported files from a source folder into the vault,
    /// recursively preserving the original folder structure.
    public func importNotes(from sourceFolder: URL, into vaultFolder: URL) throws -> ImportResult {
        let supportedExtensions = Set(["txt", "html", "htm", "rtf", "md", "pdf"])

        var imported = 0
        var skipped = 0
        var foldersCreated = 0
        var errors: [String] = []

        let importRoot = vaultFolder.appending(path: "Imported")
        if !fileManager.fileExists(atPath: importRoot.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: importRoot, withIntermediateDirectories: true)
            foldersCreated += 1
        }

        let sourcePath = sourceFolder.path(percentEncoded: false)

        guard let enumerator = fileManager.enumerator(
            at: sourceFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ImportResult(imported: 0, skipped: 0, foldersCreated: foldersCreated, errors: ["Could not enumerate source folder"])
        }

        while let itemURL = enumerator.nextObject() as? URL {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relativePath = itemURL.path(percentEncoded: false)
                .replacingOccurrences(of: sourcePath, with: "")

            if isDir {
                let destFolder = importRoot.appending(path: relativePath)
                if !fileManager.fileExists(atPath: destFolder.path(percentEncoded: false)) {
                    try fileManager.createDirectory(at: destFolder, withIntermediateDirectories: true)
                    foldersCreated += 1
                }
            } else {
                guard supportedExtensions.contains(itemURL.pathExtension.lowercased()) else { continue }

                do {
                    let markdown = try convertToMarkdown(itemURL)
                    let baseName = itemURL.deletingPathExtension().lastPathComponent
                    let relativeDir = (relativePath as NSString).deletingLastPathComponent
                    let destFolder = importRoot.appending(path: relativeDir)

                    if !fileManager.fileExists(atPath: destFolder.path(percentEncoded: false)) {
                        try fileManager.createDirectory(at: destFolder, withIntermediateDirectories: true)
                        foldersCreated += 1
                    }

                    let destURL = resolveCollision(
                        in: destFolder,
                        baseName: baseName.replacingOccurrences(of: "/", with: "-"),
                        ext: "md"
                    )

                    if destURL == nil {
                        skipped += 1
                        continue
                    }

                    let now = ISO8601DateFormatter().string(from: Date())
                    let fullContent = """
                    ---
                    title: \(baseName)
                    tags: [imported]
                    created: \(now)
                    modified: \(now)
                    ---

                    \(markdown)
                    """

                    try writer.write(Data(fullContent.utf8), to: destURL!)
                    imported += 1
                } catch {
                    errors.append("\(relativePath): \(error.localizedDescription)")
                }
            }
        }

        return ImportResult(imported: imported, skipped: skipped, foldersCreated: foldersCreated, errors: errors)
    }

    /// Returns a non-colliding destination URL by appending a numeric suffix when needed.
    private func resolveCollision(in folder: URL, baseName: String, ext: String) -> URL? {
        let candidate = folder.appending(path: "\(baseName).\(ext)")
        if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        for i in 2...999 {
            let numbered = folder.appending(path: "\(baseName) \(i).\(ext)")
            if !fileManager.fileExists(atPath: numbered.path(percentEncoded: false)) {
                return numbered
            }
        }

        return nil
    }

    private func convertToMarkdown(_ fileURL: URL) throws -> String {
        let ext = fileURL.pathExtension.lowercased()

        switch ext {
        case "md":
            return try String(contentsOf: fileURL, encoding: .utf8)

        case "txt":
            return try String(contentsOf: fileURL, encoding: .utf8)

        case "html", "htm":
            return try convertHTMLToMarkdown(fileURL)

        case "rtf":
            return try convertRTFToMarkdown(fileURL)

        case "pdf":
            return try convertPDFToMarkdown(fileURL)

        default:
            return try String(contentsOf: fileURL, encoding: .utf8)
        }
    }

    private func convertHTMLToMarkdown(_ fileURL: URL) throws -> String {
        let html = try String(contentsOf: fileURL, encoding: .utf8)
        var md = html
        md = md.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<h1[^>]*>(.*?)</h1>", with: "# $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<h2[^>]*>(.*?)</h2>", with: "## $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<h3[^>]*>(.*?)</h3>", with: "### $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<strong>(.*?)</strong>", with: "**$1**", options: .regularExpression)
        md = md.replacingOccurrences(of: "<b>(.*?)</b>", with: "**$1**", options: .regularExpression)
        md = md.replacingOccurrences(of: "<em>(.*?)</em>", with: "*$1*", options: .regularExpression)
        md = md.replacingOccurrences(of: "<i>(.*?)</i>", with: "*$1*", options: .regularExpression)
        md = md.replacingOccurrences(of: "<li>(.*?)</li>", with: "- $1", options: .regularExpression)
        md = md.replacingOccurrences(of: "<p>(.*?)</p>", with: "$1\n\n", options: .regularExpression)
        md = md.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        md = md.replacingOccurrences(of: "&amp;", with: "&")
        md = md.replacingOccurrences(of: "&lt;", with: "<")
        md = md.replacingOccurrences(of: "&gt;", with: ">")
        md = md.replacingOccurrences(of: "&nbsp;", with: " ")
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convertRTFToMarkdown(_ fileURL: URL) throws -> String {
        #if canImport(AppKit)
        let data = try Data(contentsOf: fileURL)
        let attrString = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attrString.string
        #else
        return try String(contentsOf: fileURL, encoding: .utf8)
        #endif
    }

    private func convertPDFToMarkdown(_ fileURL: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: fileURL) else {
            throw NSError(domain: "NotesImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Could not open PDF file", bundle: .module)])
        }
        var result = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if let text = page.string, !text.isEmpty {
                if i > 0 { result += "\n\n" }
                result += text
            }
        }
        return result.isEmpty ? String(localized: "[PDF contains no extractable text]", bundle: .module) : result
        #else
        throw NSError(domain: "NotesImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "PDF import is not supported on this platform", bundle: .module)])
        #endif
    }
}
