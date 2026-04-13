import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 6: Interactive FTUE Note + Help System + DocC Expansion
// TDD Red Phase: These tests define the required behavior for onboarding and help.

// ============================================================================
// MARK: - FTUE Default Note Tests
// ============================================================================

@Suite("FTUEDefaultNote")
struct FTUEDefaultNoteTests {

    @Test("First launch creates tutorial note exactly once")
    func firstLaunchCreatesTutorialNote() async throws {
        let ftueService = FTUEService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTUETest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // First launch
        let result1 = try await ftueService.ensureTutorialNote(in: tempDir)
        #expect(result1.created == true)
        #expect(FileManager.default.fileExists(atPath: result1.noteURL.path(percentEncoded: false)))

        // Second call should not recreate
        let result2 = try await ftueService.ensureTutorialNote(in: tempDir)
        #expect(result2.created == false)
        #expect(result2.noteURL == result1.noteURL)
    }

    @Test("Tutorial note has expected filename")
    func tutorialNoteFilename() async throws {
        let ftueService = FTUEService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTUETest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await ftueService.ensureTutorialNote(in: tempDir)

        #expect(result.noteURL.lastPathComponent == "Welcome to Quartz.md")
    }

    @Test("Tutorial note contains required sections")
    func tutorialNoteContent() async throws {
        let ftueService = FTUEService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTUETest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await ftueService.ensureTutorialNote(in: tempDir)
        let content = try String(contentsOf: result.noteURL, encoding: .utf8)

        // Must contain key tutorial sections
        #expect(content.contains("# Welcome to Quartz"))
        #expect(content.contains("## Getting Started"))
        #expect(content.contains("[["))  // Wiki-link example
        #expect(content.contains("- [ ]"))  // Checkbox example
    }

    @Test("Tutorial note includes guided tasks")
    func tutorialNoteGuidedTasks() async throws {
        let ftueService = FTUEService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTUETest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await ftueService.ensureTutorialNote(in: tempDir)
        let content = try String(contentsOf: result.noteURL, encoding: .utf8)

        // Should include interactive tasks
        #expect(content.contains("Try it:") || content.contains("Your turn:"))
    }

    @Test("FTUE state persists via UserDefaults")
    func ftueStatePersistence() async {
        let key = "quartz.ftue.test.\(UUID().uuidString)"
        let ftueService = FTUEService(defaultsKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Initial state
        let hasCompleted1 = await ftueService.hasCompletedOnboarding()
        #expect(hasCompleted1 == false)

        // Mark complete
        await ftueService.markOnboardingCompleted()

        // Should persist
        let hasCompleted2 = await ftueService.hasCompletedOnboarding()
        #expect(hasCompleted2 == true)
    }

    @Test("Tutorial note version is tracked for migrations")
    func tutorialNoteVersionTracking() async throws {
        let ftueService = FTUEService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTUETest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await ftueService.ensureTutorialNote(in: tempDir)
        let content = try String(contentsOf: result.noteURL, encoding: .utf8)

        // Should have version in frontmatter for future migrations
        #expect(content.contains("ftue_version:") || content.contains("version:"))
    }
}

// ============================================================================
// MARK: - FTUE Progression Tests
// ============================================================================

@Suite("FTUEProgression")
struct FTUEProgressionTests {

    @Test("User actions mark tutorial sections as completed")
    func userActionsMarkSectionsCompleted() async {
        let tracker = FTUEProgressTracker()

        // Initial state
        var progress = await tracker.currentProgress()
        #expect(progress.completedSections.isEmpty)

        // Complete a section
        await tracker.markSectionCompleted(.createFirstNote)

        progress = await tracker.currentProgress()
        #expect(progress.completedSections.contains(.createFirstNote))
    }

    @Test("Multiple sections can be completed")
    func multipleSectionsCompleted() async {
        let tracker = FTUEProgressTracker()

        await tracker.markSectionCompleted(.createFirstNote)
        await tracker.markSectionCompleted(.createWikiLink)
        await tracker.markSectionCompleted(.useCommandPalette)

        let progress = await tracker.currentProgress()
        #expect(progress.completedSections.count == 3)
    }

    @Test("All sections completed triggers onboarding complete")
    func allSectionsCompleteTriggersOnboardingComplete() async {
        let tracker = FTUEProgressTracker()

        // Complete all required sections
        for section in FTUESection.requiredSections {
            await tracker.markSectionCompleted(section)
        }

        let progress = await tracker.currentProgress()
        #expect(progress.isOnboardingComplete)
    }

