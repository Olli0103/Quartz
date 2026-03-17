import Foundation

/// Use case for Share Extension: Receives shared content and saves it to the vault.
///
/// Supports text, URLs, and images. Saves either to an
/// "Inbox" note or creates a new note.
public struct ShareCaptureUseCase: Sendable {
    private var fileManager: FileManager { FileManager.default }

    public init() {}

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
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
            throw error
        }
    }

    /// Processes shared content and saves it to the vault.
    ///
    /// - Parameters:
    ///   - item: The shared content
    ///   - vaultRoot: Root URL of the vault
    ///   - mode: Inbox mode or new note
    /// - Returns: URL of the created/updated note
    public func capture(
        _ item: SharedItem,
        in vaultRoot: URL,
        mode: CaptureMode = .inbox
    ) throws -> URL {
        // Write image data to disk first if needed
        let resolvedItem = try writeImageAssetIfNeeded(item, vaultRoot: vaultRoot)

        switch mode {
        case .inbox:
            return try appendToInbox(resolvedItem, vaultRoot: vaultRoot)
        case .newNote(let title):
            return try createNewNote(resolvedItem, title: title, vaultRoot: vaultRoot)
        }
    }

    /// Writes image data to the assets folder and returns an updated SharedItem with the correct path.
    /// Thread-safe timestamp generator for asset filenames.
    private static func assetTimestamp() -> String {
        // ISO8601DateFormatter is thread-safe, unlike DateFormatter
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate,
                           .withTime, .withColonSeparatorInTime]
        return f.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func writeImageAssetIfNeeded(_ item: SharedItem, vaultRoot: URL) throws -> SharedItem {
        guard case .image(let imageData, let caption) = item else { return item }

        let assetsFolder = vaultRoot.appending(path: "assets")
        try fileManager.createDirectory(at: assetsFolder, withIntermediateDirectories: true)

        let fileName = "capture-\(Self.assetTimestamp()).png"
        let imageURL = assetsFolder.appending(path: fileName)

        try coordinatedWrite(imageData, to: imageURL)

        return .image(imageData, caption: caption, assetPath: "assets/\(fileName)")
    }

    // MARK: - Private

    // ISO8601DateFormatter is thread-safe (unlike DateFormatter)
    private static let iso8601Formatter = ISO8601DateFormatter()
    // DateFormatter is NOT thread-safe; create per-use for Sendable struct
    private static func formattedTime() -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: Date())
    }

    private func appendToInbox(_ item: SharedItem, vaultRoot: URL) throws -> URL {
        let inboxURL = vaultRoot.appending(path: "Inbox.md")
        let now = Self.iso8601Formatter.string(from: Date())

        let entry = "\n\n---\n_Captured \(Self.formattedTime())_\n\n\(item.markdownContent)"

        if fileManager.fileExists(atPath: inboxURL.path(percentEncoded: false)) {
            var existing = try String(contentsOf: inboxURL, encoding: .utf8)
            existing.append(entry)
            guard let data = existing.data(using: .utf8) else { throw FileSystemError.encodingFailed(inboxURL) }
            try coordinatedWrite(data, to: inboxURL)
        } else {
            let content = """
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
            guard let contentData = content.data(using: .utf8) else { throw FileSystemError.encodingFailed(inboxURL) }
            try coordinatedWrite(contentData, to: inboxURL)
        }

        return inboxURL
    }

    private func createNewNote(_ item: SharedItem, title: String, vaultRoot: URL) throws -> URL {
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let fileName = safeTitle.hasSuffix(".md") ? safeTitle : "\(safeTitle).md"
        let fileURL = vaultRoot.appending(path: fileName)
        let now = Self.iso8601Formatter.string(from: Date())

        // Quote title if it contains YAML special characters
        let yamlTitle = Self.yamlSafeString(safeTitle)

        let content = """
        ---
        title: \(yamlTitle)
        tags: [capture]
        created: \(now)
        modified: \(now)
        ---

        \(item.markdownContent)
        """

        guard let data = content.data(using: .utf8) else {
            throw FileSystemError.encodingFailed(fileURL)
        }
        try coordinatedWrite(data, to: fileURL)
        return fileURL
    }

    /// Escapes a string for safe YAML value insertion, quoting if it contains special characters.
    private static func yamlSafeString(_ value: String) -> String {
        let specialChars = CharacterSet(charactersIn: ":{}[]#&*!|>'\"%@`,")
        guard value.rangeOfCharacter(from: specialChars) != nil ||
              value.hasPrefix(" ") || value.hasSuffix(" ") else {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Supporting Types

/// A shared content item from the Share Extension.
public enum SharedItem: Sendable {
    case text(String)
    case url(URL, title: String?)
    case image(Data, caption: String?, assetPath: String? = nil)
    case mixed(text: String, url: URL?)

    /// Markdown representation of the shared content.
    public var markdownContent: String {
        switch self {
        case .text(let text):
            return text

        case .url(let url, let title):
            let displayTitle = title ?? url.host() ?? url.absoluteString
            return "[\(displayTitle)](\(url.absoluteString))"

        case .image(_, let caption, let assetPath):
            let path = assetPath ?? "attachment.png"
            if let caption {
                return "![\(caption)](\(path))\n\n\(caption)"
            }
            return "![Captured Image](\(path))"

        case .mixed(let text, let url):
            if let url {
                return "\(text)\n\n[\(url.absoluteString)](\(url.absoluteString))"
            }
            return text
        }
    }
}

/// Mode for the capture function.
public enum CaptureMode: Sendable {
    case inbox
    case newNote(title: String)
}
