#if canImport(AppIntents)
import AppIntents

// MARK: - Vault + Service (MainActor)

@MainActor
private func sharedVaultRootURL() -> URL? {
    let d = UserDefaults(suiteName: "group.app.quartz.shared")
    return d?.url(forKey: "activeVaultURL") ?? d?.url(forKey: "defaultVaultRoot")
}

@MainActor
private func bootstrapAndResolveProvider() -> any VaultProviding {
    ServiceContainer.shared.bootstrap()
    return ServiceContainer.shared.resolveVaultProvider()
}

// MARK: - Create Note

/// Creates a Markdown note in the active vault (Shortcuts, widgets, Siri).
@available(iOS 16.0, macOS 13.0, *)
public struct CreateNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Note"
    public static let description: IntentDescription = "Creates a new note in your Quartz vault using the active vault folder."
    /// Opens Quartz so you can continue editing the new note (ideal for Home Screen actions).
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Title", description: "File name for the note (without .md); leave empty for a timestamped Quick Note", default: "")
    public var noteTitle: String

    @Parameter(title: "Content", description: "Initial note body (Markdown)", default: "")
    public var noteContent: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let vaultRoot = await MainActor.run { sharedVaultRootURL() }
        guard let vaultRoot else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No vault configured. Open Quartz and choose a vault first.", bundle: .module)))
        }
        let provider = await MainActor.run { bootstrapAndResolveProvider() }
        let trimmed = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if trimmed.isEmpty {
            let df = DateFormatter()
            df.locale = .current
            df.dateFormat = "yyyy-MM-dd HH.mm"
            name = "\(String(localized: "Quick Note", bundle: .module)) \(df.string(from: Date()))"
        } else {
            name = trimmed.hasSuffix(".md") ? String(trimmed.dropLast(3)) : trimmed
        }
        do {
            _ = try await provider.createNote(named: name, in: vaultRoot, initialContent: noteContent)
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Created note “\(name)”.", bundle: .module)))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

// MARK: - Append To Note

/// Appends Markdown text to an existing note (matched by file name).
@available(iOS 16.0, macOS 13.0, *)
public struct AppendToNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Append to Note"
    public static let description: IntentDescription = "Appends text to the end of an existing note in your vault."
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Note Name", description: "Note file name without path (e.g. Meeting Notes)")
    public var noteName: String

    @Parameter(title: "Text to Append", description: "Markdown appended after a short separator")
    public var text: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let vaultRoot = await MainActor.run { sharedVaultRootURL() }
        guard let vaultRoot else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No vault configured.", bundle: .module)))
        }
        let provider = await MainActor.run { bootstrapAndResolveProvider() }
        let url = try await Self.findNoteURL(named: noteName, in: vaultRoot)
        guard let url else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Could not find that note in the vault.", bundle: .module)))
        }
        var doc = try await provider.readNote(at: url)
        let addition = text.hasPrefix("\n") ? text : "\n\n" + text
        doc.body += addition
        try await provider.saveNote(doc)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Appended to “\(url.deletingPathExtension().lastPathComponent)”.", bundle: .module)))
    }

    private static func findNoteURL(named name: String, in vaultRoot: URL) async throws -> URL? {
        await Task.detached {
            Self.findNoteURLSync(named: name, in: vaultRoot)
        }.value
    }

    private nonisolated static func findNoteURLSync(named name: String, in vaultRoot: URL) -> URL? {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        let withoutExt = base.hasSuffix(".md") ? String(base.dropLast(3)) : base
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vaultRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let target = withoutExt.lowercased()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let n = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            if n == target { return fileURL }
        }
        return nil
    }
}

// MARK: - Search Vault