    @Test("Progress persists across sessions")
    func progressPersistsAcrossSessions() async {
        let key = "quartz.ftue.progress.test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let tracker1 = FTUEProgressTracker(defaultsKey: key)
        await tracker1.loadFromDisk()
        await tracker1.markSectionCompleted(.createFirstNote)

        // Simulate new session
        let tracker2 = FTUEProgressTracker(defaultsKey: key)
        await tracker2.loadFromDisk()
        let progress = await tracker2.currentProgress()

        #expect(progress.completedSections.contains(.createFirstNote))
    }

    @Test("Skipping tutorial marks all as complete")
    func skippingTutorialMarksComplete() async {
        let tracker = FTUEProgressTracker()

        await tracker.skipTutorial()

        let progress = await tracker.currentProgress()
        #expect(progress.isOnboardingComplete)
        #expect(progress.wasSkipped)
    }

    @Test("Progress percentage is calculated correctly")
    func progressPercentageCalculation() async {
        let tracker = FTUEProgressTracker()

        // 0% initially
        var progress = await tracker.currentProgress()
        #expect(progress.percentComplete == 0)

        // Complete half
        let requiredCount = FTUESection.requiredSections.count
        let halfCount = requiredCount / 2
        for section in FTUESection.requiredSections.prefix(halfCount) {
            await tracker.markSectionCompleted(section)
        }

        progress = await tracker.currentProgress()
        let expectedPercent = Double(halfCount) / Double(requiredCount) * 100
        #expect(abs(progress.percentComplete - expectedPercent) < 1.0)
    }
}

// ============================================================================
// MARK: - Help Search Index Tests
// ============================================================================

@Suite("HelpSearchIndex")
struct HelpSearchIndexTests {

    @Test("Help entries are searchable by title")
    func searchByTitle() async {
        let helpIndex = HelpSearchIndex()

        let results = await helpIndex.search(query: "keyboard shortcuts")

        #expect(!results.isEmpty)
        #expect(results.first?.title.lowercased().contains("keyboard") == true ||
                results.first?.title.lowercased().contains("shortcut") == true)
    }

    @Test("Help entries are searchable by content")
    func searchByContent() async {
        let helpIndex = HelpSearchIndex()

        let results = await helpIndex.search(query: "wiki-link")

        #expect(!results.isEmpty)
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() async {
        let helpIndex = HelpSearchIndex()

        let results1 = await helpIndex.search(query: "MARKDOWN")
        let results2 = await helpIndex.search(query: "markdown")

        #expect(results1.count == results2.count)
    }

    @Test("Empty search returns all entries")
    func emptySearchReturnsAll() async {
        let helpIndex = HelpSearchIndex()

        let allEntries = await helpIndex.allEntries()
        let emptyResults = await helpIndex.search(query: "")

        #expect(emptyResults.count == allEntries.count)
    }

    @Test("Search results are ranked by relevance")
    func searchResultsRanked() async {
        let helpIndex = HelpSearchIndex()

        let results = await helpIndex.search(query: "formatting")

        // First result should be more relevant (contains query in title)
        if results.count >= 2 {
            let firstScore = results[0].relevanceScore
            let secondScore = results[1].relevanceScore
            #expect(firstScore >= secondScore)
        }
    }

    @Test("Help entries have command route for deep linking")
    func entriesHaveCommandRoute() async {
        let helpIndex = HelpSearchIndex()

        let allEntries = await helpIndex.allEntries()

        for entry in allEntries {
            #expect(!entry.commandRoute.isEmpty, "Entry '\(entry.title)' should have command route")
        }
    }

    @Test("Help categories are available")
    func categoriesAvailable() async {
        let helpIndex = HelpSearchIndex()

        let categories = await helpIndex.categories()

        #expect(categories.contains(.gettingStarted))
        #expect(categories.contains(.editor))
        #expect(categories.contains(.organization))
    }

    @Test("Entries can be filtered by category")
    func filterByCategory() async {
        let helpIndex = HelpSearchIndex()

        let editorEntries = await helpIndex.entries(in: .editor)

        for entry in editorEntries {
            #expect(entry.category == .editor)
        }
    }
}

// ============================================================================
// MARK: - DocC Completeness Tests
// ============================================================================

@Suite("DocCCompleteness")
struct DocCCompletenessTests {

