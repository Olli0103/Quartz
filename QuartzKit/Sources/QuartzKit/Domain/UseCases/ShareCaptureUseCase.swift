import Foundation

/// Use Case für Share Extension: Empfängt geteilte Inhalte und speichert sie im Vault.
///
/// Unterstützt Text, URLs und Bilder. Speichert entweder in einer
/// "Inbox"-Notiz oder erstellt eine neue Notiz.
public struct ShareCaptureUseCase: Sendable {
    private let fileManager = FileManager.default

    public init() {}

    /// Verarbeitet geteilten Inhalt und speichert ihn im Vault.
    ///
    /// - Parameters:
    ///   - item: Der geteilte Inhalt
    ///   - vaultRoot: Root-URL des Vaults
    ///   - mode: Inbox-Modus oder neue Notiz
    /// - Returns: URL der erstellten/aktualisierten Notiz
    public func capture(
        _ item: SharedItem,
        in vaultRoot: URL,
        mode: CaptureMode = .inbox
    ) throws -> URL {
        switch mode {
        case .inbox:
            return try appendToInbox(item, vaultRoot: vaultRoot)
        case .newNote(let title):
            return try createNewNote(item, title: title, vaultRoot: vaultRoot)
        }
    }

    // MARK: - Private

    private func appendToInbox(_ item: SharedItem, vaultRoot: URL) throws -> URL {
        let inboxURL = vaultRoot.appending(path: "Inbox.md")
        let now = ISO8601DateFormatter().string(from: Date())
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let entry = "\n\n---\n_Captured \(timeFormatter.string(from: Date()))_\n\n\(item.markdownContent)"

        if fileManager.fileExists(atPath: inboxURL.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: inboxURL)
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            try handle.close()
        } else {
            let frontmatter = """
            ---
            title: Inbox
            tags: [inbox, capture]
            created: \(now)
            modified: \(now)
            ---

            # Inbox

            Quick captures from Share Extension.
            \(entry)
            """
            try frontmatter.data(using: .utf8)?.write(to: inboxURL, options: .atomic)
        }

        return inboxURL
    }

    private func createNewNote(_ item: SharedItem, title: String, vaultRoot: URL) throws -> URL {
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
        let fileName = safeTitle.hasSuffix(".md") ? safeTitle : "\(safeTitle).md"
        let fileURL = vaultRoot.appending(path: fileName)
        let now = ISO8601DateFormatter().string(from: Date())

        let content = """
        ---
        title: \(safeTitle)
        tags: [capture]
        created: \(now)
        modified: \(now)
        ---

        \(item.markdownContent)
        """

        try content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

// MARK: - Supporting Types

/// Ein geteilter Inhalt aus der Share Extension.
public enum SharedItem: Sendable {
    case text(String)
    case url(URL, title: String?)
    case image(Data, caption: String?)
    case mixed(text: String, url: URL?)

    /// Markdown-Darstellung des geteilten Inhalts.
    public var markdownContent: String {
        switch self {
        case .text(let text):
            return text

        case .url(let url, let title):
            let displayTitle = title ?? url.host() ?? url.absoluteString
            return "[\(displayTitle)](\(url.absoluteString))"

        case .image(_, let caption):
            // Bild wird als Asset gespeichert, hier nur Referenz
            if let caption {
                return "![\(caption)](attachment.png)\n\n\(caption)"
            }
            return "![Captured Image](attachment.png)"

        case .mixed(let text, let url):
            if let url {
                return "\(text)\n\n[\(url.absoluteString)](\(url.absoluteString))"
            }
            return text
        }
    }
}

/// Modus für die Capture-Funktion.
public enum CaptureMode: Sendable {
    case inbox
    case newNote(title: String)
}
