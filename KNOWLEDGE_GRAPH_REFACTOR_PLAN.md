# Knowledge Graph Refactor Plan

Status: staged review plan complete. This document remains implementation-free. It defines fix direction only.

## Review Boundary

This plan is based on:

- [KNOWLEDGE_GRAPH_DEEP_REVIEW.md](/Users/I533181/Developments/Quartz/KNOWLEDGE_GRAPH_DEEP_REVIEW.md)
- [KNOWLEDGE_GRAPH_FLOW_MAP.md](/Users/I533181/Developments/Quartz/KNOWLEDGE_GRAPH_FLOW_MAP.md)

No implementation should start before the first milestone is explicitly approved.

## Refactor Intent

The current system should not be treated as one graph that needs “cleanup.”

`proven`: the repo currently contains several overlapping relationship systems:

- explicit-link interpretation
- live explicit graph edges
- persisted graph snapshot
- graph-view local rebuild
- embedding-based related-note edges
- AI concept extraction

The refactor direction should therefore be:

1. define one canonical relationship model for explicit note-to-note edges
2. separate explicit relationships from semantic similarity and AI concepts
3. make all consumers read from explicit authoritative producers rather than rebuilding locally
4. make lifecycle invalidation explicit for save/edit/rename/move/delete/relaunch/vault switch
5. narrow product language so it stops overclaiming

## Safe-In-Place vs Structural vs Replace

### Safe in place

- wire `GraphEdgeStore` to a canonical resolver if that store remains part of the architecture
- reroute consumers onto one explicit reference interpretation path
- repair lifecycle invalidation for rename/move/delete
- separate settings and labels for semantic related notes vs AI concepts
- remove dead/unused notification paths and unused helper methods

### Refactor required

- unify explicit relationship ownership
- unify persistence writer/reader ownership
- make graph view consume authoritative relationship state instead of rebuilding its own
- introduce one relationship refresh bus with typed payloads and deterministic ordering

### Replace required

- current graph-cache authorship model if graph view continues to be only cache writer
- current product-level “semantic linking” umbrella if the implementation remains hybrid and non-unified

## Staged Milestone Outline

### KG0 — Product Truth And Vocabulary

- Goal:
  - stop overclaiming and establish strict relationship terminology
- Scope:
  - settings copy
  - inspector labels where misleading
  - graph legend naming
- Outcome:
  - users can distinguish:
    - explicit links
    - related notes
    - unlinked mentions
    - AI concepts

### KG1 — Canonical Note Identity

- Goal:
  - define one note identity used by all relationship systems
- Scope:
  - explicit link resolution
  - live graph edges
  - semantic note-note edges
  - graph cache nodes
- Expected direction:
  - canonical note URL for persisted/runtime note identity
  - stable derived ID only where a vector index truly requires it

### KG2 — Explicit Reference Pipeline Unification

- Goal:
  - make one system authoritative for explicit note-to-note relationships
- Scope:
  - `WikiLinkExtractor`
  - `NoteReferenceCatalog`
  - `GraphEdgeStore`
  - `BacklinkUseCase`
  - outgoing links
- Expected direction:
  - one parse
  - one resolve
  - one canonical explicit-reference payload

### KG3 — Lifecycle Invalidation And Repair

- Goal:
  - make save/edit/rename/move/delete/relaunch/vault-switch relationship updates deterministic
- Scope:
  - `EditorSession`
  - `SidebarViewModel`
  - `ContentViewModel`
  - `NoteFilePresenter`
  - background services
- Expected direction:
  - all relationship-affecting lifecycle events publish typed, canonical invalidations

### KG4 — Persistence Ownership

- Goal:
  - make persisted relationship state authored by the same owner that live consumers trust
- Scope:
  - `GraphCache`
  - `GraphEdgeStore`
  - graph-view cache usage
- Expected direction:
  - graph cache should not depend on graph view being opened

### KG5 — Semantic Similarity And AI Concepts Separation

- Goal:
  - split note-note similarity from AI concept extraction cleanly
- Scope:
  - `SemanticLinkService`
  - `KnowledgeExtractionService`
  - settings
  - graph rendering
- Expected direction:
  - separate storage
  - separate toggles
  - separate UI language

### KG6 — Consumer Convergence

- Goal:
  - make inspector, graph view, and navigation consumers read the same canonical relationship state
- Scope:
  - inspector panels
  - graph view
  - relationship navigation
- Expected direction:
  - remove local graph-view edge rebuilding from note bodies

### KG7 — Scale / Background Integrity