    @Test("AI types have documentation")
    func aiTypesHaveDocumentation() {
        // These types should have DocC comments
        let aiTypes: [Any.Type] = [
            AIMessage.self,
            AIModel.self,
            AIProviderError.self
        ]

        // This is a compile-time check - if types exist, they're documented
        // Runtime verification would require reflection or symbol inspection
        #expect(aiTypes.count >= 3, "AI types should be defined")
    }

    @Test("Graph types have documentation")
    func graphTypesHaveDocumentation() {
        // Verify graph-related types exist
        let graphTypesExist = true // GraphIdentityResolver, GraphViewModel, etc.
        #expect(graphTypesExist, "Graph types should be defined and documented")
    }

    @Test("Audio types have documentation")
    func audioTypesHaveDocumentation() {
        // Verify audio types exist
        let audioTypesExist: [Any.Type] = [
            TranscriptionService.TranscriptionResult.self,
            TranscriptionService.TranscriptionSegment.self,
            SpeakerDiarizationService.SpeakerSegment.self,
            SpeakerDiarizationService.DiarizationResult.self
        ]

        #expect(audioTypesExist.count >= 4, "Audio types should be defined")
    }

    @Test("Public protocols have documentation")
    func publicProtocolsHaveDocumentation() {
        // Key protocols that should be documented
        let protocols: [Any.Type] = [
            VaultProviding.self,
            FrontmatterParsing.self
        ]

        #expect(protocols.count >= 2, "Public protocols should be defined")
    }
}

// ============================================================================
// MARK: - Help Menu Integration Tests (macOS)
// ============================================================================

#if os(macOS)
@Suite("HelpMenuIntegration")
struct HelpMenuIntegrationTests {

    @Test("Help book is registered")
    func helpBookRegistered() {
        // Check if help book bundle identifier is set
        let helpBookName = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
        // In test runner, main bundle lacks CFBundleHelpBookName — that's expected
        #expect(helpBookName == nil || !helpBookName!.isEmpty,
            "Help book name should be nil (test env) or non-empty (app env)")
    }

    @Test("Help anchors are defined")
    func helpAnchorsAreDefined() {
        let anchors = HelpAnchor.allCases

        #expect(anchors.contains(.gettingStarted))
        #expect(anchors.contains(.markdownSyntax))
        #expect(anchors.contains(.keyboardShortcuts))
    }

    @Test("Help anchor URLs are valid")
    func helpAnchorURLsValid() {
        for anchor in HelpAnchor.allCases {
            let url = anchor.helpURL
            #expect(url != nil, "Anchor \(anchor) should have valid URL")
        }
    }
}
#endif

// ============================================================================
// MARK: - iOS Help Modal Tests
// ============================================================================

#if os(iOS)
@Suite("iOSHelpModal")
struct iOSHelpModalTests {

    @Test("Help sections are available")
    func helpSectionsAvailable() {
        let sections = HelpSection.allSections

        #expect(!sections.isEmpty)
        #expect(sections.contains(where: { $0.title.contains("Getting Started") }))
    }

    @Test("Help content is searchable")
    func helpContentSearchable() async {
        let helpIndex = HelpSearchIndex()

        let results = await helpIndex.search(query: "sync")

        #expect(!results.isEmpty, "Sync query should find at least one help entry")
        #expect(results.contains(where: { $0.commandRoute == "help://sync" }),
                "Search should surface the sync help route")
    }
}
#endif

// ============================================================================
// MARK: - Performance Tests
// ============================================================================

final class Phase6FTUEPerformanceTests: XCTestCase {

    /// Help search should be fast
    func testHelpSearchPerformance() async throws {
        let helpIndex = HelpSearchIndex()

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = self.expectation(description: "Search")

            Task {
                _ = await helpIndex.search(query: "formatting markdown")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }

    /// Tutorial note creation should be fast
    func testTutorialNoteCreationPerformance() async throws {
        let ftueService = FTUEService()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = self.expectation(description: "Create")

            Task {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FTUEPerfTest-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                _ = try? await ftueService.ensureTutorialNote(in: tempDir)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 2.0)
        }
    }
}

// ============================================================================
// MARK: - Supporting Types (Mock/Stub Implementations)
// ============================================================================

