import Foundation
import Testing
@testable import QuartzKit

@Suite("Knowledge graph scale and background integrity")
struct KnowledgeGraphScaleIntegrityTests {

    @Test("Stale semantic similarity work cannot overwrite a newer request for the same note")
    func staleSemanticAnalysisIsSuperseded() async {
        let vaultRoot = URL(fileURLWithPath: "/vault")
        let noteA = vaultRoot.appending(path: "Alpha.md")
        let noteB = vaultRoot.appending(path: "Beta.md")
        let noteC = vaultRoot.appending(path: "Gamma.md")
        let idB = VectorEmbeddingService.stableNoteID(for: noteB, vaultRoot: vaultRoot)
        let idC = VectorEmbeddingService.stableNoteID(for: noteC, vaultRoot: vaultRoot)

        let searchDriver = SuspendedSemanticSearchDriver(
            firstResult: [idB],
            laterResult: [idC]
        )
        let edgeStore = GraphEdgeStore()
        let service = SemanticLinkService(
            embeddingService: VectorEmbeddingService(vaultURL: vaultRoot),
            edgeStore: edgeStore,
            vaultRootURL: vaultRoot,
            debounceInterval: .milliseconds(1),
            similaritySearchOverride: { noteID, limit, threshold in
                await searchDriver.search(noteID: noteID, limit: limit, threshold: threshold)
            },
            noteURLResolverOverride: { ids in
                ids.compactMap {
                    switch $0 {
                    case idB: noteB
                    case idC: noteC
                    default: nil
                    }
                }
            }
        )

        await service.scheduleAnalysis(for: noteA)
        #expect(await waitUntil { await searchDriver.callCount == 1 })

        await service.scheduleAnalysis(for: noteA)
        #expect(await waitUntil { (await edgeStore.semanticRelations(for: noteA)) == [noteC] })

        await searchDriver.resumeFirstSearch()

        #expect(await waitUntil { (await edgeStore.semanticRelations(for: noteA)) == [noteC] })
    }

    @Test("Stale AI concept extraction cannot overwrite a newer request for the same note")
    func staleConceptExtractionIsSuperseded() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "kg7-concepts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let noteURL = rootURL.appending(path: "Alpha.md")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try String(repeating: "This is a sufficiently long note for extraction. ", count: 4)
            .write(to: noteURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let extractionDriver = SuspendedConceptExtractionDriver(
            firstResult: ["stale-concept"],
            laterResult: ["fresh-concept"]
        )
        let edgeStore = GraphEdgeStore()
        let service = KnowledgeExtractionService(
            edgeStore: edgeStore,
            vaultRootURL: rootURL,
            debounceInterval: .milliseconds(1),
            scanInterval: .milliseconds(1),
            extractionOverride: { input in
                await extractionDriver.extractConcepts(from: input)
            }
        )

        await service.scheduleExtraction(for: noteURL)
        #expect(await waitUntil { await extractionDriver.callCount == 1 })

        await service.scheduleExtraction(for: noteURL)
        #expect(await waitUntil { (await edgeStore.concepts(for: noteURL)) == ["fresh-concept"] })

        await extractionDriver.resumeFirstExtraction()

        #expect(await waitUntil { (await edgeStore.concepts(for: noteURL)) == ["fresh-concept"] })
    }

