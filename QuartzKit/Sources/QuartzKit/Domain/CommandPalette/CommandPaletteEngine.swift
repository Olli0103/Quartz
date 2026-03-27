import Foundation

/// Search engine for the command palette.
///
/// Merges note search (from `NotePreviewRepository`) with command search
/// (from `CommandRegistry`). Debounces keystrokes at 100ms, ranks results
/// by score, and caps at 10 total.
///
/// **Empty query**: Shows 7 recent notes + 3 pinned commands.
/// **With query**: Parallel note + command fuzzy match, merged by score.
///
/// **Ref:** Phase H1 Spec — CommandPaletteEngine
@Observable
@MainActor
public final class CommandPaletteEngine {

    // MARK: - Public State

    /// Current search query — set by the TextField.
    public var searchText: String = "" {
        didSet { performSearch() }
    }

    /// Merged results (notes + commands), sorted by score.
    public private(set) var results: [PaletteItem] = []

    /// Currently selected row index for keyboard navigation.
    public var selectedIndex: Int = 0

    // MARK: - Dependencies

    private let previewRepository: NotePreviewRepository?
    private let commands: [PaletteCommand]
    private let vaultRootURL: URL?
    private var searchTask: Task<Void, Never>?

    private static let maxResults = 10
    private static let maxNotes = 7
    private static let maxCommands = 5
    private static let debounceInterval: Duration = .milliseconds(100)

    // MARK: - Init

    public init(
        previewRepository: NotePreviewRepository?,
        commands: [PaletteCommand],
        vaultRootURL: URL? = nil
    ) {
        self.previewRepository = previewRepository
        self.commands = commands
        self.vaultRootURL = vaultRootURL

        // Show default state immediately
        Task {
            results = await buildDefaultResults()
        }
    }

    // MARK: - Keyboard Navigation

    /// Moves selection up (wraps to bottom).
    public func moveSelectionUp() {
        guard !results.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = results.count - 1
        }
    }

    /// Moves selection down (wraps to top).
    public func moveSelectionDown() {
        guard !results.isEmpty else { return }
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }
    }

    /// Executes the currently selected item. Returns the note URL if a note was selected.
    @discardableResult
    public func executeSelected() -> URL? {
        guard selectedIndex >= 0, selectedIndex < results.count else { return nil }
        let item = results[selectedIndex]
        switch item {
        case .note(let noteResult):
            return noteResult.url
        case .command(let command):
            command.action()
            return nil
        }
    }

    // MARK: - Search

    private func performSearch() {
        searchTask?.cancel()
        selectedIndex = 0

        let query = searchText.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            Task {
                results = await buildDefaultResults()
            }
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }

            // Parallel: notes + commands
            async let noteResults = searchNotes(query: query)
            let commandResults = searchCommands(query: query)

            guard !Task.isCancelled else { return }

            let notes = await noteResults
            let merged = mergeResults(notes: notes, commands: commandResults)
            results = merged
        }
    }

    // MARK: - Note Search

    private func searchNotes(query: String) async -> [NoteResult] {
        guard let repo = previewRepository else { return [] }

        let allPreviews = await repo.allPreviews()
        let queryLower = query.lowercased()
        let rootPath = vaultRootURL?.path(percentEncoded: false) ?? ""

        var results: [NoteResult] = []

        for preview in allPreviews {
            let titleLower = preview.title.lowercased()
            var score = 0

            // Title scoring
            if titleLower == queryLower {
                score = 15 // exact match
            } else if titleLower.hasPrefix(queryLower) {
                score = 12 // starts with
            } else if titleLower.contains(queryLower) {
                score = 10 // contains
            } else if preview.snippet.lowercased().contains(queryLower) {
                score = 3  // snippet match
            } else {
                continue // no match
            }

            // Recency bonus
            let age = -preview.modifiedAt.timeIntervalSinceNow
            if age < 3600 { score += 2 }       // modified in last hour
            else if age < 86400 { score += 1 }  // modified in last 24h

            let folderPath = computeFolderPath(for: preview.url, rootPath: rootPath)

            results.append(NoteResult(
                url: preview.url,
                title: preview.title,
                folderPath: folderPath,
                modifiedAt: preview.modifiedAt,
                snippet: preview.snippet,
                matchScore: score
            ))
        }

        return results
            .sorted { $0.matchScore > $1.matchScore }
            .prefix(Self.maxNotes)
            .map { $0 }
    }

    // MARK: - Command Search

    private func searchCommands(query: String) -> [PaletteItem] {
        let queryLower = query.lowercased()
        var scored: [(command: PaletteCommand, score: Int)] = []

        for command in commands {
            let titleLower = command.title.lowercased()
            var score = 0

            if titleLower.hasPrefix(queryLower) {
                score = 10
            } else if titleLower.contains(queryLower) {
                score = 8
            } else if command.keywords.contains(where: { $0.hasPrefix(queryLower) }) {
                score = 6
            } else if command.keywords.contains(where: { $0.contains(queryLower) }) {
                score = 4
            } else {
                continue
            }

            scored.append((command: command, score: score))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(Self.maxCommands)
            .map { .command($0.command) }
    }

    // MARK: - Merge

    private func mergeResults(notes: [NoteResult], commands: [PaletteItem]) -> [PaletteItem] {
        var all: [(item: PaletteItem, score: Int)] = []

        for note in notes {
            all.append((.note(note), note.matchScore))
        }

        for cmd in commands {
            // Commands from searchCommands already have their score baked in at ranking time.
            // Give them a base score of 5 so they interleave reasonably with notes.
            all.append((cmd, 5))
        }

        return all
            .sorted { $0.score > $1.score }
            .prefix(Self.maxResults)
            .map(\.item)
    }

    // MARK: - Default Results (Empty Query)

    private func buildDefaultResults() async -> [PaletteItem] {
        var items: [PaletteItem] = []

        // Recent notes (up to 7)
        if let repo = previewRepository {
            let allPreviews = await repo.allPreviews()
            let rootPath = vaultRootURL?.path(percentEncoded: false) ?? ""

            let recent = allPreviews
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(Self.maxNotes)

            for preview in recent {
                let folderPath = computeFolderPath(for: preview.url, rootPath: rootPath)
                items.append(.note(NoteResult(
                    url: preview.url,
                    title: preview.title,
                    folderPath: folderPath,
                    modifiedAt: preview.modifiedAt,
                    snippet: preview.snippet,
                    matchScore: 0
                )))
            }
        }

        // Pinned commands (up to 3)
        let pinned = commands.filter { CommandRegistry.pinnedCommandIDs.contains($0.id) }
        for command in pinned.prefix(3) {
            items.append(.command(command))
        }

        return items
    }

    // MARK: - Helpers

    private func computeFolderPath(for url: URL, rootPath: String) -> String {
        let parent = url.deletingLastPathComponent().path(percentEncoded: false)
        guard !rootPath.isEmpty, parent.hasPrefix(rootPath) else {
            return "/"
        }
        let relative = String(parent.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "/" : relative + "/"
    }
}