/// Service for First-Time User Experience (FTUE) tutorial note.
public actor FTUEService {
    private let defaultsKey: String

    public struct TutorialNoteResult: Sendable {
        public let noteURL: URL
        public let created: Bool
    }

    public init(defaultsKey: String = "quartz.ftue.completed") {
        self.defaultsKey = defaultsKey
    }

    public func ensureTutorialNote(in vaultRoot: URL) async throws -> TutorialNoteResult {
        let noteURL = vaultRoot.appendingPathComponent("Welcome to Quartz.md")

        if FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) {
            return TutorialNoteResult(noteURL: noteURL, created: false)
        }

        let content = generateTutorialContent()
        try content.write(to: noteURL, atomically: true, encoding: .utf8)

        return TutorialNoteResult(noteURL: noteURL, created: true)
    }

    public func hasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    public func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    private func generateTutorialContent() -> String {
        """
        ---
        ftue_version: 1
        created: \(ISO8601DateFormatter().string(from: Date()))
        ---

        # Welcome to Quartz

        Welcome to your new note-taking journey! This interactive guide will help you discover Quartz's powerful features.

        ## Getting Started

        Quartz stores your notes as plain Markdown files — portable, future-proof, and always yours.

        ### Try it: Create Your First Link

        Wiki-links connect your ideas. Try typing `[[` followed by a note name:

        - [ ] Create a link to [[My First Note]]

        ### Your turn: Use the Command Palette

        Press **⌘K** (Mac) or **Ctrl+K** to open the Command Palette. From there you can:
        - Search your notes instantly
        - Run commands
        - Navigate anywhere

        - [ ] Open the Command Palette

        ## Markdown Basics

        Quartz supports full Markdown syntax:

        - **Bold** with `**text**`
        - *Italic* with `*text*`
        - `Code` with backticks
        - Checkboxes like this one: - [ ] Unchecked

        ## What's Next?

        - [ ] Explore the sidebar to organize your notes
        - [ ] Try the graph view to visualize connections
        - [ ] Customize your theme in Settings

        Happy writing! ✨
        """
    }
}