/// Searches note titles and bodies under the vault for a query string.
@available(iOS 16.0, macOS 13.0, *)
public struct SearchVaultIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search Vault"
    public static let description: IntentDescription = "Searches your Quartz vault for Markdown notes matching a query."
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Query", description: "Text to search for in note names and contents")
    public var query: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let vaultRoot = await MainActor.run { sharedVaultRootURL() }
        guard let vaultRoot else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No vault configured.", bundle: .module)))
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Enter a search query.", bundle: .module)))
        }
        let matches = await Self.searchMarkdownFiles(in: vaultRoot, query: q, limit: 8)
        if matches.isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No notes matched “\(query)”.", bundle: .module)))
        }
        let lines = matches.map(\URL.lastPathComponent).joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: lines))
    }

    private nonisolated static func searchMarkdownFiles(in vaultRoot: URL, query: String, limit: Int) async -> [URL] {
        await Task.detached(priority: .utility) {
            Self.searchMarkdownFilesSync(in: vaultRoot, query: query, limit: limit)
        }.value
    }

    private nonisolated static func searchMarkdownFilesSync(in vaultRoot: URL, query: String, limit: Int) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: vaultRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var results: [(URL, Int)] = []
        let needle = query
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            let name = fileURL.lastPathComponent.lowercased()
            var score = 0
            if name.contains(needle) { score += 2 }
            if let data = try? Data(contentsOf: fileURL), let s = String(data: data, encoding: .utf8) {
                if s.lowercased().contains(needle) { score += 1 }
            }
            if score > 0 {
                results.append((fileURL, score))
            }
        }
        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(limit).map(\.0))
    }
}

// MARK: - Open Note Intent

/// Opens a note by vault-relative path (used by widgets, Shortcuts, and Siri).
@available(iOS 16.0, macOS 13.0, *)
public struct OpenNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Note"
    public static let description: IntentDescription = "Opens a Markdown note in Quartz using its path inside the vault."
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Path in Vault", description: "Path relative to the vault root, e.g. Ideas/Meeting.md")
    public var relativePath: String

    public init() {
        self.relativePath = ""
    }

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    public func perform() async throws -> some IntentResult {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result() }
        var url = URL(string: "quartz://note")!
        for segment in trimmed.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }
        UserDefaults(suiteName: "group.app.quartz.shared")?.set(url.absoluteString, forKey: "pendingDeepLink")
        return .result()
    }
}

// MARK: - Daily Note Intent

@available(iOS 16.0, macOS 13.0, *)
public struct DailyNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Daily Note"
    public static let description: IntentDescription = "Creates or opens today's daily note in the active vault."
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let vaultRoot = await MainActor.run { sharedVaultRootURL() }
        guard let vaultRoot else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No vault configured.", bundle: .module)))
        }
        let templateService = VaultTemplateService()
        do {
            let url = try await templateService.createDailyNote(in: vaultRoot)
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Daily note ready: \(url.lastPathComponent)", bundle: .module)))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

// MARK: - App Shortcuts Provider

/// Opens the app into voice recording mode (widgets, Siri, Control Center).
@available(iOS 16.0, macOS 13.0, *)
public struct CaptureAudioIntent: AppIntent {
    public static let title: LocalizedStringResource = "Record Voice Note"
    public static let description: IntentDescription = "Opens Quartz and starts voice recording."
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.app.quartz.shared")?
            .set("quartz://audio", forKey: "pendingDeepLink")
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, macOS 13.0, *)
public struct QuartzShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)",
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AppendToNoteIntent(),
            phrases: [
                "Append to a note in \(.applicationName)",
                "Add text to note in \(.applicationName)",
            ],
            shortTitle: "Append to Note",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: SearchVaultIntent(),
            phrases: [
                "Search my vault in \(.applicationName)",
                "Find notes in \(.applicationName)",
            ],
            shortTitle: "Search Vault",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: DailyNoteIntent(),
            phrases: [
                "Open daily note in \(.applicationName)",
                "Today's note in \(.applicationName)",
            ],
            shortTitle: "Daily Note",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: [
                "Open a note in \(.applicationName)",
            ],
            shortTitle: "Open Note",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: CaptureAudioIntent(),
            phrases: [
                "Record a voice note in \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Voice Note",
            systemImageName: "mic.fill"
        )
    }
}
#endif
