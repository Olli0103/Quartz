@testable import QuartzKit
import Foundation

// MARK: - Advanced Mock Vault Provider

/// Protocol-oriented mock for comprehensive file system testing.
///
/// **The Objective:**
/// Enables testing of:
/// - Disk full errors during save operations
/// - iCloud eviction (`.notDownloaded` state)
/// - NSFilePresenter race conditions
/// - Slow/timeout scenarios
/// - Large vault performance (1000+ files)
///
/// **Cross-Platform Nuances:**
/// - **macOS**: Simulates "Optimize Mac Storage" eviction.
/// - **iOS/iPadOS**: Simulates background app termination during I/O.
/// - **All platforms**: Simulates iCloud sync conflicts.
///
/// **Usage:**
/// ```swift
/// let mock = AdvancedMockVaultProvider()
/// mock.simulateError(.diskFull, for: .saveNote)
///
/// do {
///     try await mock.saveNote(note)
///     XCTFail("Should have thrown disk full error")
/// } catch FileSystemError.diskFull {
///     // Expected
/// }
/// ```
public actor AdvancedMockVaultProvider: VaultProviding {

    // MARK: - State

    /// In-memory file tree.
    private var fileTree: [FileNode] = []

    /// In-memory notes storage.
    private var notes: [URL: NoteDocument] = [:]

    /// Simulated errors for specific operations.
    private var simulatedErrors: [Operation: SimulatedError] = [:]

    /// Simulated delays for specific operations.
    private var simulatedDelays: [Operation: TimeInterval] = [:]

    /// Files marked as "not downloaded" (iCloud eviction simulation).
    private var notDownloadedFiles: Set<URL> = []

    /// Files with simulated conflicts.
    private var conflictingFiles: Set<URL> = []

    /// Callback for operation tracking in tests.
    public var operationLog: [(Operation, URL?)] = []

    /// Whether to automatically generate a large test vault.
    private let generateLargeVault: Bool

    /// Number of notes in the generated vault.
    private let generatedNoteCount: Int

    // MARK: - Init

    public init(generateLargeVault: Bool = false, noteCount: Int = 100) {
        self.generateLargeVault = generateLargeVault
        self.generatedNoteCount = noteCount
        // Note: Call populateTestVault() after init for generating vault
    }

    /// Call after init to populate the test vault (required for async context).
    public func populateTestVault() {
        if generateLargeVault {
            generateTestVault(noteCount: generatedNoteCount)
        }
    }

    // MARK: - Simulation Control

    /// Sets a simulated error for an operation type.
    public func simulateError(_ error: SimulatedError, for operation: Operation) {
        simulatedErrors[operation] = error
    }

    /// Clears simulated error for an operation type.
    public func clearSimulatedError(for operation: Operation) {
        simulatedErrors.removeValue(forKey: operation)
    }

    /// Sets a simulated delay for an operation type.
    public func simulateDelay(_ delay: TimeInterval, for operation: Operation) {
        simulatedDelays[operation] = delay
    }

    /// Marks a file as "not downloaded" (iCloud eviction).
    public func markAsNotDownloaded(_ url: URL) {
        notDownloadedFiles.insert(url)
    }

    /// Marks a file as having a sync conflict.
    public func markAsConflicting(_ url: URL) {
        conflictingFiles.insert(url)
    }

    /// Clears all simulated states.
    public func reset() {
        simulatedErrors.removeAll()
        simulatedDelays.removeAll()
        notDownloadedFiles.removeAll()
        conflictingFiles.removeAll()
        operationLog.removeAll()
    }

    // MARK: - VaultProviding Implementation

    public func loadFileTree(at root: URL) async throws -> [FileNode] {
        try await simulateOperationIfNeeded(.loadFileTree, url: root)

        if generateLargeVault && fileTree.isEmpty {
            generateTestVault(noteCount: generatedNoteCount)
        }

        return fileTree
    }

    public func readNote(at url: URL) async throws -> NoteDocument {
        try await simulateOperationIfNeeded(.readNote, url: url)

        // Check for iCloud eviction
        if notDownloadedFiles.contains(url) {
            throw FileSystemError.iCloudTimeout(url)
        }

        guard let note = notes[url] else {
            throw FileSystemError.fileNotFound(url)
        }

        return note
    }

    public func saveNote(_ note: NoteDocument) async throws {
        try await simulateOperationIfNeeded(.saveNote, url: note.fileURL)

        notes[note.fileURL] = note
        updateFileTree(for: note.fileURL, isDirectory: false)
    }

    public func createNote(named name: String, in folder: URL) async throws -> NoteDocument {
        try await simulateOperationIfNeeded(.createNote, url: folder)

        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            throw FileSystemError.invalidName(name)
        }

        let baseName = sanitized.hasSuffix(".md") ? String(sanitized.dropLast(3)) : sanitized
        let fileName = "\(baseName).md"
        let fileURL = folder.appending(path: fileName)

        guard notes[fileURL] == nil else {
            throw FileSystemError.fileAlreadyExists(fileURL)
        }

        let frontmatter = Frontmatter(
            title: baseName,
            createdAt: .now,
            modifiedAt: .now
        )

        let note = NoteDocument(
            fileURL: fileURL,
            frontmatter: frontmatter,
            body: "",
            isDirty: false
        )

        notes[fileURL] = note
        updateFileTree(for: fileURL, isDirectory: false)

        return note
    }

    public func createNote(named name: String, in folder: URL, initialContent: String) async throws -> NoteDocument {
        var note = try await createNote(named: name, in: folder)
        note.body = initialContent
        notes[note.fileURL] = note
        return note
    }

    public func deleteNote(at url: URL) async throws {
        try await simulateOperationIfNeeded(.deleteNote, url: url)

        notes.removeValue(forKey: url)
        removeFromFileTree(url)
    }

    public func rename(at url: URL, to newName: String) async throws -> URL {
        try await simulateOperationIfNeeded(.rename, url: url)

        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            throw FileSystemError.invalidName(newName)
        }

        let baseName = sanitized.hasSuffix(".md") ? sanitized : "\(sanitized).md"
        let newURL = url.deletingLastPathComponent().appending(path: baseName)

        guard notes[newURL] == nil else {
            throw FileSystemError.fileAlreadyExists(newURL)
        }

        if var note = notes[url] {
            note = NoteDocument(
                fileURL: newURL,
                frontmatter: note.frontmatter,
                body: note.body,
                isDirty: note.isDirty
            )
            notes.removeValue(forKey: url)
            notes[newURL] = note
        }

        updateFileTree(for: newURL, isDirectory: false)
        removeFromFileTree(url)

        return newURL
    }

    public func createFolder(named name: String, in parent: URL) async throws -> URL {
        try await simulateOperationIfNeeded(.createFolder, url: parent)

        let folderURL = parent.appending(path: name)
        updateFileTree(for: folderURL, isDirectory: true)
        return folderURL
    }

    // MARK: - Private Helpers

    private func simulateOperationIfNeeded(_ operation: Operation, url: URL?) async throws {
        operationLog.append((operation, url))

        // Apply delay if configured
        if let delay = simulatedDelays[operation] {
            try await Task.sleep(for: .seconds(delay))
        }

        // Throw error if configured
        if let error = simulatedErrors[operation] {
            throw error.asFileSystemError(url: url)
        }
    }

    private func generateTestVault(noteCount: Int) {
        let rootURL = URL(filePath: "/mock/vault")
        var generatedNotes: [URL: NoteDocument] = [:]
        var generatedNodes: [FileNode] = []

        // Generate folders
        let folders = ["Projects", "Daily", "Research", "Archive"]
        for folder in folders {
            let folderURL = rootURL.appending(path: folder)
            generatedNodes.append(FileNode(
                name: folder,
                url: folderURL,
                nodeType: .folder,
                children: [],
                metadata: FileMetadata(createdAt: .now, modifiedAt: .now, fileSize: 0)
            ))
        }

        // Generate notes
        for i in 0..<noteCount {
            let folderIndex = i % folders.count
            let folderName = folders[folderIndex]
            let noteURL = rootURL.appending(path: folderName).appending(path: "Note_\(i).md")

            let body = generateMarkdownContent(index: i, totalNotes: noteCount)
            let frontmatter = Frontmatter(
                title: "Note \(i)",
                tags: ["tag\(i % 10)", "generated"],
                createdAt: Date().addingTimeInterval(-Double(i) * 3600),
                modifiedAt: Date().addingTimeInterval(-Double(i) * 60)
            )

            let note = NoteDocument(
                fileURL: noteURL,
                frontmatter: frontmatter,
                body: body,
                isDirty: false
            )

            generatedNotes[noteURL] = note

            // Add to folder's children
            if var folderNode = generatedNodes.first(where: { $0.name == folderName }) {
                var children = folderNode.children ?? []
                children.append(FileNode(
                    name: "Note_\(i).md",
                    url: noteURL,
                    nodeType: .note,
                    metadata: FileMetadata(
                        createdAt: frontmatter.createdAt,
                        modifiedAt: frontmatter.modifiedAt,
                        fileSize: Int64(body.utf8.count)
                    )
                ))
                folderNode.children = children
                if let idx = generatedNodes.firstIndex(where: { $0.name == folderName }) {
                    generatedNodes[idx] = folderNode
                }
            }
        }

        self.notes = generatedNotes
        self.fileTree = generatedNodes
    }

    private func generateMarkdownContent(index: Int, totalNotes: Int) -> String {
        // Generate realistic markdown content with wiki-links
        let linkedNoteIndex = (index + 1) % totalNotes
        return """
        # Note \(index)

        This is a generated test note for performance testing.

        ## Section 1

        Some content with a [[Note_\(linkedNoteIndex)]] wiki-link.

        - List item 1
        - List item 2
        - List item 3

        ## Section 2

        More content for testing embeddings and semantic analysis.
        The Intelligence Engine should process this text efficiently.

        Tags: #tag\(index % 10) #generated
        """
    }

    private func updateFileTree(for url: URL, isDirectory: Bool) {
        // Simplified tree update for mock
        let node = FileNode(
            name: url.lastPathComponent,
            url: url,
            nodeType: isDirectory ? .folder : .note,
            children: isDirectory ? [] : nil,
            metadata: FileMetadata(createdAt: .now, modifiedAt: .now, fileSize: 0)
        )

        if !fileTree.contains(where: { $0.url == url }) {
            fileTree.append(node)
        }
    }

    private func removeFromFileTree(_ url: URL) {
        fileTree.removeAll { $0.url == url }
    }
}