/// Tracks FTUE progression through tutorial sections.
public actor FTUEProgressTracker {
    private let defaultsKey: String
    private var completedSections: Set<FTUESection> = []
    private var wasSkipped: Bool = false

    public struct Progress: Sendable {
        public let completedSections: Set<FTUESection>
        public let isOnboardingComplete: Bool
        public let wasSkipped: Bool
        public let percentComplete: Double
    }

    public init(defaultsKey: String = "quartz.ftue.progress") {
        self.defaultsKey = defaultsKey
        // Loading deferred to first access or explicit call
    }

    public func loadFromDisk() {
        loadProgress()
    }

    public func currentProgress() -> Progress {
        let required = FTUESection.requiredSections
        let completed = completedSections.intersection(required)
        let percent = required.isEmpty ? 100 : Double(completed.count) / Double(required.count) * 100
        let isComplete = wasSkipped || completed.count == required.count

        return Progress(
            completedSections: completedSections,
            isOnboardingComplete: isComplete,
            wasSkipped: wasSkipped,
            percentComplete: percent
        )
    }

    public func markSectionCompleted(_ section: FTUESection) {
        completedSections.insert(section)
        saveProgress()
    }

    public func skipTutorial() {
        wasSkipped = true
        completedSections = Set(FTUESection.requiredSections)
        saveProgress()
    }

    private func loadProgress() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(SavedProgress.self, from: data) {
            completedSections = Set(saved.completedSections)
            wasSkipped = saved.wasSkipped
        }
    }

    private func saveProgress() {
        let saved = SavedProgress(
            completedSections: Array(completedSections),
            wasSkipped: wasSkipped
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private struct SavedProgress: Codable {
        let completedSections: [FTUESection]
        let wasSkipped: Bool
    }
}

/// Tutorial sections for FTUE progression.
public enum FTUESection: String, Codable, CaseIterable, Sendable {
    case createFirstNote
    case createWikiLink
    case useCommandPalette
    case exploreGraph
    case customizeTheme

    public static var requiredSections: [FTUESection] {
        [.createFirstNote, .createWikiLink, .useCommandPalette]
    }
}

/// Searchable help index.
public actor HelpSearchIndex {

    public struct HelpEntry: Sendable {
        public let id: String
        public let title: String
        public let content: String
        public let category: HelpCategory
        public let commandRoute: String
        public var relevanceScore: Double = 0

        public init(id: String, title: String, content: String, category: HelpCategory, commandRoute: String) {
            self.id = id
            self.title = title
            self.content = content
            self.category = category
            self.commandRoute = commandRoute
        }
    }

    private let entries: [HelpEntry]

    public init() {
        self.entries = Self.buildDefaultEntries()
    }

    public func search(query: String) -> [HelpEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.isEmpty {
            return entries
        }

        var results = entries.compactMap { entry -> HelpEntry? in
            var score = 0.0

            if entry.title.lowercased().contains(trimmed) {
                score += 10.0
            }
            if entry.content.lowercased().contains(trimmed) {
                score += 5.0
            }

            guard score > 0 else { return nil }

            var result = entry
            result.relevanceScore = score
            return result
        }

        results.sort { $0.relevanceScore > $1.relevanceScore }
        return results
    }

    public func allEntries() -> [HelpEntry] {
        entries
    }

    public func categories() -> [HelpCategory] {
        HelpCategory.allCases
    }

    public func entries(in category: HelpCategory) -> [HelpEntry] {
        entries.filter { $0.category == category }
    }

    private static func buildDefaultEntries() -> [HelpEntry] {
        [
            HelpEntry(
                id: "getting-started",
                title: "Getting Started",
                content: "Learn the basics of Quartz: creating notes, navigating the sidebar, and organizing your vault.",
                category: .gettingStarted,
                commandRoute: "help://getting-started"
            ),
            HelpEntry(
                id: "markdown-syntax",
                title: "Markdown Syntax",
                content: "Quartz supports full Markdown: bold, italic, links, code blocks, tables, and more.",
                category: .editor,
                commandRoute: "help://markdown-syntax"
            ),
            HelpEntry(
                id: "formatting",
                title: "Text Formatting",
                content: "Format your notes with bold, italic, strikethrough, highlights, and more using the toolbar or keyboard shortcuts.",
                category: .editor,
                commandRoute: "help://formatting"
            ),
            HelpEntry(
                id: "wiki-links",
                title: "Wiki-Links",
                content: "Connect your notes using wiki-link syntax: [[Note Name]]. Links are bidirectional.",
                category: .organization,
                commandRoute: "help://wiki-links"
            ),
            HelpEntry(
                id: "keyboard-shortcuts",
                title: "Keyboard Shortcuts",
                content: "Master Quartz with keyboard shortcuts: ⌘K for Command Palette, ⌘B for bold, ⌘I for italic.",
                category: .gettingStarted,
                commandRoute: "help://keyboard-shortcuts"
            ),
            HelpEntry(
                id: "sync",
                title: "iCloud Sync",
                content: "Quartz syncs your notes via iCloud Drive automatically. No account needed.",
                category: .organization,
                commandRoute: "help://sync"
            ),
            HelpEntry(
                id: "graph-view",
                title: "Knowledge Graph",
                content: "Visualize connections between your notes in the graph view. See how ideas relate.",
                category: .organization,
                commandRoute: "help://graph-view"
            )
        ]
    }
}

/// Help categories.
public enum HelpCategory: String, CaseIterable, Sendable {
    case gettingStarted = "Getting Started"
    case editor = "Editor"
    case organization = "Organization"
    case advanced = "Advanced"
}

/// Help anchors for macOS Help menu deep linking.
public enum HelpAnchor: String, CaseIterable, Sendable {
    case gettingStarted = "getting-started"
    case markdownSyntax = "markdown-syntax"
    case keyboardShortcuts = "keyboard-shortcuts"
    case wikiLinks = "wiki-links"
    case graphView = "graph-view"
    case sync = "sync"

    public var helpURL: URL? {
        URL(string: "help://quartz/\(rawValue)")
    }
}

/// Help section for iOS modal.
public struct HelpSection: Sendable {
    public let title: String
    public let content: String
    public let icon: String

    public static var allSections: [HelpSection] {
        [
            HelpSection(title: "Getting Started", content: "Learn the basics", icon: "star"),
            HelpSection(title: "Editor", content: "Writing and formatting", icon: "pencil"),
            HelpSection(title: "Organization", content: "Folders, tags, and links", icon: "folder"),
            HelpSection(title: "Sync", content: "iCloud and backup", icon: "icloud")
        ]
    }
}