    @Test("AI concept persistence survives note relocation and deletion")
    func persistedConceptStateTracksRelocationAndDeletion() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "kg7-concept-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        let notesDirectory = rootURL.appending(path: "Notes", directoryHint: .isDirectory)
        let movedDirectory = rootURL.appending(path: "Moved", directoryHint: .isDirectory)
        let originalURL = notesDirectory.appending(path: "Alpha.md")
        let relocatedURL = movedDirectory.appending(path: "Alpha.md")

        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appending(path: ".quartz"), withIntermediateDirectories: true)
        try String(repeating: "Swift architecture knowledge graph indexing. ", count: 4)
            .write(to: originalURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let edgeStore = GraphEdgeStore()
        let service = KnowledgeExtractionService(
            edgeStore: edgeStore,
            vaultRootURL: rootURL,
            debounceInterval: .milliseconds(1),
            scanInterval: .milliseconds(1),
            extractionOverride: { _ in ["swift", "architecture"] }
        )

        await service.scheduleExtraction(for: originalURL)
        #expect(await waitUntil { Set(await edgeStore.concepts(for: originalURL)) == Set(["architecture", "swift"]) })

        try FileManager.default.moveItem(at: originalURL, to: relocatedURL)
        await service.handleNoteRelocation(from: originalURL, to: relocatedURL)

        let relocatedState = try loadAIState(from: rootURL)
        #expect(relocatedState.processedTimestamps["Notes/Alpha.md"] == nil)
        #expect(relocatedState.processedTimestamps["Moved/Alpha.md"] != nil)
        #expect(relocatedState.conceptEdges["swift"] == Set(["Moved/Alpha.md"]))
        #expect(relocatedState.conceptEdges["architecture"] == Set(["Moved/Alpha.md"]))
        #expect(await edgeStore.concepts(for: originalURL).isEmpty)
        #expect(Set(await edgeStore.concepts(for: relocatedURL)) == Set(["architecture", "swift"]))

        try FileManager.default.removeItem(at: relocatedURL)
        await service.handleNoteDeletion(at: relocatedURL)

        let deletedState = try loadAIState(from: rootURL)
        #expect(deletedState.processedTimestamps["Moved/Alpha.md"] == nil)
        #expect(deletedState.conceptEdges["swift"] == nil)
        #expect(deletedState.conceptEdges["architecture"] == nil)
        #expect(await edgeStore.concepts(for: relocatedURL).isEmpty)
    }

    @MainActor
    @Test("Vault load and switch hydrate semantic similarity and AI concepts deterministically")
    func vaultLoadAndSwitchRestoreSemanticAndConceptStateDeterministically() async throws {
        let firstFixture = try RelationshipFixture.make(
            name: "kg7-vault-a",
            conceptEdges: ["swift": ["Source.md"]]
        )
        let secondFixture = try RelationshipFixture.make(
            name: "kg7-vault-b",
            conceptEdges: [:]
        )
        defer {
            firstFixture.teardown()
            secondFixture.teardown()
        }

        let viewModel = makeContentViewModel()
        viewModel.loadVault(firstFixture.config)

        let firstWarm = try await waitUntilOnMainActor("first vault reaches indexWarm") {
            viewModel.startupCoordinator.currentPhase >= .indexWarm
        }
        #expect(firstWarm)

        let firstConceptRestore = try await waitUntilOnMainActor("first vault restores concept state") {
            let concepts = await viewModel.graphEdgeStore.concepts(for: firstFixture.sourceURL)
            return concepts == ["swift"]
        }
        #expect(firstConceptRestore)

        let firstCache = GraphCache(vaultRoot: firstFixture.rootURL)
        await viewModel.graphEdgeStore.updateSemanticConnections(
            for: firstFixture.sourceURL,
            related: [firstFixture.targetURL]
        )
        NotificationCenter.default.post(
            name: .quartzRelatedNotesUpdated,
            object: firstFixture.sourceURL,
            userInfo: ["vaultRootURL": firstFixture.rootURL]
        )

        let semanticSnapshotPersisted = try await waitUntilOnMainActor("first vault persists semantic snapshot") {
            guard let tree = viewModel.sidebarViewModel?.fileTree else { return false }
            let runtimeFingerprint = firstCache.computeFingerprint(for: collectNoteURLs(from: tree))
            let snapshot = firstCache.loadSemanticRelationshipSnapshotIfValid(fingerprint: runtimeFingerprint)
            return snapshot?.relations.first?.targetURLs == [CanonicalNoteIdentity.canonicalFileURL(for: firstFixture.targetURL)]
        }
        #expect(semanticSnapshotPersisted)

        let reloadedViewModel = makeContentViewModel()
        reloadedViewModel.loadVault(firstFixture.config)

        let reloadedWarm = try await waitUntilOnMainActor("reloaded vault reaches indexWarm") {
            reloadedViewModel.startupCoordinator.currentPhase >= .indexWarm
        }
        #expect(reloadedWarm)

        let firstSemanticRestore = try await waitUntilOnMainActor("reloaded vault restores semantic state") {
            let semanticRelations = await reloadedViewModel.graphEdgeStore.semanticRelations(for: firstFixture.sourceURL)
            return semanticRelations == [firstFixture.targetURL]
        }
        #expect(firstSemanticRestore)

        let reloadedConceptRestore = try await waitUntilOnMainActor("reloaded vault restores concept state") {
            let concepts = await reloadedViewModel.graphEdgeStore.concepts(for: firstFixture.sourceURL)
            return concepts == ["swift"]
        }
        #expect(reloadedConceptRestore)

        reloadedViewModel.loadVault(secondFixture.config)

        let secondWarm = try await waitUntilOnMainActor("second vault reaches indexWarm") {
            reloadedViewModel.startupCoordinator.currentPhase >= .indexWarm
        }
        #expect(secondWarm)

        let switchCleared = try await waitUntilOnMainActor("vault switch clears stale semantic and concept state") {
            let firstSemanticRelations = await reloadedViewModel.graphEdgeStore.semanticRelations(for: firstFixture.sourceURL)
            let firstConcepts = await reloadedViewModel.graphEdgeStore.concepts(for: firstFixture.sourceURL)
            let secondSemanticRelations = await reloadedViewModel.graphEdgeStore.semanticRelations(for: secondFixture.sourceURL)
            let secondConcepts = await reloadedViewModel.graphEdgeStore.concepts(for: secondFixture.sourceURL)
            return firstSemanticRelations.isEmpty
                && firstConcepts.isEmpty
                && secondSemanticRelations.isEmpty
                && secondConcepts.isEmpty
        }
        #expect(switchCleared)
    }

    @MainActor
    private func makeContentViewModel() -> ContentViewModel {
        let parser = FrontmatterParser()
        let provider = FileSystemVaultProvider(frontmatterParser: parser)
        ServiceContainer.shared.reset()
        ServiceContainer.shared.bootstrap(vaultProvider: provider, frontmatterParser: parser)
        return ContentViewModel(appState: AppState())
    }

    private func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        for node in nodes {
            if node.isNote {
                urls.append(node.url)
            }
            if let children = node.children {
                urls.append(contentsOf: collectNoteURLs(from: children))
            }
        }
        return urls
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return await condition()
    }

    private func loadAIState(from rootURL: URL) throws -> AIIndexState {
        let data = try Data(contentsOf: rootURL.appending(path: ".quartz").appending(path: "ai_index.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AIIndexState.self, from: data)
    }

    @MainActor
    private func waitUntilOnMainActor(
        _ description: String,
        timeout: Duration = .seconds(8),
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () async -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return await condition()
    }
}

private actor SuspendedSemanticSearchDriver {
    private let firstResult: [UUID]
    private let laterResult: [UUID]
    private var continuation: CheckedContinuation<[UUID], Never>?
    private(set) var callCount = 0

    init(firstResult: [UUID], laterResult: [UUID]) {
        self.firstResult = firstResult
        self.laterResult = laterResult
    }

    func search(noteID: UUID, limit: Int, threshold: Float) async -> [UUID] {
        callCount += 1
        if callCount == 1 {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return laterResult
    }

    func resumeFirstSearch() {
        continuation?.resume(returning: firstResult)
        continuation = nil
    }
}

private actor SuspendedConceptExtractionDriver {
    private let firstResult: [String]
    private let laterResult: [String]
    private var continuation: CheckedContinuation<[String], Never>?
    private(set) var callCount = 0

    init(firstResult: [String], laterResult: [String]) {
        self.firstResult = firstResult
        self.laterResult = laterResult
    }

    func extractConcepts(from input: String) async -> [String] {
        callCount += 1
        if callCount == 1 {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return laterResult
    }

    func resumeFirstExtraction() {
        continuation?.resume(returning: firstResult)
        continuation = nil
    }
}

private struct RelationshipFixture {
    let rootURL: URL
    let sourceURL: URL
    let targetURL: URL
    let config: VaultConfig

    static func make(
        name: String,
        conceptEdges: [String: Set<String>]
    ) throws -> RelationshipFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "Quartz-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let quartzDirectory = rootURL.appending(path: ".quartz", directoryHint: .isDirectory)
        let sourceURL = rootURL.appending(path: "Source.md")
        let targetURL = rootURL.appending(path: "Target.md")

        try FileManager.default.createDirectory(at: quartzDirectory, withIntermediateDirectories: true)
        try "See [[Target]] and discuss Swift architecture in detail with longer implementation notes for deterministic concept restore."
            .write(to: sourceURL, atomically: true, encoding: .utf8)
        try "# Target\nSemantic content".write(to: targetURL, atomically: true, encoding: .utf8)

        if !conceptEdges.isEmpty {
            var aiState = AIIndexState()
            aiState.conceptEdges = conceptEdges
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(aiState)
            try data.write(to: quartzDirectory.appending(path: "ai_index.json"), options: .atomic)
        }

        return RelationshipFixture(
            rootURL: rootURL,
            sourceURL: sourceURL,
            targetURL: targetURL,
            config: VaultConfig(name: name, rootURL: rootURL)
        )
    }

    @MainActor
    func teardown() {
        try? FileManager.default.removeItem(at: rootURL)
        ServiceContainer.shared.reset()
    }

    static func persistedConceptState(at rootURL: URL) -> AIIndexState {
        let url = rootURL.appending(path: ".quartz").appending(path: "ai_index.json")
        guard let data = try? Data(contentsOf: url) else { return AIIndexState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AIIndexState.self, from: data)) ?? AIIndexState()
    }
}