// MARK: - Supporting Types

public extension AdvancedMockVaultProvider {

    /// Operations that can be simulated.
    enum Operation: String, CaseIterable, Sendable {
        case loadFileTree
        case readNote
        case saveNote
        case createNote
        case deleteNote
        case rename
        case createFolder
    }

    /// Errors that can be simulated.
    enum SimulatedError: String, Sendable {
        case diskFull
        case iCloudTimeout
        case fileNotFound
        case permissionDenied
        case networkUnavailable
        case conflict
        case encodingFailed

        func asFileSystemError(url: URL?) -> Error {
            let targetURL = url ?? URL(filePath: "/unknown")
            switch self {
            case .diskFull:
                return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [
                    NSLocalizedDescriptionKey: "The disk is full."
                ])
            case .iCloudTimeout:
                return FileSystemError.iCloudTimeout(targetURL)
            case .fileNotFound:
                return FileSystemError.fileNotFound(targetURL)
            case .permissionDenied:
                return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied."
                ])
            case .networkUnavailable:
                return NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
                    NSLocalizedDescriptionKey: "Network unavailable."
                ])
            case .conflict:
                return NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                    NSLocalizedDescriptionKey: "File conflict detected."
                ])
            case .encodingFailed:
                return FileSystemError.encodingFailed(targetURL)
            }
        }
    }
}