- Goal:
  - support larger vaults without stale or contradictory relationship state
- Scope:
  - incremental rebuild strategy
  - cache versioning
  - background scan ordering
  - performance budgets

## Top 20 Blockers

### 1. Live explicit graph resolver is not wired to canonical identity

- Severity:
  - critical
- Symptom:
  - live explicit graph edges can resolve fewer targets than inspector explicit-reference consumers
- Root cause:
  - `GraphEdgeStore.setIdentityResolver(_:)` exists, but production search did not find a production caller
- Affected files:
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - [GraphIdentityResolver.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
- Affected surfaces:
  - live explicit edges
  - backlinks
  - wiki-link navigation fallback
- User impact:
  - link resolution trust breaks on aliases, titles, and path-qualified links
- Architectural impact:
  - explicit graph and explicit reference catalog cannot converge
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG1

### 2. Persisted graph cache is authored by graph view, not by the live graph owner

- Severity:
  - critical
- Symptom:
  - persisted graph state depends on whether graph view was built
- Root cause:
  - `ContentViewModel.loadVault(_:)` reads `GraphCache`
  - `GraphViewModel.buildGraph(...)` writes `GraphCache`
  - no production caller found for `GraphEdgeStore.exportForCache()`
- Affected files:
  - [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- Affected surfaces:
  - app relaunch
  - graph load
  - backlink warm state
- User impact:
  - graph can feel stale or missing until graph view is rebuilt
- Architectural impact:
  - persistence ownership is wrong
- Change type:
  - refactor-required
- Recommended milestone:
  - KG4

### 3. Rename and move do not repair explicit graph state

- Severity:
  - critical
- Symptom:
  - moved or renamed notes can keep stale incoming/outgoing graph edges
- Root cause:
  - rename/move flows update shell metadata but do not rewrite explicit graph relationships
- Affected files:
  - [SidebarViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift)
  - [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- Affected surfaces:
  - backlinks
  - outgoing links
  - graph view
- User impact:
  - relationship trust breaks after file operations
- Architectural impact:
  - note identity drift is uncontained
- Change type:
  - refactor-required
- Recommended milestone:
  - KG3

### 4. Delete lifecycle leaves stale graph, semantic, and concept edges

- Severity:
  - critical
- Symptom:
  - deleted notes can still be represented in relationship systems
- Root cause:
  - delete flows remove Spotlight/preview state, but no production caller removes explicit, semantic, or concept edges comprehensively
- Affected files:
  - [SidebarViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift)
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
- Affected surfaces:
  - graph view
  - related notes
  - AI concepts
- User impact:
  - stale relationships remain visible after deletion
- Architectural impact:
  - lifecycle invalidation is incomplete
- Change type:
  - refactor-required
- Recommended milestone:
  - KG3

### 5. Non-open note move/delete bypasses Intelligence Engine cleanup

- Severity:
  - critical
- Symptom:
  - embeddings and AI-derived relationship state may remain stale for notes changed via sidebar operations
- Root cause:
  - `IntelligenceEngineCoordinator` listens to `.quartzFilePresenterDidMove` and `.quartzFilePresenterWillDelete`
  - sidebar operations publish `.quartzSpotlightNoteRelocated` / `.quartzSpotlightNotesRemoved`
- Affected files:
  - [IntelligenceEngineCoordinator.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/IntelligenceEngineCoordinator.swift)
  - [SidebarViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Sidebar/SidebarViewModel.swift)
- Affected surfaces:
  - embeddings
  - related notes
  - AI concepts
- User impact:
  - stale semantic and concept state after sidebar file operations
- Architectural impact:
  - lifecycle events do not share one bus
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG3

### 6. Graph view rebuilds explicit edges independently from the live graph

- Severity:
  - critical
- Symptom:
  - graph view can disagree with inspector/live graph state
- Root cause:
  - `GraphViewModel.buildGraph(...)` re-reads notes and rebuilds explicit edges locally
- Affected files:
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- Affected surfaces:
  - graph view
  - persisted graph cache
- User impact:
  - graph feels like a different product than the inspector
- Architectural impact:
  - duplicate relationship ownership
- Change type:
  - replace-required
- Recommended milestone:
  - KG6

### 7. Semantic similarity has two different thresholds and two different producers

- Severity:
  - critical
- Symptom:
  - “related notes” and graph semantic links disagree
- Root cause:
  - `SemanticLinkService` uses threshold `0.82`
  - `GraphViewModel.buildGraph(...)` uses threshold `0.35`
- Affected files:
  - [SemanticLinkService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift)
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- Affected surfaces:
  - inspector related notes
  - graph view
- User impact:
  - users cannot predict what “semantic” means
- Architectural impact:
  - one feature name covers two incompatible systems
- Change type:
  - refactor-required
- Recommended milestone:
  - KG5

### 8. Graph cache loses concept edge type

- Severity:
  - high
- Symptom:
  - concept hubs cannot round-trip through graph cache faithfully
- Root cause:
  - `GraphCache.CachedEdge` has no `isConcept`
- Affected files:
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- Affected surfaces:
  - graph cache
  - graph view
- User impact:
  - graph persistence fidelity is weak for AI concepts
- Architectural impact:
  - graph schema is lossy
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG4

### 9. One setting gates both semantic related notes and AI concept extraction

- Severity:
  - high
- Symptom:
  - disabling “semantic auto-linking” also disables concept extraction
- Root cause:
  - both services read `semanticAutoLinkingEnabled`
- Affected files:
  - [SemanticLinkService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift)
  - [KnowledgeExtractionService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)
  - [AISettingsView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Settings/AISettingsView.swift)
- Affected surfaces:
  - settings
  - related notes
  - AI concepts
- User impact:
  - settings behavior is misleading
- Architectural impact:
  - unrelated systems are coupled by one flag
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG0

### 10. Graph/reference refresh still relies on NotificationCenter fan-out

- Severity:
  - high
- Symptom:
  - ordering and refresh guarantees are hard to reason about
- Root cause:
  - typed event bus exists but relationship flows still use NotificationCenter as the real transport
- Affected files:
  - [DomainEventBus.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Events/DomainEventBus.swift)
  - [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - [InspectorSidebar.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift)
  - [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
- Affected surfaces:
  - all relationship refresh consumers
- User impact:
  - intermittent staleness is hard to eliminate
- Architectural impact:
  - hidden coupling remains
- Change type:
  - refactor-required
- Recommended milestone:
  - KG3

### 11. Backlinks are computed from a merge, not one authoritative model

- Severity:
  - high
- Symptom:
  - backlink trust depends on scan-vs-live-graph reconciliation
- Root cause:
  - `BacklinkUseCase` merges scanned and live graph results
- Affected files:
  - [BacklinkUseCase.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
- Affected surfaces:
  - inspector backlinks
- User impact:
  - backlinks can feel inconsistent after edits or file operations
- Architectural impact:
  - hybrid merge masks upstream divergence
- Change type:
  - refactor-required
- Recommended milestone:
  - KG2

### 12. Published target invalidation can be richer than stored graph edges

- Severity:
  - high
- Symptom:
  - inspector refresh can behave as if a relationship exists that the live graph actor does not actually store
- Root cause:
  - `EditorSession.refreshExplicitLinkGraphConnections(...)` publishes `targetURLs` resolved through `NoteReferenceCatalog` after separately updating `GraphEdgeStore`
- Affected files:
  - [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - [NoteReferenceCatalog.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- Affected surfaces:
  - backlink refresh
  - live graph integrity
- User impact:
  - inspector and graph can disagree
- Architectural impact:
  - invalidation payload is not derived from one stored truth
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG2

### 13. File-tree changes do not recompute all current-note relationships

- Severity:
  - high
- Symptom:
  - open-note relationships can lag after note catalog changes
- Root cause:
  - `EditorSession.fileTree.didSet` only refreshes wiki-link picker suggestions
- Affected files:
  - [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- Affected surfaces:
  - outgoing links
  - unlinked mentions
  - explicit graph notifications
- User impact:
  - relationship UI can lag until next edit/reopen
- Architectural impact:
  - note-catalog invalidation is partial
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG3

### 14. Graph view does not subscribe to live relationship invalidations

- Severity:
  - high
- Symptom:
  - graph view can stay stale while open
- Root cause:
  - current graph view rebuild is keyed only on `.task(id: semanticAutoLinkingEnabled)`
- Affected files:
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- Affected surfaces:
  - graph view
- User impact:
  - graph feels detached from current editor state
- Architectural impact:
  - consumer convergence is impossible without explicit subscriptions
- Change type:
  - refactor-required
- Recommended milestone:
  - KG6

### 15. Multiple note identity schemes are active at once

- Severity:
  - high
- Symptom:
  - rename/move semantics differ across explicit graph, embeddings, graph nodes, and concept hubs
- Root cause:
  - canonical URL, SHA256-of-path, deterministic UUID-from-relative-path, and synthetic graph-node IDs all coexist
- Affected files:
  - [NoteDocument.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift)
  - [GraphIdentityResolver.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
  - [VectorEmbeddingService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift)
  - [KnowledgeGraphView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- Affected surfaces:
  - all relationship systems
- User impact:
  - rename/move correctness is hard to trust
- Architectural impact:
  - impossible to reason about one graph
- Change type:
  - refactor-required
- Recommended milestone:
  - KG1

### 16. Normalization logic is duplicated and inconsistent

- Severity:
  - medium
- Symptom:
  - some note references resolve in one surface and fail in another
- Root cause:
  - normalization exists independently in `GraphIdentityResolver`, `NoteReferenceCatalog`, and `GraphEdgeStore` fallback
- Affected files:
  - [GraphIdentityResolver.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
  - [NoteReferenceCatalog.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
  - [GraphCache.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- Affected surfaces:
  - link resolution
  - backlinks
  - live graph
- User impact:
  - relationship resolution feels inconsistent
- Architectural impact:
  - canonical reference interpretation is impossible
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG1

### 17. Explicit graph is not rebuilt by background indexing

- Severity:
  - medium
- Symptom:
  - search/embeddings/concepts can be fresh while explicit graph is stale
- Root cause:
  - `IntelligenceEngineCoordinator` only updates embeddings, semantic edges, and concepts
- Affected files:
  - [IntelligenceEngineCoordinator.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/IntelligenceEngineCoordinator.swift)
  - [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
- Affected surfaces:
  - graph view
  - backlinks
  - relaunch freshness
- User impact:
  - background “indexing” does not mean all relationships are fresh
- Architectural impact:
  - indexing model is incomplete
- Change type:
  - refactor-required
- Recommended milestone:
  - KG4

### 18. There is no AI-assisted explicit note-linking flow despite semantic branding

- Severity:
  - medium
- Symptom:
  - product language can imply richer semantic linking than the repo actually implements
- Root cause:
  - explicit link suggestions are heuristic mention matching, not embeddings or AI generation
- Affected files:
  - [LinkSuggestionService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
  - [AISettingsView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Settings/AISettingsView.swift)
- Affected surfaces:
  - inspector suggested links
  - settings
  - knowledge graph positioning
- User impact:
  - users overtrust how “smart” the link system really is
- Architectural impact:
  - future work can start from the wrong premise
- Change type:
  - replace-required for product language, not necessarily code
- Recommended milestone:
  - KG0

### 19. Fuzzy link resolution exists but is not part of production flows

- Severity:
  - low
- Symptom:
  - code suggests typo-tolerant resolution capability that users do not actually get
- Root cause:
  - `GraphIdentityResolver.resolve(_:fuzzy:)` exists, but no production caller was found using `fuzzy: true`
- Affected files:
  - [GraphIdentityResolver.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
- Affected surfaces:
  - none proven in production
- User impact:
  - low today; mainly a review/truthfulness issue
- Architectural impact:
  - dead complexity
- Change type:
  - safe-in-place
- Recommended milestone:
  - KG0

### 20. Graph cache, embeddings, and AI index warm independently on relaunch

- Severity:
  - low
- Symptom:
  - different relationship surfaces become “ready” at different times after launch
- Root cause:
  - relaunch hydrates graph cache, embeddings, concepts, and current-note live state through separate tasks
- Affected files:
  - [ContentView.swift](/Users/I533181/Developments/Quartz/Quartz/ContentView.swift)
  - [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
  - [StartupCoordinator.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Vault/StartupCoordinator.swift)
- Affected surfaces:
  - app relaunch
  - inspector
  - graph view
- User impact:
  - relationship trust depends on timing after launch
- Architectural impact:
  - no single readiness boundary exists for relationship state
- Change type:
  - refactor-required
- Recommended milestone:
  - KG7

## De-Scope Candidates

If the codebase cannot converge quickly, these capabilities should be renamed or narrowed before new graph work starts:

- “semantic linking” as a blanket term
- any implication that unlinked mentions are AI-generated
- any implication that graph view is the same source of truth as inspector relationships

## Plan Summary

1. KG0:
   - fix terminology and settings truth first
2. KG1:
   - unify note identity and normalization
3. KG2:
   - unify explicit reference interpretation
4. KG3:
   - repair lifecycle invalidation
5. KG4:
   - move persistence ownership to the authoritative relationship owner
6. KG5:
   - separate semantic similarity from AI concepts
7. KG6:
   - make graph view consume shared state, not rebuild locally
8. KG7:
   - harden startup/background-scale behavior
