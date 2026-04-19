# Knowledge Graph Flow Map

Status: PHASE 2 flow mapping complete. This document maps the current runtime relationship flows only. It does not propose fixes.

## Operating Summary

`proven`: Quartz does not have one authoritative relationship pipeline.

Current runtime relationship state is split across:

- live current-note editor state
  - [`EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- explicit reference interpretation for inspector surfaces
  - [`NoteReferenceCatalog.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
  - [`LinkSuggestionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
  - [`BacklinkUseCase.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
- live explicit / semantic / concept edge actor
  - [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - `GraphEdgeStore`
- persisted graph snapshot
  - [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- graph-view local rebuild
  - [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- embedding-based similarity
  - [`SemanticLinkService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift)
  - [`VectorEmbeddingService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift)
- AI concept extraction
  - [`KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)

## Classification Legend

- `authoritative`
  - one owner is clearly responsible for the result in that flow
- `duplicated`
  - multiple systems independently derive similar relationship data
- `heuristic`
  - result comes from matching rules or AI output rather than explicit persisted note links
- `fragile`
  - refresh, invalidation, or identity handoff is incomplete or timing-dependent

## Flow 1 — Explicit Wiki-Link Typed In Editor

- Triggering event:
  - [`MarkdownEditorRepresentable.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift)
  - `Coordinator.textDidChange(_:)`
  - calls [`EditorSession.textDidChange(_:)`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- Authoritative data source:
  - `EditorSession.currentText`
  - `EditorSession.cursorPosition`
  - `EditorSession.fileTree`
- Parser / resolver / transformation:
  - picker trigger detection:
    - `EditorSession.activeWikiLinkTriggerContext(for:)`
  - picker suggestions:
    - `NoteReferenceCatalog.linkInsertionSuggestions(matching:excluding:)`
  - explicit-link target extraction:
    - `EditorSession.explicitLinkTargets(in:)`
    - `WikiLinkExtractor.extractLinks(from:)`
- Cache or index mutation:
  - ephemeral picker state only:
    - `InEditorLinkInsertionState.presentOrUpdate(...)`
  - current-note outgoing-link refresh task scheduled:
    - `EditorSession.scheduleOutgoingLinkRefresh()`
  - live explicit graph update only after extracted target list changes:
    - `EditorSession.refreshExplicitLinkGraphConnectionsIfNeeded()`
    - `GraphEdgeStore.updateConnections(...)`
- Publish / invalidation:
  - `.quartzReferenceGraphDidChange`
  - no typed graph event is authoritative here
- UI consumers:
  - [`NoteLinkPicker.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteLinkPicker.swift)
  - inspector outgoing links
  - inspector backlinks when the edited note links to the current inspector target
- Stale windows / race windows:
  - `proven`: picker suggestions use `NoteReferenceCatalog`, but live graph edges use `GraphEdgeStore.updateConnections(...)`, which usually falls back to basename-only resolution because `GraphEdgeStore.setIdentityResolver(_:)` is not wired in production
  - `proven`: `EditorSession.fileTree.didSet` only reruns link-insertion suggestions; it does not rerun outgoing-link or unlinked-mention analysis when the catalog changes late
- Flow classification:
  - `duplicated`
  - `fragile`

## Flow 2 — Explicit Wiki-Link Saved To Disk

- Triggering event:
  - autosave or manual save
  - [`EditorSession.save(force:)`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- Authoritative data source:
  - native text view snapshot captured inside `save(force:)`
  - `currentNote.frontmatter`
- Parser / resolver / transformation:
  - note is serialized by [`FileSystemVaultProvider.saveNote(...)`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/FileSystemVaultProvider.swift)
  - after disk write, `refreshExplicitLinkGraphConnectionsIfNeeded(force:sourceURL:content:)` re-parses the saved snapshot
- Cache or index mutation:
  - note body/frontmatter persisted to disk
  - content hashes updated in `EditorSession`
  - live explicit graph updated in `GraphEdgeStore`
  - search / preview / Spotlight / embeddings updated indirectly by save observers in [`ContentViewModel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
  - `proven`: persisted graph cache is not updated here
- Publish / invalidation:
  - `DomainEventBus.publish(.noteSaved(...))`
  - `.quartzNoteSaved`
  - `.quartzReferenceGraphDidChange`
- UI consumers:
  - inspector backlinks
  - inspector outgoing links
  - search results, previews, Spotlight, embeddings
- Stale windows / race windows:
  - `proven`: disk save is authoritative for the note file, but graph persistence is not; `GraphCache` remains stale until graph view rebuild/saves
  - `proven`: only the saved/open note’s explicit graph is refreshed here, not a vault-wide graph rebuild
- Flow classification:
  - note save itself: `authoritative`
  - relationship persistence side: `duplicated`
  - `fragile`

## Flow 3 — Outgoing-Links Refresh

- Triggering event:
  - `EditorSession.textDidChange(_:)`
  - `EditorSession.applyLoadedNoteState(...)`
  - any mutation path that changes `currentText`
- Authoritative data source:
  - `EditorSession.currentText`
  - `EditorSession.fileTree`
  - optional `graphEdgeStore` for target resolution
- Parser / resolver / transformation:
  - `NoteReferenceCatalog.resolvedExplicitReferences(in:graphEdgeStore:)`
  - deduplicated into `InspectorStore.OutgoingLinkItem`
- Cache or index mutation:
  - `InspectorStore.setOutgoingLinks(_:)`
  - no disk persistence
  - no graph-cache persistence
- Publish / invalidation:
  - none beyond `@Observable`/SwiftUI state change in `InspectorStore`
- UI consumers:
  - [`InspectorSidebar.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift)
  - [`OutgoingLinksPanel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/OutgoingLinksPanel.swift)
- Stale windows / race windows:
  - `proven`: `fileTree` replacement does not call `scheduleOutgoingLinkRefresh()`
  - `proven`: multiple references to the same target collapse to one row because `scheduleOutgoingLinkRefresh()` deduplicates by `noteURL`
  - `proven`: outgoing links are live current-note state only; reopening another note recomputes them, but they are not sourced from a persisted graph
- Flow classification:
  - current-note result: `authoritative`
  - overall system: `fragile`

## Flow 4 — Backlink Refresh

- Triggering event:
  - inspector task keyed by note/vault:
    - `InspectorSidebar.backlinksTaskKey`
  - `.quartzNoteSaved`
  - `.quartzReferenceGraphDidChange`
- Authoritative data source:
  - there is no single authority
  - `BacklinkUseCase.findBacklinks(to:in:)` merges:
    - full vault scan from disk
    - `GraphEdgeStore.backlinks(for:)`
- Parser / resolver / transformation:
  - scanned path:
    - `BacklinkUseCase.scanForBacklinks(...)`
    - `NoteReferenceCatalog.resolvedExplicitReferences(...)`
  - live graph path:
    - `BacklinkUseCase.liveGraphBacklinks(...)`
    - optionally enriches with line context from note body
- Cache or index mutation:
  - no dedicated backlink cache
  - `InspectorSidebar.backlinks` local `@State` updated after each pull refresh
- Publish / invalidation:
  - pull-based reload driven by `InspectorSidebar`
  - no authoritative backlink event model
- UI consumers:
  - [`BacklinksPanel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/BacklinksPanel.swift)
  - backlink navigation from inspector
- Stale windows / race windows:
  - `proven`: backlinks are a merge of scanned references and live graph edges; disagreements are resolved by local strength scoring, not one canonical source
  - `proven`: stale live graph edges can leak into backlink results until scanned data dominates
  - `proven`: if note catalog changes without save/referenceGraph invalidation, inspector backlinks wait until the next pull refresh trigger
- Flow classification:
  - `duplicated`
  - `fragile`

## Flow 5 — Unlinked-Mention Refresh

- Triggering event:
  - `EditorSession.scheduleAnalysis()`
  - called from `textDidChange(_:)` and `applyLoadedNoteState(...)`
- Authoritative data source:
  - `EditorSession.currentText`
  - `EditorSession.fileTree`
  - optional `GraphEdgeStore` only for explicit-link exclusion resolution
- Parser / resolver / transformation:
  - `LinkSuggestionService.suggestLinks(...)`
  - internally:
    - `NoteReferenceCatalog.resolvedExplicitReferences(...)`
    - exclusion by explicit `noteURL` and `matchRange`
    - heuristic scan of `searchTerms`
    - word-boundary filter
- Cache or index mutation:
  - `InspectorStore.suggestedLinks`
  - no disk persistence
- Publish / invalidation:
  - none beyond `InspectorStore` mutation
- UI consumers:
  - unlinked-mention section in `InspectorSidebar`
  - `EditorSession.linkSuggestedMention(_:)` when user clicks `Link`
- Stale windows / race windows:
  - `proven`: `fileTree` changes do not automatically reschedule `scheduleAnalysis()`
  - `proven`: unlinked mentions are note-local and debounced; they lag keystrokes by `analysisDelay`
  - `proven`: one suggestion per `noteURL` collapses repeated mentions
- Flow classification:
  - `heuristic`
  - `fragile`

## Flow 6 — Graph Edge Creation / Update

- Triggering event:
  - `EditorSession.refreshExplicitLinkGraphConnectionsIfNeeded(...)`
  - called from:
    - `textDidChange(_:)`
    - `applyLoadedNoteState(...)`
    - `save(force:)`
- Authoritative data source:
  - explicit wiki-link targets extracted from current text or save snapshot
- Parser / resolver / transformation:
  - `EditorSession.explicitLinkTargets(in:)`
  - `WikiLinkExtractor.extractLinks(from:)`
  - `GraphEdgeStore.updateConnections(for:linkedTitles:allVaultURLs:)`
  - separately:
    - `NoteReferenceCatalog.resolveExplicitLinkTarget(...)`
    - used only to publish `targetURLs`
- Cache or index mutation:
  - `GraphEdgeStore.edges`
  - `GraphEdgeStore.reverseEdges`
  - fallback `titleIndex` may rebuild
  - `proven`: `GraphCache` is not written here
- Publish / invalidation:
  - `.quartzReferenceGraphDidChange`
- UI consumers:
  - inspector backlink refresh
  - wiki-link navigation fallback resolution through `GraphEdgeStore.resolveTitle(_:)`
- Stale windows / race windows:
  - `proven`: stored graph edges can be poorer than published `targetURLs` because `GraphEdgeStore` and `NoteReferenceCatalog` do not share one resolver path in production
  - `proven`: this updates only the open/current note; no vault-wide explicit graph recomputation occurs here
- Flow classification:
  - `duplicated`
  - `fragile`

## Flow 7 — Note Rename

- Triggering event:
  - internal/sidebar rename:
    - `SidebarViewModel.rename(at:to:)`
    - `FileSystemVaultProvider.rename(at:to:)`
  - current open note external rename:
    - `NoteFilePresenter.presentedItemDidMove(to:)`
    - `EditorSession.filePresenter(_:didMoveFrom:to:)`
- Authoritative data source:
  - filesystem path mutation
  - canonical note URL after rename
- Parser / resolver / transformation:
  - sidebar rename posts `.quartzSpotlightNoteRelocated`
  - open-note rename additionally posts:
    - `.quartzFilePresenterDidMove`
    - `.quartzSpotlightNoteRelocated`
    - `DomainEventBus.publish(.noteRelocated(...))`
- Cache or index mutation:
  - sidebar file tree refreshed
  - current open editor note URL updated if the note is actively presented
  - embeddings relocate only through `IntelligenceEngineCoordinator.handleFileMove(...)`, which listens to `.quartzFilePresenterDidMove`
  - `proven`: no production path rewrites explicit graph edges on rename
  - `proven`: `ContentViewModel.relocateEmbedding(...)` exists but production search did not find a caller
- Publish / invalidation:
  - `.quartzSpotlightNoteRelocated`
  - `.quartzFilePresenterDidMove` only for current open note
- UI consumers:
  - open editor selection restoration
  - preview / Spotlight relocation
- Stale windows / race windows:
  - `proven`: non-open note rename from sidebar does not feed `IntelligenceEngineCoordinator`, because that coordinator listens for `.quartzFilePresenterDidMove`, not `.quartzSpotlightNoteRelocated`
  - `proven`: `SidebarViewModel` defines `.quartzNoteRenamed`, and observes it, but current production search found no producer
  - `proven`: explicit edges keyed by old URL can remain stale
- Flow classification:
  - `fragile`
  - `partially implemented`

## Flow 8 — Note Move

- Triggering event:
  - `SidebarViewModel.move(at:to:)`
  - `FolderManagementUseCase.move(at:to:)`
  - or current open note external move via `NoteFilePresenter.presentedItemDidMove(to:)`
- Authoritative data source:
  - filesystem path mutation
- Parser / resolver / transformation:
  - move computes new destination path only
  - no relationship-aware transform runs for explicit links
- Cache or index mutation:
  - sidebar file tree refreshed
  - preview / Spotlight relocated
  - current open note path updated if NSFilePresenter sees the move
  - `proven`: `ContentViewModel.relocateEmbedding(...)` exists but production search did not find a caller
  - `proven`: no production caller rewires `GraphEdgeStore` explicit edges or semantic/concept edges on note move
- Publish / invalidation:
  - `.quartzSpotlightNoteRelocated`
  - `.quartzFilePresenterDidMove` only for the currently open note
- UI consumers:
  - current-note shell restoration
  - preview / Spotlight
- Stale windows / race windows:
  - `proven`: moving unopened notes updates shell metadata, but not the live graph actor or embeddings through the sidebar move path
  - `proven`: path-based stable IDs in `VectorEmbeddingService` change on move, so stale embedding entries are likely unless relocation or delete/reindex happens
- Flow classification:
  - `fragile`
  - `partially implemented`

## Flow 9 — Note Delete

- Triggering event:
  - internal/sidebar delete:
    - `SidebarViewModel.delete(at:)`
    - `FileSystemVaultProvider.deleteNote(at:)`
  - current open note external delete:
    - `NoteFilePresenter.accommodatePresentedItemDeletion(...)`
    - `EditorSession.filePresenterWillDelete(_:)`
- Authoritative data source:
  - filesystem removal to trash
- Parser / resolver / transformation:
  - delete itself is file-system only
  - no relationship-aware explicit-edge cleanup step exists in the delete path
- Cache or index mutation:
  - sidebar tree refreshed
  - preview / Spotlight removal
  - `proven`: `ContentViewModel.removeEmbeddingsForNotes(at:)` exists but production search did not find a caller
  - `proven`: `GraphEdgeStore.removeSemanticConnections(for:)` and `removeConcepts(for:)` have no production callers in the current repo
  - `proven`: explicit graph edges are not proactively pruned on delete except when some later source note update overwrites them
- Publish / invalidation:
  - `.quartzSpotlightNotesRemoved`
  - `.quartzFilePresenterWillDelete` only for current open note
  - `DomainEventBus.publish(.noteDeleted(...))` only from `EditorSession.filePresenterWillDelete(_:)`
- UI consumers:
  - current editor selection cleared if deleted note is open
  - preview / Spotlight removal
- Stale windows / race windows:
  - `proven`: sidebar delete of unopened notes does not reach `IntelligenceEngineCoordinator`, because it observes `.quartzFilePresenterWillDelete`, not `.quartzSpotlightNotesRemoved`
  - `proven`: delete can leave stale graph/semantic/concept edges in memory and on disk-derived graph cache
- Flow classification:
  - `fragile`
  - `partially implemented`

## Flow 10 — Note Reopen

- Triggering event:
  - `ContentViewModel.openNote(at:)`
  - `EditorSession.loadNote(at:)`
  - `EditorSession.applyLoadedNoteState(...)`
- Authoritative data source:
  - note body from disk via `vaultProvider.readNote(at:)`
  - restored selection/scroll state if present
- Parser / resolver / transformation:
  - render/highlight rebuild
  - `scheduleAnalysis()`
  - `scheduleOutgoingLinkRefresh()`
  - `refreshExplicitLinkGraphConnectionsIfNeeded(force: true)`
  - `refreshSemanticLinks()`
- Cache or index mutation:
  - `currentText`
  - `InspectorStore.stats`
  - `InspectorStore.headings`
  - `InspectorStore.suggestedLinks`
  - `InspectorStore.outgoingLinks`
  - live graph actor for explicit edges
- Publish / invalidation:
  - `.quartzReferenceGraphDidChange` if explicit targets differ
  - semantic/concept refreshes remain pull-from-store after existing notifications
- UI consumers:
  - editor
  - inspector ToC/stats/outgoing/unlinked/related notes
- Stale windows / race windows:
  - `proven`: reopen refreshes current-note relationships only; it does not rebuild the vault-wide explicit graph
  - `proven`: inspector related notes reflect whatever `semanticEdges` currently hold; if embeddings are stale, reopen does not itself regenerate them
- Flow classification:
  - current note reopen: `authoritative`
  - overall graph freshness: `fragile`

## Flow 11 — App Relaunch

- Triggering event:
  - [`ContentView.runStartupTask()`](/Users/I533181/Developments/Quartz/Quartz/ContentView.swift)
  - [`VaultCoordinator.restoreLastVault(...)`](/Users/I533181/Developments/Quartz/Quartz/VaultCoordinator.swift)
  - [`ContentViewModel.loadVault(_:)`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
  - `restoreSelectedNoteIfNeeded()`
- Authoritative data source:
  - last-vault bookmark
  - SceneStorage/UserDefaults restoration keys
  - `GraphCache`
  - `embeddings.idx`
  - `ai_index.json`
- Parser / resolver / transformation:
  - load file tree
  - prewarm search index
  - load graph cache into `GraphEdgeStore` if fingerprint matches
  - load embeddings index
  - start concept vault scan
  - reopen selected note and rerun note-local relationship refresh
- Cache or index mutation:
  - new `ContentViewModel`, `EditorSession`, `GraphEdgeStore`, `SemanticLinkService`, `KnowledgeExtractionService`
  - `GraphEdgeStore.loadFromCache(...)`
  - `VectorEmbeddingService.loadIndex()`
  - `KnowledgeExtractionService.startVaultScan()` restores concepts into live store
- Publish / invalidation:
  - concept scan posts `.quartzConceptScanProgress` and `.quartzConceptsUpdated`
  - no authoritative explicit-graph invalidation occurs for all notes on relaunch
- UI consumers:
  - app shell
  - selected note editor
  - inspector
- Stale windows / race windows:
  - `proven`: if graph cache is stale or absent, relaunch does not proactively rebuild explicit wiki-link edges across the vault
  - `proven`: graph cache load and note reopen hydrate different relationship systems at different times
- Flow classification:
  - `duplicated`
  - `fragile`

## Flow 12 — Vault Switch

- Triggering event:
  - `VaultCoordinator.openVault(...)`
  - `ContentViewModel.loadVault(_:)`
  - `StartupCoordinator.reset()`
- Authoritative data source:
  - newly selected vault root URL
- Parser / resolver / transformation:
  - old session/services torn down
  - new provider/search/index/embedding/graph services created
  - new file tree loaded
- Cache or index mutation:
  - previous `GraphEdgeStore` discarded with previous `ContentViewModel`
  - new `GraphEdgeStore` starts empty, then optionally loads `GraphCache`
  - new embeddings index loaded
  - new concept scan started
- Publish / invalidation:
  - no typed relationship reset event exported to consumers; reset is implicit in replacement of state owners
- UI consumers:
  - whole workspace shell
  - selected note restoration path after vault load
- Stale windows / race windows:
  - `proven`: relationship systems warm at different times after vault switch
  - `proven`: the new vault can have search/index warm while explicit graph is only cache-loaded or note-local
- Flow classification:
  - `authoritative` for session reset
  - `fragile` for graph completeness

## Flow 13 — Background Indexing / Initial Vault Scan

- Triggering event:
  - initial vault load:
    - `ContentViewModel.loadVault(_:)`
    - `indexAllNotes(in:vaultRoot:embedding:)`
    - `KnowledgeExtractionService.startVaultScan()`
  - post-save / file change:
    - `IntelligenceEngineCoordinator`
- Authoritative data source:
  - file tree
  - file mtimes
  - note bodies from disk
  - `embeddings.idx`
  - `AIIndexState`
- Parser / resolver / transformation:
  - embeddings:
    - `VectorEmbeddingService.indexNote(...)`
  - semantic similarity:
    - `SemanticLinkService.scheduleAnalysis(for:)`
  - concept extraction:
    - `KnowledgeExtractionService.scheduleExtraction(for:)`
    - `startVaultScan()`
- Cache or index mutation:
  - `VaultSearchIndex`
  - preview repository
  - Spotlight index
  - `embeddings.idx`
  - `GraphEdgeStore.semanticEdges`
  - `GraphEdgeStore.conceptEdges`
  - `AIIndexState`
  - `proven`: explicit wiki-link graph is not rebuilt by background indexing
- Publish / invalidation:
  - `.quartzNoteSaved`
  - `.quartzSemanticLinksUpdated`
  - `.quartzConceptsUpdated`
  - `.quartzConceptScanProgress`
- UI consumers:
  - search UI
  - note list preview
  - inspector related notes
  - inspector AI concepts
  - graph view when manually rebuilt/opened
- Stale windows / race windows:
  - `proven`: background indexing keeps embeddings and concepts fresh, but explicit wiki-link graph freshness is separate
  - `plausible but unverified`: concept vault scan restore/update ordering can temporarily rehydrate older concept state before fresh extraction completes
- Flow classification:
  - `duplicated`
  - semantic/concept portions are `heuristic`
  - explicit graph portion is `missing`

## Flow 14 — Semantic-Suggestion Generation

- Triggering event:
  - `ContentViewModel.updateEmbeddingForNote(at:)`
  - `IntelligenceEngineCoordinator.processPendingChanges()`
  - both call `SemanticLinkService.scheduleAnalysis(for:)`
- Authoritative data source:
  - `VectorEmbeddingService`
  - note stable ID from `VectorEmbeddingService.stableNoteID(for:vaultRoot:)`
- Parser / resolver / transformation:
  - `SemanticLinkService.runAnalysis()`
  - `findSimilarNoteIDs(for:limit:threshold:)`
  - `resolveNoteURLs(from:)` scans vault directory and recomputes stable IDs
- Cache or index mutation:
  - `GraphEdgeStore.updateSemanticConnections(for:related:)`
- Publish / invalidation:
  - `.quartzSemanticLinksUpdated`
- UI consumers:
  - `EditorSession.refreshSemanticLinks()`
  - `InspectorStore.relatedNotes`
- Stale windows / race windows:
  - `proven`: semantic edges here are not the same semantic edges shown in graph view, because graph view recomputes its own embedding edges at threshold `0.35`
  - `proven`: semantic edges are in-memory only; they are not explicitly persisted except indirectly if graph view later saves a cache snapshot
  - `proven`: moved/deleted unopened notes can leave stale embedding-driven semantic state because lifecycle cleanup is not uniformly wired
- Flow classification:
  - `heuristic`
  - `duplicated`
  - `fragile`

## Flow 15 — AI-Assisted Concept Extraction Flow

- Triggering event:
  - initial vault scan:
    - `KnowledgeExtractionService.startVaultScan()`
  - on-save/file-change:
    - `KnowledgeExtractionService.scheduleExtraction(for:)`
    - `IntelligenceEngineCoordinator.processPendingChanges()`
- Authoritative data source:
  - note body from disk
  - configured AI provider or `AIExecutionPolicy`
  - persisted `AIIndexState`
- Parser / resolver / transformation:
  - `KnowledgeExtractionService.extractConcepts(for:)`
  - prompt-based extraction into JSON array of concepts
  - `parseConcepts(from:)`
  - concepts normalized to lowercase strings
- Cache or index mutation:
  - `GraphEdgeStore.updateConcepts(for:concepts:)`
  - `AIIndexState.conceptEdges`
  - `AIIndexState.processedTimestamps`
- Publish / invalidation:
  - `.quartzConceptsUpdated`
  - `.quartzConceptScanProgress`
- UI consumers:
  - `EditorSession.refreshConcepts()`
  - `InspectorStore.aiConcepts`
  - `KnowledgeGraphView.addConceptHubNodes()`
- Stale windows / race windows:
  - `proven`: this is concept extraction, not explicit note linking
  - `proven`: the same `semanticAutoLinkingEnabled` setting gates both note-note semantic similarity and concept extraction, even though they are different systems
  - `proven`: graph cache cannot round-trip concept edge type because `GraphCache.CachedEdge` does not persist `isConcept`
  - `proven`: delete/move cleanup for concept edges is not wired in production
- Flow classification:
  - `heuristic`
  - `fragile`

## Cross-Flow Conclusions

1. `proven`: explicit links, outgoing links, backlinks, unlinked mentions, semantic related notes, graph-view edges, and AI concepts do not flow through one pipeline.
2. `proven`: current-note editor surfaces are the most authoritative relationship surfaces in the app.
3. `proven`: graph persistence is graph-view-owned, not live-graph-owned.
4. `proven`: rename/move/delete handling is strongest for shell metadata, weaker for embeddings, and weakest for explicit graph integrity.
5. `proven`: “semantic linking” in shipped behavior is a mixture of embeddings, heuristic mention matching, and AI concept extraction, not one unified system.