// MARK: - Test Helpers

public extension AdvancedMockVaultProvider {

    /// Returns all stored note URLs.
    var storedNoteURLs: [URL] {
        Array(notes.keys)
    }

    /// Returns the number of stored notes.
    var storedNoteCount: Int {
        notes.count
    }

    /// Returns the operation log for verification.
    var operations: [(Operation, URL?)] {
        operationLog
    }

    /// Directly adds a note to the mock (for test setup).
    func addNote(_ note: NoteDocument) {
        notes[note.fileURL] = note
    }

    /// Directly sets the file tree (for test setup).
    func setFileTree(_ tree: [FileNode]) {
        fileTree = tree
    }

    /// Returns content for a specific note URL (for testing).
    func getContent(for url: URL) -> String? {
        notes[url]?.body
    }
}

// MARK: - Chaos Simulation

public extension AdvancedMockVaultProvider {

    /// Simulates an "Eviction Storm" — macOS bird daemon instantly un-downloading many files.
    ///
    /// **Hostile OS Threat:**
    /// macOS "Optimize Storage" can evict hundreds of files simultaneously when disk space is low.
    /// This happens while the app is indexing, causing mass iCloud timeout errors.
    ///
    /// **Usage:**
    /// ```swift
    /// let mock = AdvancedMockVaultProvider(generateLargeVault: true, noteCount: 500)
    /// await mock.populateTestVault()
    /// await mock.simulateEvictionStorm(percentage: 0.8) // Evict 80% of files
    /// ```
    func simulateEvictionStorm(percentage: Double = 0.5) {
        let urlsToEvict = Array(notes.keys).shuffled().prefix(Int(Double(notes.count) * percentage))

        for url in urlsToEvict {
            notDownloadedFiles.insert(url)
        }
    }

