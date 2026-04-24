import SwiftUI
import OSLog

/// Coordinates vault loading, note opening, and command routing.
///
/// Extracts the business logic from `ContentView` so that the view
/// is only responsible for layout and presentation.
@Observable
@MainActor
public final class ContentViewModel {
    nonisolated private static let embeddingCheckpointInterval = 8
    nonisolated private static let indexingTelemetryLogger = Logger(subsystem: "com.quartz", category: "IndexingTelemetry")

    public var sidebarViewModel: SidebarViewModel?
    /// Jitter-free editor session. Used by WorkspaceView's detail column.
    /// This is the SOLE editor state machine — no legacy fallback.
    public var editorSession: EditorSession?
    /// Document-context chat session — reads live text from EditorSession at send-time.
    public var documentChatSession: DocumentChatSession?
    /// Inspector store — shared across note switches, persists visibility state.
    public let inspectorStore = InspectorStore()
    public var searchIndex: VaultSearchIndex?
    /// Core Spotlight indexer (system search); separate from in-app ``searchIndex``.
    private var spotlightIndexer: QuartzSpotlightIndexer?
    public var embeddingService: VectorEmbeddingService?
    /// Preview cache for the middle column note list.
    public var previewRepository: NotePreviewRepository?
    /// Preview indexer — reads 8KB prefix of each note for title/snippet/tags.
    public var previewIndexer: NotePreviewIndexer?
    public var cloudSyncStatus: CloudSyncStatus = .notApplicable
    /// URLs of files with unresolved iCloud sync conflicts. Used to present ConflictResolverView.
    public var conflictingFileURLs: [URL] = []
    public var indexingProgress: (current: Int, total: Int)?
    /// VaultProvider for injection into child views (avoids ServiceContainer in render path).
    public var vaultProvider: (any VaultProviding)?

    // MARK: - Backup State

    /// Vault backup service — manages export, auto-backup, and restore.
    public let backupService = VaultBackupService()
    /// Available backups for the current vault.
    public var availableBackups: [BackupEntry] = []
    /// Whether a backup operation is currently running.
    public var isBackupInProgress: Bool = false
    /// Backup progress (0.0–1.0).
    public var backupProgress: Double = 0
    /// Last sync timestamp (updated when cloudSyncStatus becomes .current).
    public var lastSyncTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: "quartzLastSyncTimestamp") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "quartzLastSyncTimestamp") }
    }

    private let appState: AppState
    private var cloudSyncService: CloudSyncService?
    private var syncMonitoringTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var vaultHydrationTask: Task<Void, Never>?
    private var restorationPhaseTask: Task<Void, Never>?
    private var relationshipLifecycleTask: Task<Void, Never>?
    private var explicitRelationshipRepairTask: Task<Void, Never>?
    private var semanticSnapshotPersistTask: Task<Void, Never>?
    private var currentVaultRootURL: URL?
    private var relationshipRuntimeGeneration: UInt64 = 0
    private var indexingRunID: UInt64 = 0
    /// Debounced task for re-indexing embeddings after note saves.
    private var embeddingReindexTask: Task<Void, Never>?
    /// Observer token for `.quartzNoteSaved` notifications (embedding reindex).
    private var noteSavedObserver: Any?
    /// Observer tokens for note lifecycle notifications (spotlight, preview, search).
    private var noteLifecycleObservers: [Any] = []
    /// Whether the current vault has completed its authoritative explicit relationship hydration.
    private var hasHydratedExplicitRelationships = false
    /// Whether the pending repair task must refresh the sidebar tree before rebuilding.
    private var explicitRelationshipRepairNeedsSidebarRefresh = false
    /// Guards against file-tree callbacks re-scheduling the repair task while KG3
    /// is already performing the authoritative refresh/rebuild sequence.
    private var isPerformingExplicitRelationshipRepair = false
    /// Background note-to-note related-note similarity engine.
    public var semanticLinkService: SemanticLinkService?
    /// Background AI concept extraction engine.
    public var knowledgeExtractionService: KnowledgeExtractionService?
    /// Unified Intelligence Engine coordinator — bridges file events to all AI services.
    public var intelligenceCoordinator: IntelligenceEngineCoordinator?
    /// Shared graph edge store for wiki-link and semantic edges.
    public let graphEdgeStore = GraphEdgeStore()
    /// Startup phase coordinator — deterministic handshake replacing timing heuristics.
    public let startupCoordinator = StartupCoordinator()

    public init(appState: AppState) {
        self.appState = appState
    }

    nonisolated private static func elapsedMilliseconds(since startTime: UInt64) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000
    }

    nonisolated private static func logIndexingStage(
        _ stage: String,
        startedAt startTime: UInt64,
        noteCount: Int? = nil,
        detail: String? = nil
    ) {
        let elapsed = elapsedMilliseconds(since: startTime)
        let diagnosticsMessage: String
        switch (noteCount, detail) {
        case let (.some(noteCount), .some(detail)):
            diagnosticsMessage = "\(stage) finished in \(elapsed) ms (\(noteCount) notes, \(detail))"
            indexingTelemetryLogger.info(
                "\(stage, privacy: .public) finished in \(elapsed) ms (\(noteCount) notes, \(detail, privacy: .public))"
            )
        case let (.some(noteCount), .none):
            diagnosticsMessage = "\(stage) finished in \(elapsed) ms (\(noteCount) notes)"
            indexingTelemetryLogger.info(
                "\(stage, privacy: .public) finished in \(elapsed) ms (\(noteCount) notes)"
            )
        case let (.none, .some(detail)):
            diagnosticsMessage = "\(stage) finished in \(elapsed) ms (\(detail))"
            indexingTelemetryLogger.info(
                "\(stage, privacy: .public) finished in \(elapsed) ms (\(detail, privacy: .public))"
            )
        case (.none, .none):
            diagnosticsMessage = "\(stage) finished in \(elapsed) ms"
            indexingTelemetryLogger.info("\(stage, privacy: .public) finished in \(elapsed) ms")
        }
        QuartzDiagnostics.info(category: "IndexingTelemetry", diagnosticsMessage)
    }

    nonisolated private static func logIndexingFailure(
        _ operation: String,
        error: Error,
        noteURL: URL? = nil
    ) {
        let noteDescription = noteURL.map { " for \($0.lastPathComponent)" } ?? ""
        let message = "\(operation)\(noteDescription) failed: \(error.localizedDescription)"
        indexingTelemetryLogger.error("\(message, privacy: .public)")
        QuartzDiagnostics.error(category: "IndexingTelemetry", message)
    }

    // MARK: - Vault Loading

    /// Loads a vault: creates sidebar VM, search index, builds the file tree, and indexes notes.
    /// Wires the `NoteListStore` with preview data after indexing completes.
    public func loadVault(_ vault: VaultConfig, noteListStore: NoteListStore? = nil) {
        KnowledgeAnalysisSettings.migrateLegacyDefaultsIfNeeded()
        let previousSemanticLinkService = semanticLinkService
        let previousKnowledgeExtractionService = knowledgeExtractionService
        let previousIntelligenceCoordinator = intelligenceCoordinator

        editorSession?.closeNote()
        stopCloudSync()
        indexingTask?.cancel()
        indexingTask = nil
        vaultHydrationTask?.cancel()
        vaultHydrationTask = nil
        restorationPhaseTask?.cancel()
        restorationPhaseTask = nil
        relationshipLifecycleTask?.cancel()
        relationshipLifecycleTask = nil
        explicitRelationshipRepairTask?.cancel()
        explicitRelationshipRepairTask = nil
        semanticSnapshotPersistTask?.cancel()
        semanticSnapshotPersistTask = nil
        embeddingReindexTask?.cancel()
        embeddingReindexTask = nil
        hasHydratedExplicitRelationships = false
        explicitRelationshipRepairNeedsSidebarRefresh = false
        inspectorStore.aiScanProgress = nil
        startupCoordinator.reset()
        relationshipRuntimeGeneration &+= 1
        let loadGeneration = relationshipRuntimeGeneration

        currentVaultRootURL = vault.rootURL

        // Phase: vault resolved (bookmark acquired, directory accessible)
        startupCoordinator.advance(to: StartupCoordinator.StartupPhase.vaultResolved)

        let provider = ServiceContainer.shared.resolveVaultProvider()
        vaultProvider = provider
        let viewModel = SidebarViewModel(vaultProvider: provider)
        viewModel.onFileTreeDidChange = { [weak self] newTree in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL) else { return }
                await self.syncRelationshipCatalog(to: newTree)
                if self.hasHydratedExplicitRelationships, !self.isPerformingExplicitRelationshipRepair {
                    self.scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: false)
                }
            }
        }
        sidebarViewModel = viewModel

        let index = VaultSearchIndex(vaultProvider: provider)
        searchIndex = index

        spotlightIndexer = QuartzSpotlightIndexer(vaultProvider: provider)

        let embedding = VectorEmbeddingService(vaultURL: vault.rootURL)
        embeddingService = embedding

        // Initialize background related-note similarity service.
        // KG5 keeps this separate from AI concept extraction and from explicit links.
        semanticLinkService = SemanticLinkService(
            embeddingService: embedding,
            edgeStore: graphEdgeStore,
            vaultRootURL: vault.rootURL
        )

        // Initialize background AI concept extraction engine
        knowledgeExtractionService = KnowledgeExtractionService(
            edgeStore: graphEdgeStore,
            vaultRootURL: vault.rootURL
        )

        // Initialize Intelligence Engine coordinator — unified event routing
        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embedding,
            semanticService: semanticLinkService,
            extractionService: knowledgeExtractionService,
            vaultRootURL: vault.rootURL
        )
        intelligenceCoordinator = coordinator

        let frontmatterParser = ServiceContainer.shared.resolveFrontmatterParser()
        let previewRepo = NotePreviewRepository(vaultRoot: vault.rootURL)
        previewRepository = previewRepo
        let previewIdx = NotePreviewIndexer(
            vaultRoot: vault.rootURL,
            repository: previewRepo,
            frontmatterParser: frontmatterParser
        )
        previewIndexer = previewIdx

        // Create EditorSession ONCE per vault — reused across all note switches.
        // This prevents view destruction/flashing when switching notes.
        let container2 = ServiceContainer.shared
        let session = EditorSession(
            vaultProvider: container2.resolveVaultProvider(),
            frontmatterParser: container2.resolveFrontmatterParser(),
            inspectorStore: inspectorStore
        )
        session.vaultRootURL = vault.rootURL
        session.graphEdgeStore = graphEdgeStore
        editorSession = session
        startRelationshipLifecycleObserver(for: vault.rootURL)

        // Phase: editor mounted
        startupCoordinator.advance(to: StartupCoordinator.StartupPhase.editorMounted)

        // Create DocumentChatSession ONCE per vault — reuses the same EditorSession.
        documentChatSession = DocumentChatSession(editorSession: session)

        vaultHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await previousIntelligenceCoordinator?.stopObserving()
            await previousSemanticLinkService?.invalidatePendingWork()
            await previousKnowledgeExtractionService?.invalidateBackgroundWork()

            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            await coordinator.startObserving()
            await self.graphEdgeStore.resetAllState()
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            // Load preview cache from disk first (instant middle column population)
            let previewCacheLoadStart = DispatchTime.now().uptimeNanoseconds
            await previewRepo.loadCache()
            let cachedPreviewCount = await previewRepo.count
            Self.logIndexingStage(
                "preview cache load",
                startedAt: previewCacheLoadStart,
                noteCount: cachedPreviewCount,
                detail: "cached previews"
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            // Wire NoteListStore with cached data immediately (before full reindex)
            if let noteListStore {
                noteListStore.configure(repository: previewRepo, vaultRoot: vault.rootURL)
                await noteListStore.loadItems(for: .allNotes)
            }
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            let treeLoadStart = DispatchTime.now().uptimeNanoseconds
            await viewModel.loadTree(at: vault.rootURL)
            let treeNoteCount = Self.collectNoteURLs(from: viewModel.fileTree).count
            Self.logIndexingStage("vault tree load", startedAt: treeLoadStart, noteCount: treeNoteCount)
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }
            await self.syncRelationshipCatalog(to: viewModel.fileTree)
            // Run preview indexer alongside other indexers — it's the fastest (8KB reads)
            let previewReindexStart = DispatchTime.now().uptimeNanoseconds
            await previewIdx.indexAll(from: viewModel.fileTree)
            let refreshedPreviewCount = await previewRepo.count
            Self.logIndexingStage(
                "preview cache rebuild",
                startedAt: previewReindexStart,
                noteCount: treeNoteCount,
                detail: "\(refreshedPreviewCount) cached previews"
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            // Refresh note list after full reindex completes (picks up new/changed notes)
            if let noteListStore {
                await noteListStore.refresh()
            }
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            let searchIndexStart = DispatchTime.now().uptimeNanoseconds
            await index.buildIndex(fromPreloadedTree: viewModel.fileTree, at: vault.rootURL)
            let searchEntryCount = await index.entryCount
            let searchBuildSource = await index.latestBuildSource?.rawValue ?? "unknown"
            Self.logIndexingStage(
                "search index ready",
                startedAt: searchIndexStart,
                noteCount: searchEntryCount,
                detail: searchBuildSource
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            // Hydrate authoritative explicit relationships from cache when valid.
            // KG4 keeps persisted explicit relationship ownership with the same
            // runtime owner that powers outgoing links, backlinks, and exclusions.
            let noteURLs = Self.collectNoteURLs(from: viewModel.fileTree)
            let graphCache = GraphCache(vaultRoot: vault.rootURL)
            let explicitFingerprint = graphCache.computeFingerprint(for: noteURLs)
            let explicitRelationshipStart = DispatchTime.now().uptimeNanoseconds
            if let snapshot = graphCache.loadExplicitRelationshipSnapshotIfValid(
                fingerprint: explicitFingerprint
            ) {
                let affectedTargets = await self.graphEdgeStore.loadExplicitRelationshipSnapshot(snapshot)
                NotificationCenter.default.post(
                    name: .quartzReferenceGraphDidChange,
                    object: nil,
                    userInfo: ["targetURLs": Array(affectedTargets)]
                )
            } else {
                await self.rebuildExplicitRelationshipState(from: viewModel.fileTree)
            }
            Self.logIndexingStage(
                "explicit relationship hydration",
                startedAt: explicitRelationshipStart,
                noteCount: noteURLs.count
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            let semanticRelationshipStart = DispatchTime.now().uptimeNanoseconds
            let semanticSnapshot = graphCache.loadSemanticRelationshipSnapshotIfValid(
                fingerprint: explicitFingerprint
            )
            if let semanticSnapshot {
                await self.graphEdgeStore.loadSemanticRelationshipSnapshot(semanticSnapshot)
                NotificationCenter.default.post(
                    name: .quartzRelatedNotesUpdated,
                    object: nil,
                    userInfo: ["vaultRootURL": vault.rootURL]
                )
            }
            Self.logIndexingStage(
                "semantic relationship hydration",
                startedAt: semanticRelationshipStart,
                noteCount: noteURLs.count,
                detail: semanticSnapshot == nil ? "no persisted snapshot" : "persisted snapshot restored"
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }

            let conceptRestoreStart = DispatchTime.now().uptimeNanoseconds
            await self.knowledgeExtractionService?.restorePersistedConcepts()
            Self.logIndexingStage("ai concept restore", startedAt: conceptRestoreStart, noteCount: noteURLs.count)
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }
            self.hasHydratedExplicitRelationships = true

            // Phase: index warm (search + graph loaded)
            self.startupCoordinator.advance(to: StartupCoordinator.StartupPhase.indexWarm)

            if let root = self.currentVaultRootURL {
                let spotlightIndexStart = DispatchTime.now().uptimeNanoseconds
                await spotlightIndexer?.removeAllInDomain()
                await spotlightIndexer?.indexAllNotes(
                    urls: Self.collectNoteURLs(from: viewModel.fileTree),
                    vaultRoot: root
                )
                Self.logIndexingStage("spotlight reindex", startedAt: spotlightIndexStart, noteCount: noteURLs.count)
            }
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }
            let embeddingLoadStart = DispatchTime.now().uptimeNanoseconds
            do {
                try await embedding.loadIndex()
            } catch {
                Self.logIndexingFailure("embedding index load", error: error)
            }
            let loadedEmbeddingEntries = await embedding.entryCount
            Self.logIndexingStage(
                "embedding index load",
                startedAt: embeddingLoadStart,
                detail: "\(loadedEmbeddingEntries) chunks"
            )
            guard self.isCurrentRelationshipGeneration(loadGeneration, vaultRoot: vault.rootURL),
                  !Task.isCancelled else { return }
            self.indexAllNotes(
                in: viewModel.fileTree,
                vaultRoot: vault.rootURL,
                embedding: embedding,
                generation: loadGeneration
            )

            // Start proactive AI concept extraction for the entire vault (rate-limited, low priority)
            await knowledgeExtractionService?.startVaultScan()
            Self.indexingTelemetryLogger.info("AI concept vault scan scheduled for \(noteURLs.count) notes")
            QuartzDiagnostics.info(
                category: "IndexingTelemetry",
                "AI concept vault scan scheduled for \(noteURLs.count) notes"
            )
        }

        let iCloudSyncEnabled = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool) ?? true
        if Self.isICloudDriveURL(vault.rootURL) {
            // Vault is in iCloud — always monitor sync status
            startCloudSync(for: vault.rootURL)
        } else if iCloudSyncEnabled && CloudSyncService.isAvailable {
            // Local vault with sync enabled — user may want to migrate
            cloudSyncStatus = .notApplicable
        }

        // Observe note saves for debounced embedding re-indexing (5s after last save)
        startEmbeddingReindexObserver()
        startNoteLifecycleObservers()

        // Auto-backup check (runs in background if enabled)
        scheduleAutoBackupIfNeeded(vaultRoot: vault.rootURL)

        // Load list of available backups
        refreshAvailableBackups(vaultRoot: vault.rootURL)

        // Check iCloud availability (resolves container URL on background thread)
        checkICloudAvailability()
    }

    /// Listens for `.quartzNoteSaved` and re-indexes the saved note's embeddings
    /// after a 5-second debounce. This keeps the vector index fresh without
    /// blocking the editor on every keystroke.
    private func startEmbeddingReindexObserver() {
        noteSavedObserver.map { NotificationCenter.default.removeObserver($0) }
        noteSavedObserver = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.scheduleEmbeddingReindex(for: url)
            }
        }
    }

    /// Debounced embedding reindex — waits 5 seconds after the last save.
    private func scheduleEmbeddingReindex(for url: URL) {
        embeddingReindexTask?.cancel()
        embeddingReindexTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            updateEmbeddingForNote(at: url)
        }
    }

    /// Subscribes to note lifecycle notifications for spotlight, preview, and search index updates.
    /// **Per CODEX.md F1:** Extracted from ContentView's onReceive handlers.
    private func startNoteLifecycleObservers() {
        // Clear any existing observers
        for observer in noteLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        noteLifecycleObservers.removeAll()

        // .quartzNoteSaved — update spotlight, preview, and search index
        let savedObserver = NotificationCenter.default.addObserver(
            forName: .quartzNoteSaved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.spotlightIndexNote(at: url)
                self.updatePreviewForNote(at: url)
                self.updateSearchIndex(for: url)
            }
        }
        noteLifecycleObservers.append(savedObserver)

        // .quartzRelatedNotesUpdated — persist the canonical semantic similarity snapshot
        let relatedNotesObserver = NotificationCenter.default.addObserver(
            forName: .quartzRelatedNotesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let updatedVaultRoot = notification.userInfo?["vaultRootURL"] as? URL
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.notificationBelongsToCurrentVault(updatedVaultRoot),
                      let tree = self.sidebarViewModel?.fileTree else { return }
                self.scheduleSemanticSnapshotPersistence(from: tree)
            }
        }
        noteLifecycleObservers.append(relatedNotesObserver)

        // .quartzSpotlightNotesRemoved — remove spotlight, preview, and search entries
        let removedObserver = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNotesRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let urls = notification.userInfo?["urls"] as? [URL] else { return }
            Task { @MainActor in
                self.spotlightRemoveNotes(at: urls)
                self.removePreviewsForNotes(at: urls)
                self.removeSearchEntries(for: urls)
            }
        }
        noteLifecycleObservers.append(removedObserver)

        // .quartzSpotlightNoteRelocated — update spotlight, preview, and search paths
        let relocatedObserver = NotificationCenter.default.addObserver(
            forName: .quartzSpotlightNoteRelocated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let oldURL = notification.userInfo?["old"] as? URL,
                  let newURL = notification.userInfo?["new"] as? URL else { return }
            Task { @MainActor in
                self.spotlightRelocateNote(from: oldURL, to: newURL)
                self.handleSearchAndPreviewRelocation(from: oldURL, to: newURL)
            }
        }
        noteLifecycleObservers.append(relocatedObserver)

        // .quartzFilePresenterDidChange — external edits should refresh all in-app indexes
        let filePresenterChangeObserver = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.spotlightIndexNote(at: url)
                self.updatePreviewForNote(at: url)
                self.updateSearchIndex(for: url)
            }
        }
        noteLifecycleObservers.append(filePresenterChangeObserver)

        // .quartzFilePresenterWillDelete — external deletes must remove all persisted in-app indexes
        let filePresenterDeleteObserver = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterWillDelete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.spotlightRemoveNotes(at: [url])
                self.removePreviewsForNotes(at: [url])
                self.removeSearchEntries(for: [url])
            }
        }
        noteLifecycleObservers.append(filePresenterDeleteObserver)

        // .quartzFilePresenterDidMove — external renames/moves must relocate all in-app indexes
        let filePresenterMoveObserver = NotificationCenter.default.addObserver(
            forName: .quartzFilePresenterDidMove,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let oldURL = notification.userInfo?["oldURL"] as? URL,
                  let newURL = notification.userInfo?["newURL"] as? URL else { return }
            Task { @MainActor in
                self.spotlightRelocateNote(from: oldURL, to: newURL)
                self.handleSearchAndPreviewRelocation(from: oldURL, to: newURL)
            }
        }
        noteLifecycleObservers.append(filePresenterMoveObserver)

        // .quartzReindexRequested — full vault reindex
        let reindexObserver = NotificationCenter.default.addObserver(
            forName: .quartzReindexRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reindexVault()
            }
        }
        noteLifecycleObservers.append(reindexObserver)
    }

    /// Stops all note lifecycle observers.
    private func stopNoteLifecycleObservers() {
        for observer in noteLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        noteLifecycleObservers.removeAll()
    }

    // MARK: - Relationship Lifecycle Repair

    private func startRelationshipLifecycleObserver(for vaultRoot: URL) {
        relationshipLifecycleTask?.cancel()
        relationshipLifecycleTask = Task { [weak self] in
            let stream = await DomainEventBus.shared.subscribe()
            for await event in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.handleRelationshipLifecycleEvent(event, vaultRoot: vaultRoot)
            }
        }
    }

    private func handleRelationshipLifecycleEvent(_ event: DomainEvent, vaultRoot: URL) async {
        switch event {
        case let .noteSaved(url, _):
            guard hasHydratedExplicitRelationships,
                  relationshipEventImpactsCurrentVault(urls: [url], vaultRoot: vaultRoot) else { return }
            await refreshExplicitRelationshipsAfterSave(for: url)
        case let .noteRelocated(from, to):
            guard relationshipEventImpactsCurrentVault(urls: [from, to], vaultRoot: vaultRoot) else { return }
            scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: true)
        case let .noteDeleted(url):
            guard relationshipEventImpactsCurrentVault(urls: [url], vaultRoot: vaultRoot) else { return }
            scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: true)
        default:
            break
        }
    }

    private func relationshipEventImpactsCurrentVault(urls: [URL], vaultRoot: URL) -> Bool {
        let canonicalVaultRoot = vaultRoot.standardizedFileURL
        return urls
            .map(CanonicalNoteIdentity.canonicalFileURL(for:))
            .contains { url in
                url.path(percentEncoded: false).hasPrefix(canonicalVaultRoot.path(percentEncoded: false))
            }
    }

    private func scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: Bool) {
        guard hasHydratedExplicitRelationships,
              let vaultRoot = currentVaultRootURL else { return }
        let generation = relationshipRuntimeGeneration

        explicitRelationshipRepairNeedsSidebarRefresh =
            explicitRelationshipRepairNeedsSidebarRefresh || requiresSidebarRefresh

        explicitRelationshipRepairTask?.cancel()
        explicitRelationshipRepairTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self,
                  !Task.isCancelled,
                  self.isCurrentRelationshipGeneration(generation, vaultRoot: vaultRoot),
                  self.currentVaultRootURL == vaultRoot else { return }

            let needsSidebarRefresh = self.explicitRelationshipRepairNeedsSidebarRefresh
            self.explicitRelationshipRepairNeedsSidebarRefresh = false
            self.isPerformingExplicitRelationshipRepair = true
            defer { self.isPerformingExplicitRelationshipRepair = false }

            if needsSidebarRefresh {
                await self.sidebarViewModel?.refresh()
            }

            let tree = self.sidebarViewModel?.fileTree ?? []
            await self.syncRelationshipCatalog(to: tree)
            await self.rebuildExplicitRelationshipState(from: tree)
        }
    }

    private func syncRelationshipCatalog(to tree: [FileNode]) async {
        await graphEdgeStore.configureCanonicalResolution(with: tree)
        editorSession?.fileTree = tree
    }

    private func refreshExplicitRelationshipsAfterSave(for sourceURL: URL) async {
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let tree = sidebarViewModel?.fileTree ?? []

        guard let existingNode = Self.findFileNode(at: canonicalSourceURL, in: tree) else {
            scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: true)
            return
        }

        let provider = vaultProvider ?? ServiceContainer.shared.resolveVaultProvider()
        guard let savedNote = try? await provider.readNote(at: canonicalSourceURL) else {
            scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: true)
            return
        }

        if Self.identityMetadataChanged(
            from: existingNode.frontmatter,
            to: savedNote.frontmatter
        ) {
            scheduleExplicitRelationshipLifecycleRepair(requiresSidebarRefresh: true)
            return
        }

        await refreshExplicitRelationshipState(for: canonicalSourceURL, within: tree)
    }

    private func refreshExplicitRelationshipState(for sourceURL: URL, within tree: [FileNode]) async {
        let provider = vaultProvider ?? ServiceContainer.shared.resolveVaultProvider()
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let catalog = NoteReferenceCatalog(allNotes: tree)
        let previousTargets = Set(await graphEdgeStore.explicitReferences(from: canonicalSourceURL).map(\.targetNoteURL))

        let references: [ExplicitNoteReference]
        if let note = try? await provider.readNote(at: canonicalSourceURL) {
            references = await catalog.resolvedExplicitReferences(
                in: note.body,
                sourceNoteURL: canonicalSourceURL,
                graphEdgeStore: nil
            )
        } else {
            references = []
        }

        await graphEdgeStore.updateExplicitReferences(for: canonicalSourceURL, references: references)
        let newTargets = Set(await graphEdgeStore.explicitReferences(from: canonicalSourceURL).map(\.targetNoteURL))
        let affectedTargets = Array(previousTargets.union(newTargets))

        NotificationCenter.default.post(
            name: .quartzReferenceGraphDidChange,
            object: nil,
            userInfo: ["targetURLs": affectedTargets]
        )

        await persistExplicitRelationshipSnapshot(from: tree)
    }

    private func rebuildExplicitRelationshipState(from tree: [FileNode]) async {
        let provider = vaultProvider ?? ServiceContainer.shared.resolveVaultProvider()
        let catalog = NoteReferenceCatalog(allNotes: tree)
        let noteURLs = Self.collectNoteURLs(from: tree)
        var referencesBySource: [URL: [ExplicitNoteReference]] = [:]

        for noteURL in noteURLs {
            guard let note = try? await provider.readNote(at: noteURL) else { continue }
            let references = await catalog.resolvedExplicitReferences(
                in: note.body,
                sourceNoteURL: noteURL,
                graphEdgeStore: nil
            )
            if !references.isEmpty {
                referencesBySource[CanonicalNoteIdentity.canonicalFileURL(for: noteURL)] = references
            }
        }

        let affectedTargets = await graphEdgeStore.replaceExplicitRelationshipState(with: referencesBySource)
        NotificationCenter.default.post(
            name: .quartzReferenceGraphDidChange,
            object: nil,
            userInfo: ["targetURLs": Array(affectedTargets)]
        )
        await persistExplicitRelationshipSnapshot(from: tree)
    }

    private func persistExplicitRelationshipSnapshot(from tree: [FileNode]) async {
        guard let vaultRoot = currentVaultRootURL else { return }
        let noteURLs = Self.collectNoteURLs(from: tree)
        let fingerprint = GraphCache(vaultRoot: vaultRoot).computeFingerprint(for: noteURLs)
        let snapshot = await graphEdgeStore.exportExplicitRelationshipSnapshot(fingerprint: fingerprint)
        do {
            try GraphCache(vaultRoot: vaultRoot).saveExplicitRelationshipSnapshot(snapshot)
        } catch {
            assertionFailure("Failed to persist explicit relationship snapshot: \(error)")
        }
    }

    private func persistSemanticRelationshipSnapshot(from tree: [FileNode]) async {
        guard let vaultRoot = currentVaultRootURL else { return }
        let noteURLs = Self.collectNoteURLs(from: tree)
        let fingerprint = GraphCache(vaultRoot: vaultRoot).computeFingerprint(for: noteURLs)
        let snapshot = await graphEdgeStore.exportSemanticRelationshipSnapshot(fingerprint: fingerprint)
        do {
            try GraphCache(vaultRoot: vaultRoot).saveSemanticRelationshipSnapshot(snapshot)
        } catch {
            assertionFailure("Failed to persist related-note similarity snapshot: \(error)")
        }
    }

    private func scheduleSemanticSnapshotPersistence(from tree: [FileNode]) {
        let generation = relationshipRuntimeGeneration
        let treeSnapshot = tree

        semanticSnapshotPersistTask?.cancel()
        semanticSnapshotPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self,
                  !Task.isCancelled,
                  self.isCurrentRelationshipGeneration(generation) else { return }
            await self.persistSemanticRelationshipSnapshot(from: treeSnapshot)
        }
    }

    private func isCurrentRelationshipGeneration(_ generation: UInt64, vaultRoot: URL? = nil) -> Bool {
        guard relationshipRuntimeGeneration == generation else { return false }
        guard let vaultRoot else { return true }
        return currentVaultRootURL?.standardizedFileURL == vaultRoot.standardizedFileURL
    }

    private func isCurrentIndexingRun(
        _ runID: UInt64,
        generation: UInt64,
        vaultRoot: URL
    ) -> Bool {
        indexingRunID == runID && isCurrentRelationshipGeneration(generation, vaultRoot: vaultRoot)
    }

    private func notificationBelongsToCurrentVault(_ updatedVaultRoot: URL?) -> Bool {
        guard let updatedVaultRoot else { return true }
        guard let currentVaultRootURL else { return false }
        return updatedVaultRoot.standardizedFileURL == currentVaultRootURL.standardizedFileURL
    }

    // MARK: - Note Opening

    /// Opens a note by loading it into the existing EditorSession.
    /// The session object is REUSED — no view destruction, no flash.
    public func openNote(at url: URL?) {
        guard let url else {
            editorSession?.closeNote()
            documentChatSession?.clear()
            return
        }

        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        guard FileManager.default.fileExists(atPath: canonicalURL.path(percentEncoded: false)) else { return }

        // Reuse existing session — just load the new note into it
        if let session = editorSession {
            session.fileTree = sidebarViewModel?.fileTree ?? []
            Task { await session.loadNote(at: canonicalURL) }
        }

        // Clear chat history — system prompt is document-specific
        documentChatSession?.clear()
    }

    // MARK: - Startup Restoration

    /// Completes startup only after the asynchronous warm-up phase has finished and
    /// the shell has either applied or intentionally skipped editor restoration.
    public func completeStartupRestorationIfNeeded() {
        restorationPhaseTask?.cancel()
        restorationPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startupCoordinator.awaitPhase(.indexWarm)
            guard self.startupCoordinator.currentPhase == .indexWarm else { return }
            _ = self.startupCoordinator.advance(to: .restorationApplied)
        }
    }

    // MARK: - Daily Note

    /// Creates a daily note with today's date as the filename (ISO 8601).
    public func createDailyNote() {
        guard let root = sidebarViewModel?.vaultRootURL else { return }
        // en_US_POSIX ensures stable ISO date format for filenames
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: Date())
        Task {
            await sidebarViewModel?.createNote(named: name, in: root)
        }
    }

    // MARK: - Vault Chat

    /// Creates a new streaming vault chat session wired to the current embedding service.
    ///
    /// **Just-in-time indexing:** Before creating the session, ensures the background
    /// indexer has completed (waits up to 30s), then force-saves the active note
    /// and indexes its live text into the vector store.
    public func createVaultChatSession2() async -> VaultChatSession2? {
        guard let embeddingService,
              let vaultRoot = currentVaultRootURL else { return nil }

        // Just-in-time: save + index the active note before chat opens
        if let session = editorSession, let noteURL = session.note?.fileURL {
            await session.save(force: true)
            let liveText = session.currentText
            if !liveText.isEmpty {
                let stableID = VectorEmbeddingService.stableNoteID(for: noteURL, vaultRoot: vaultRoot)
                do {
                    try await embeddingService.indexNote(noteID: stableID, content: liveText)
                    try await embeddingService.saveIndex()
                } catch {
                    Self.logIndexingFailure("just-in-time embedding update", error: error, noteURL: noteURL)
                }
            }
        }

        let fileTree = sidebarViewModel?.fileTree ?? []
        let titleMap = Self.buildNoteTitleMap(from: fileTree, vaultRoot: vaultRoot)

        // Log index state for diagnostics
        let entryCount = await embeddingService.entryCount
        let noteCount = await embeddingService.indexedNoteCount
        print("[VaultChat] Opening with \(entryCount) chunks from \(noteCount) notes, \(titleMap.count) notes in tree")

        let chatService = VaultChatService(
            embeddingService: embeddingService,
            providerRegistry: .shared
        )

        return VaultChatSession2(
            chatService: chatService,
            noteResolver: { noteID in titleMap[noteID] },
            indexedChunkCount: entryCount,
            indexedNoteCount: noteCount
        )
    }

    /// Legacy non-streaming vault chat session (kept for backward compatibility during migration).
    public func createVaultChatSession() -> VaultChatSession? {
        guard let embeddingService,
              let vaultRoot = currentVaultRootURL else { return nil }

        let fileTree = sidebarViewModel?.fileTree ?? []
        let titleMap = Self.buildNoteTitleMap(from: fileTree, vaultRoot: vaultRoot)

        let chatService = VaultChatService(
            embeddingService: embeddingService,
            providerRegistry: .shared
        )

        return VaultChatSession(
            chatService: chatService,
            noteResolver: { noteID in titleMap[noteID] }
        )
    }

    /// Resolves a stable vault note ID (embeddings / vault chat sources) to the note’s file URL.
    public func urlForVaultNote(stableID: UUID) -> URL? {
        guard let vaultRoot = currentVaultRootURL,
              let tree = sidebarViewModel?.fileTree else { return nil }
        return Self.urlForNoteFile(stableID: stableID, nodes: tree, vaultRoot: vaultRoot)
    }

    private static func urlForNoteFile(stableID: UUID, nodes: [FileNode], vaultRoot: URL) -> URL? {
        for node in nodes {
            if node.isNote {
                let id = VectorEmbeddingService.stableNoteID(for: node.url, vaultRoot: vaultRoot)
                if id == stableID { return node.url }
            }
            if let children = node.children,
               let url = urlForNoteFile(stableID: stableID, nodes: children, vaultRoot: vaultRoot) {
                return url
            }
        }
        return nil
    }

    /// Re-indexes every note in the vault. Can be triggered from the UI.
    public func reindexVault() {
        guard let tree = sidebarViewModel?.fileTree,
              let vaultRoot = currentVaultRootURL else { return }
        refreshSearchAndPreviewCaches(from: tree, vaultRoot: vaultRoot, forceSearchRebuild: true)
        if let embedding = embeddingService {
            indexAllNotes(
                in: tree,
                vaultRoot: vaultRoot,
                embedding: embedding,
                generation: relationshipRuntimeGeneration
            )
        }
        Task {
            await spotlightIndexer?.removeAllInDomain()
            await spotlightIndexer?.indexAllNotes(urls: Self.collectNoteURLs(from: tree), vaultRoot: vaultRoot)
        }
    }

    // MARK: - Incremental Search Index Updates

    /// Incrementally updates the in-app search index for a single saved note.
    /// Called on every note save via `.quartzNoteSaved` notification.
    public func updateSearchIndex(for url: URL) {
        Task {
            await searchIndex?.updateEntry(for: url)
        }
    }

    /// Removes search index entries for deleted notes.
    public func removeSearchEntries(for urls: [URL]) {
        Task {
            for url in urls {
                await searchIndex?.removeEntry(for: url)
            }
        }
    }

    public func relocateSearchEntry(from oldURL: URL, to newURL: URL) {
        Task {
            await searchIndex?.removeEntry(for: oldURL)
            await searchIndex?.updateEntry(for: newURL)
        }
    }

    // MARK: - Core Spotlight

    /// Called when a note file is saved (autosave or explicit).
    public func spotlightIndexNote(at url: URL) {
        guard let vaultRoot = currentVaultRootURL else { return }
        Task {
            await spotlightIndexer?.indexNote(at: url, vaultRoot: vaultRoot)
        }
    }

    /// Removes Spotlight entries for deleted markdown files.
    public func spotlightRemoveNotes(at urls: [URL]) {
        Task {
            for url in urls {
                await spotlightIndexer?.removeNote(fileURL: url)
            }
        }
    }

    /// Updates Spotlight when a note file moves on disk.
    public func spotlightRelocateNote(from oldURL: URL, to newURL: URL) {
        guard let vaultRoot = currentVaultRootURL else { return }
        Task { @MainActor in
            // Single markdown file: update one Spotlight entry. Folder moves change many paths — reindex the vault.
            if newURL.pathExtension.lowercased() == "md" {
                await spotlightIndexer?.relocate(from: oldURL, to: newURL, vaultRoot: vaultRoot)
            } else if let tree = sidebarViewModel?.fileTree {
                await spotlightIndexer?.removeAllInDomain()
                await spotlightIndexer?.indexAllNotes(urls: Self.collectNoteURLs(from: tree), vaultRoot: vaultRoot)
            }
        }
    }

    // MARK: - Preview Cache (Incremental Updates)

    /// Incrementally updates the preview cache for a single saved note.
    /// Posts `.quartzPreviewCacheDidChange` with the URL so `NoteListStore` can do a targeted update.
    public func updatePreviewForNote(at url: URL) {
        Task {
            await previewIndexer?.indexFile(at: url)
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: url)
        }
    }

    /// Removes preview entries for deleted notes.
    public func removePreviewsForNotes(at urls: [URL]) {
        Task {
            for url in urls {
                await previewIndexer?.removeFile(at: url)
            }
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: nil)
        }
    }

    /// Updates preview entry when a note is renamed or moved.
    public func relocatePreview(from oldURL: URL, to newURL: URL) {
        Task {
            await previewIndexer?.removeFile(at: oldURL)
            await previewIndexer?.indexFile(at: newURL)
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: nil)
        }
    }

    private func handleSearchAndPreviewRelocation(from oldURL: URL, to newURL: URL) {
        if newURL.pathExtension.lowercased() == "md" {
            relocatePreview(from: oldURL, to: newURL)
            relocateSearchEntry(from: oldURL, to: newURL)
            return
        }

        guard let tree = sidebarViewModel?.fileTree,
              let vaultRoot = currentVaultRootURL else { return }
        refreshSearchAndPreviewCaches(from: tree, vaultRoot: vaultRoot, forceSearchRebuild: true)
    }

    private func refreshSearchAndPreviewCaches(
        from tree: [FileNode],
        vaultRoot: URL,
        forceSearchRebuild: Bool = false
    ) {
        Task {
            await previewIndexer?.indexAll(from: tree)
            NotificationCenter.default.post(name: .quartzPreviewCacheDidChange, object: nil)
        }

        Task {
            if forceSearchRebuild {
                await searchIndex?.rebuildIndex(fromPreloadedTree: tree, at: vaultRoot)
            } else {
                await searchIndex?.buildIndex(fromPreloadedTree: tree, at: vaultRoot)
            }
        }
    }

    // MARK: - Incremental Embedding Updates

    /// Re-indexes a single note's embeddings after save.
    /// Runs on a background thread to avoid blocking the editor.
    public func updateEmbeddingForNote(at url: URL) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }
        let generation = relationshipRuntimeGeneration

        // If this is the active note, use live text (avoids stale disk read)
        let liveText: String? = (editorSession?.note?.fileURL == url) ? editorSession?.currentText : nil

        let semanticService = self.semanticLinkService
        let extractionService = self.knowledgeExtractionService
        Task.detached(priority: .utility) {
            let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
            // CRITICAL: Use coordinated read to prevent race with iCloud sync
            let content: String?
            if let liveText {
                content = liveText
            } else {
                do {
                    content = try CoordinatedFileWriter.shared.readString(from: url)
                } catch {
                    Self.logIndexingFailure("embedding note read", error: error, noteURL: url)
                    content = nil
                }
            }
            if let content, !content.isEmpty {
                do {
                    try await embedding.indexNote(noteID: stableID, content: content)
                    try await embedding.saveIndex()
                } catch {
                    Self.logIndexingFailure("embedding note update", error: error, noteURL: url)
                    return
                }
                let isCurrentGeneration = await MainActor.run { [weak self] in
                    self?.isCurrentRelationshipGeneration(generation, vaultRoot: vaultRoot) ?? false
                }
                guard isCurrentGeneration else { return }
                // Trigger background related-note similarity analysis after successful embedding update
                await semanticService?.scheduleAnalysis(for: url)
                // Trigger AI concept extraction
                await extractionService?.scheduleExtraction(for: url)
            }
        }
    }

    /// Removes embeddings for deleted notes.
    public func removeEmbeddingsForNotes(at urls: [URL]) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                await embedding.removeNote(stableID)
            }
            do {
                try await embedding.saveIndex()
            } catch {
                Self.logIndexingFailure("embedding deletion save", error: error)
            }
        }
    }

    /// Updates embeddings when a note is renamed or moved.
    public func relocateEmbedding(from oldURL: URL, to newURL: URL) {
        guard let embedding = embeddingService,
              let vaultRoot = currentVaultRootURL else { return }
        Task.detached(priority: .utility) {
            // Remove old stableID entries
            let oldID = VectorEmbeddingService.stableNoteID(for: oldURL, vaultRoot: vaultRoot)
            await embedding.removeNote(oldID)
            // Index at new stableID with coordinated read
            let newID = VectorEmbeddingService.stableNoteID(for: newURL, vaultRoot: vaultRoot)
            // CRITICAL: Use coordinated read to prevent race with iCloud sync
            let content: String?
            do {
                content = try CoordinatedFileWriter.shared.readString(from: newURL)
            } catch {
                Self.logIndexingFailure("embedding relocation read", error: error, noteURL: newURL)
                content = nil
            }
            if let content, !content.isEmpty {
                do {
                    try await embedding.indexNote(noteID: newID, content: content)
                } catch {
                    Self.logIndexingFailure("embedding relocation index", error: error, noteURL: newURL)
                }
            }
            do {
                try await embedding.saveIndex()
            } catch {
                Self.logIndexingFailure("embedding relocation save", error: error, noteURL: newURL)
            }
        }
    }

    // MARK: - Backup

    /// Triggers a manual backup of the current vault.
    public func triggerManualBackup() {
        guard let vaultRoot = currentVaultRootURL else { return }
        guard !isBackupInProgress else { return }

        isBackupInProgress = true
        backupProgress = 0

        Task.detached(priority: .utility) { [backupService] in
            do {
                _ = try await backupService.createBackup(vaultRoot: vaultRoot) { progress in
                    Task { @MainActor [weak self] in
                        self?.backupProgress = progress.fraction
                    }
                }
                await MainActor.run { [weak self] in
                    self?.isBackupInProgress = false
                    self?.backupProgress = 1
                    self?.refreshAvailableBackups(vaultRoot: vaultRoot)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isBackupInProgress = false
                    self?.backupProgress = 0
                }
            }
        }
    }

    /// Restores a backup to a user-chosen destination.
    /// Returns the URL of the restored vault folder.
    public func restoreFromBackup(backupURL: URL, destination: URL) async throws {
        try await backupService.restoreBackup(from: backupURL, to: destination)
    }

    /// Refreshes the list of available backups for the current vault.
    public func refreshAvailableBackups(vaultRoot: URL? = nil) {
        guard let root = vaultRoot ?? currentVaultRootURL else { return }
        Task {
            let backups = await backupService.listBackups(vaultRoot: root)
            availableBackups = backups
        }
    }

    /// Checks if auto-backup is enabled and schedules one if >24h since last backup.
    private func scheduleAutoBackupIfNeeded(vaultRoot: URL) {
        let autoEnabled = UserDefaults.standard.bool(forKey: "quartzAutoBackupEnabled")
        guard autoEnabled else { return }

        Task.detached(priority: .utility) { [backupService] in
            let retainCount = UserDefaults.standard.integer(forKey: "quartzAutoBackupRetainCount")
            try? await backupService.runAutoBackup(
                vaultRoot: vaultRoot,
                retainCount: max(1, retainCount > 0 ? retainCount : 7)
            )
            await MainActor.run { [weak self] in
                self?.refreshAvailableBackups(vaultRoot: vaultRoot)
            }
        }
    }

    // MARK: - Note Indexing

    /// Recursively flattens the file tree into a UUID → title lookup using stable IDs.
    private static func buildNoteTitleMap(from nodes: [FileNode], vaultRoot: URL) -> [UUID: String] {
        var map: [UUID: String] = [:]
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isNote {
                    let title = node.name.replacingOccurrences(of: ".md", with: "")
                    let stableID = VectorEmbeddingService.stableNoteID(for: node.url, vaultRoot: vaultRoot)
                    map[stableID] = title
                }
                if let children = node.children {
                    walk(children)
                }
            }
        }
        walk(nodes)
        return map
    }

    /// Collects all note file URLs from the tree recursively.
    private static func collectNoteURLs(from nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isNote {
                    urls.append(node.url)
                }
                if let children = node.children {
                    walk(children)
                }
            }
        }
        walk(nodes)
        return urls
    }

    private static func findFileNode(at url: URL, in nodes: [FileNode]) -> FileNode? {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        for node in nodes {
            if CanonicalNoteIdentity.canonicalFileURL(for: node.url) == canonicalURL {
                return node
            }
            if let children = node.children,
               let found = findFileNode(at: canonicalURL, in: children) {
                return found
            }
        }
        return nil
    }

    private static func identityMetadataChanged(from oldFrontmatter: Frontmatter?, to newFrontmatter: Frontmatter) -> Bool {
        normalizeIdentityMetadata(oldFrontmatter?.title) != normalizeIdentityMetadata(newFrontmatter.title)
            || normalizeIdentityList(oldFrontmatter?.aliases ?? []) != normalizeIdentityList(newFrontmatter.aliases)
    }

    private static func normalizeIdentityMetadata(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizeIdentityList(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Indexes all notes in the file tree via the embedding service.
    /// Runs file I/O and embedding generation on a background thread,
    /// hopping back to MainActor only for progress updates.
    private func indexAllNotes(
        in tree: [FileNode],
        vaultRoot: URL,
        embedding: VectorEmbeddingService,
        generation: UInt64
    ) {
        indexingTask?.cancel()
        indexingRunID &+= 1
        let runID = indexingRunID

        let noteURLs = Self.collectNoteURLs(from: tree)
        guard !noteURLs.isEmpty else { return }

        indexingTask = Task.detached(priority: .utility) {
            let indexingStart = DispatchTime.now().uptimeNanoseconds
            var pendingNoteURLs: [URL] = []
            pendingNoteURLs.reserveCapacity(noteURLs.count)
            var pendingMissingMTime = 0
            var pendingNeverIndexed = 0
            var pendingModifiedAfterIndex = 0

            for url in noteURLs {
                guard !Task.isCancelled else { break }
                let isCurrentGeneration = await MainActor.run { [weak self] in
                    self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) ?? false
                }
                guard isCurrentGeneration else { return }

                let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let lastIndexed = await embedding.lastIndexedDate(for: stableID)
                if let mtime, let lastIndexed, mtime <= lastIndexed {
                    continue
                }

                if mtime == nil {
                    pendingMissingMTime += 1
                } else if lastIndexed == nil {
                    pendingNeverIndexed += 1
                } else {
                    pendingModifiedAfterIndex += 1
                }
                pendingNoteURLs.append(url)
            }

            let isCurrentGenerationAtCompletion = await MainActor.run { [weak self] in
                self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) ?? false
            }
            guard isCurrentGenerationAtCompletion else { return }

            guard !pendingNoteURLs.isEmpty else {
                Self.indexingTelemetryLogger.info(
                    "Embedding sweep skipped: 0/\(noteURLs.count) notes need re-embedding"
                )
                QuartzDiagnostics.info(
                    category: "IndexingTelemetry",
                    "Embedding sweep skipped: 0/\(noteURLs.count) notes need re-embedding"
                )
                await MainActor.run { [weak self] in
                    guard self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) == true else { return }
                    self?.indexingProgress = nil
                    self?.sidebarViewModel?.indexingProgress = nil
                }
                return
            }

            let total = pendingNoteURLs.count
            Self.indexingTelemetryLogger.info(
                "Embedding sweep start: \(total)/\(noteURLs.count) notes need re-embedding (neverIndexed=\(pendingNeverIndexed), modified=\(pendingModifiedAfterIndex), missingMTime=\(pendingMissingMTime))"
            )
            QuartzDiagnostics.info(
                category: "IndexingTelemetry",
                "Embedding sweep start: \(total)/\(noteURLs.count) notes need re-embedding reason.neverIndexed=\(pendingNeverIndexed) reason.modifiedAfterIndex=\(pendingModifiedAfterIndex) reason.missingMTime=\(pendingMissingMTime)"
            )
            await MainActor.run { [weak self] in
                guard self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) == true else { return }
                let progress = (current: 0, total: total)
                self?.indexingProgress = progress
                self?.sidebarViewModel?.indexingProgress = progress
            }

            var changedNotesSinceCheckpoint = 0
            var indexedNotes = 0
            for (i, url) in pendingNoteURLs.enumerated() {
                guard !Task.isCancelled else { break }
                let isCurrentGeneration = await MainActor.run { [weak self] in
                    self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) ?? false
                }
                guard isCurrentGeneration else { break }

                let stableID = VectorEmbeddingService.stableNoteID(for: url, vaultRoot: vaultRoot)
                let content: String?
                do {
                    content = try CoordinatedFileWriter.shared.readString(from: url)
                } catch {
                    Self.logIndexingFailure("embedding sweep note read", error: error, noteURL: url)
                    content = nil
                }
                if let content, !content.isEmpty {
                    do {
                        try await embedding.indexNote(noteID: stableID, content: content)
                        indexedNotes += 1
                        changedNotesSinceCheckpoint += 1
                        if changedNotesSinceCheckpoint >= Self.embeddingCheckpointInterval {
                            try await embedding.saveIndex()
                            changedNotesSinceCheckpoint = 0
                        }
                    } catch {
                        Self.logIndexingFailure("embedding sweep update/checkpoint", error: error, noteURL: url)
                    }
                }

                let current = i + 1
                if current == total || current.isMultiple(of: 100) {
                    Self.indexingTelemetryLogger.info(
                        "Embedding sweep progress: \(current)/\(total) pending notes processed"
                    )
                    QuartzDiagnostics.info(
                        category: "IndexingTelemetry",
                        "Embedding sweep progress: \(current)/\(total) pending notes processed"
                    )
                }
                if current == total || current.isMultiple(of: 10) {
                    await MainActor.run { [weak self] in
                        let progress = (current: current, total: total)
                        self?.indexingProgress = progress
                        self?.sidebarViewModel?.indexingProgress = progress
                    }
                }
                await Task.yield()
            }

            let isCurrentGeneration = await MainActor.run { [weak self] in
                self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) ?? false
            }
            guard isCurrentGeneration else { return }
            do {
                try await embedding.saveIndex()
            } catch {
                Self.logIndexingFailure("embedding sweep final save", error: error)
            }
            Self.logIndexingStage(
                "embedding sweep",
                startedAt: indexingStart,
                noteCount: total,
                detail: "\(indexedNotes) notes indexed"
            )
            await MainActor.run { [weak self] in
                guard self?.isCurrentIndexingRun(runID, generation: generation, vaultRoot: vaultRoot) == true else { return }
                self?.indexingProgress = nil
                self?.sidebarViewModel?.indexingProgress = nil
            }
        }
    }

    // MARK: - iCloud Sync

    private func startCloudSync(for vaultURL: URL) {
        let service = CloudSyncService()
        cloudSyncService = service
        cloudSyncStatus = .current

        conflictingFileURLs = []
        syncMonitoringTask = Task {
            let stream = await service.startMonitoring(vaultRoot: vaultURL)
            var fileStatuses: [URL: CloudSyncStatus] = [:]
            for await (url, status) in stream {
                fileStatuses[url] = status
                cloudSyncStatus = Self.aggregateStatus(from: fileStatuses)
                sidebarViewModel?.cloudSyncStatus = cloudSyncStatus
                if cloudSyncStatus == .current {
                    lastSyncTimestamp = Date()
                }
                conflictingFileURLs = fileStatuses.filter { $0.value == .conflict }.map(\.key)
            }
        }
    }

    public func stopCloudSync() {
        syncMonitoringTask?.cancel()
        syncMonitoringTask = nil
        if let service = cloudSyncService {
            Task { await service.stopMonitoring() }
        }
        cloudSyncService = nil
        cloudSyncStatus = .notApplicable
        sidebarViewModel?.cloudSyncStatus = .notApplicable
        conflictingFileURLs = []
        stopNoteLifecycleObservers()
    }

    private static func isICloudDriveURL(_ url: URL) -> Bool {
        if FileManager.default.isUbiquitousItem(at: url) { return true }
        let path = url.path(percentEncoded: false)
        return path.contains("com~apple~CloudDocs") || path.contains("/Mobile Documents/")
    }

    private static func aggregateStatus(from statuses: [URL: CloudSyncStatus]) -> CloudSyncStatus {
        let values = statuses.values
        if values.contains(.error) { return .error }
        if values.contains(.conflict) { return .conflict }
        if values.contains(.uploading) { return .uploading }
        if values.contains(.downloading) { return .downloading }
        if values.contains(.notDownloaded) { return .downloading }
        return .current
    }

    // MARK: - iCloud Vault Migration

    /// Whether the current vault is inside the app's iCloud ubiquity container.
    public var isVaultInICloud: Bool {
        guard let root = currentVaultRootURL else { return false }
        return Self.isICloudDriveURL(root)
    }

    /// Whether iCloud is available on this device.
    /// Resolves the container URL on a background thread to check availability.
    /// Cached after first check to avoid repeated blocking calls.
    public var isICloudAvailable: Bool = false

    /// Checks iCloud availability by resolving the ubiquity container.
    /// Call this once during vault load or settings open.
    public func checkICloudAvailability() {
        let token = FileManager.default.ubiquityIdentityToken
        print("[iCloud] ubiquityIdentityToken: \(String(describing: token))")
        Task {
            let url = await CloudSyncService.resolveContainerURL()
            print("[iCloud] resolveContainerURL: \(String(describing: url))")
            isICloudAvailable = url != nil
            print("[iCloud] isICloudAvailable set to: \(url != nil)")
        }
    }

    /// Migrates the current local vault into the app's iCloud ubiquity container.
    ///
    /// Copies the entire vault directory into `iCloud.olli.QuartzNotes/Documents/{vaultName}/`,
    /// then switches the app to use the iCloud copy as the active vault. The original local
    /// copy is left untouched as a backup.
    ///
    /// - Returns: The new iCloud vault URL, or `nil` if migration failed.
    @discardableResult
    public func migrateVaultToICloud() async -> URL? {
        guard let localRoot = currentVaultRootURL else { return nil }

        guard CloudSyncService.isAvailable else {
            cloudSyncStatus = .error
            return nil
        }

        // Resolve container URL on background thread (first call may block while
        // the system creates the container directory structure)
        guard let containerURL = await CloudSyncService.resolveContainerURL() else {
            cloudSyncStatus = .error
            return nil
        }

        let fm = FileManager.default
        let vaultName = localRoot.lastPathComponent
        let iCloudVaultURL = containerURL.appending(path: vaultName, directoryHint: .isDirectory)

        do {
            // Ensure the Documents directory exists
            if !fm.fileExists(atPath: containerURL.path(percentEncoded: false)) {
                try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            }

            // If the vault already exists in iCloud, just switch to it
            if fm.fileExists(atPath: iCloudVaultURL.path(percentEncoded: false)) {
                switchToVault(at: iCloudVaultURL, name: vaultName)
                return iCloudVaultURL
            }

            // Copy the local vault to iCloud
            try fm.copyItem(at: localRoot, to: iCloudVaultURL)

            // Switch to the iCloud vault
            switchToVault(at: iCloudVaultURL, name: vaultName)

            return iCloudVaultURL
        } catch {
            cloudSyncStatus = .error
            return nil
        }
    }

    /// Switches the active vault to a new URL and reloads everything.
    private func switchToVault(at url: URL, name: String) {
        var vault = VaultConfig(name: name, rootURL: url, storageType: .iCloudDrive)
        vault.isDefault = true
        appState.switchVault(to: vault)
        // Reload vault is triggered by the app state change in ContentView
    }

    // MARK: - Command Handling

    /// Processes a keyboard shortcut command, routing UI actions through the coordinator.
    ///
    /// Replaces the previous 5-`inout` parameter signature with a single coordinator.
    /// Layout commands (toggle sidebar) route through `WorkspaceStore`.
    public func handleCommand(
        _ command: CommandAction,
        coordinator: AppCoordinator,
        workspaceStore: WorkspaceStore
    ) {
        switch command {
        case .newNote:
            if let root = sidebarViewModel?.vaultRootURL {
                coordinator.presentNewNote(in: root)
            }
        case .newFolder:
            if let root = sidebarViewModel?.vaultRootURL {
                coordinator.presentNewFolder(in: root)
            }
        case .search:
            editorSession?.presentInNoteSearch()
        case .globalSearch:
            coordinator.activeSheet = .search
        case .toggleSidebar:
            withAnimation(QuartzAnimation.content) {
                workspaceStore.columnVisibility = workspaceStore.columnVisibility == .all
                    ? .detailOnly : .all
            }
        case .dailyNote:
            createDailyNote()
        case .format(let action):
            applyFormatting(action)
        case .paste(let mode):
            editorSession?.paste(mode: mode)
        case .none, .openVault, .createVault:
            break
        }
    }

    private func applyFormatting(_ action: FormattingAction) {
        editorSession?.handleFormattingAction(action, source: .commandMenu)
    }
}