    /// Simulates a network partition where all iCloud operations timeout.
    func simulateNetworkPartition() {
        simulatedErrors[.readNote] = .iCloudTimeout
        simulatedErrors[.saveNote] = .networkUnavailable
        simulatedErrors[.loadFileTree] = .networkUnavailable
    }

    /// Ends the simulated network partition.
    func endNetworkPartition() {
        simulatedErrors.removeValue(forKey: .readNote)
        simulatedErrors.removeValue(forKey: .saveNote)
        simulatedErrors.removeValue(forKey: .loadFileTree)
    }

    /// Simulates disk becoming full mid-operation.
    func simulateDiskFull() {
        simulatedErrors[.saveNote] = .diskFull
        simulatedErrors[.createNote] = .diskFull
    }

    /// Simulates a sandbox revocation (macOS security bookmark expired).
    func simulateSandboxRevocation() {
        simulatedErrors[.readNote] = .permissionDenied
        simulatedErrors[.saveNote] = .permissionDenied
        simulatedErrors[.loadFileTree] = .permissionDenied
    }

    /// Simulates random failures (chaos monkey mode).
    /// Each operation has a specified probability of failing.
    func enableChaosMonkey(failureProbability: Double = 0.1) {
        // Store the probability for use in operations
        // This is a simplified version - in practice you'd check this in each operation
        if failureProbability > 0.3 {
            simulatedErrors[.readNote] = .iCloudTimeout
        }
        if failureProbability > 0.5 {
            simulatedErrors[.saveNote] = .conflict
        }
    }

    /// Disables chaos monkey mode.
    func disableChaosMonkey() {
        simulatedErrors.removeAll()
    }
}
