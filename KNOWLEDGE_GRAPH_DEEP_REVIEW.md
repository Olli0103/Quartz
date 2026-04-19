# Knowledge Graph Deep Review

Status: PHASE 1 discovery complete. PHASE 2 flow mapping and PHASE 3 integrity/divergence audit are now appended below. This document remains review-only.

## Review Rules

- Scope source of truth: current repo state only
- Review mode only: no fixes implemented in this pass
- Claim status markers used throughout:
  - `proven`
  - `plausible but unverified`
  - `unknown`

## Phase 1 Discovery Summary

### Bottom-line architecture

`proven`: Quartz does not have one unified knowledge-graph or relationship model.

It has at least six overlapping relationship/index systems:

1. Persisted graph cache in [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
   - `GraphCache`
   - file: `{vault}/.quartz/graph-cache.json`
   - stores `CachedGraph.nodes`, `CachedGraph.edges`, `fingerprint`

2. Live in-memory relationship actor in [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
   - `GraphEdgeStore`
   - `edges`
   - `reverseEdges`
   - `semanticEdges`
   - `conceptEdges`
   - `noteConcepts`
   - `titleIndex`
   - optional `identityResolver`

3. Inspector current-note relationship model
   - [`NoteReferenceCatalog.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
   - [`BacklinkUseCase.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
   - [`LinkSuggestionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
   - [`EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
   - [`InspectorStore.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorStore.swift)

4. Graph-view build pipeline
   - [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
   - `GraphViewModel.buildGraph(...)`
   - local `GraphIdentityResolver`
   - local note-body scans with `WikiLinkExtractor`
   - optional embedding-based graph edges
   - optional concept hub nodes from `GraphEdgeStore`

5. Embedding/vector similarity index
   - [`VectorEmbeddingService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift)
   - file: `{vault}/.quartz/embeddings.idx`
   - on-device `NLEmbedding` vectors

6. AI concept extraction state
   - [`KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)
   - `AIIndexState`
   - file: `{vault}/.quartz/ai_index.json`

These are related, but they are not one authoritative model.

### What the app currently calls “semantic linking”

`proven`: the repo implements a hybrid, not one unified semantic-linking system.

Current implementation splits into:

- explicit-link graph
  - wiki-link parsing and note-to-note edges
- title/alias/path matching
  - used for link resolution and unlinked mention suggestions
- heuristic mention matching
  - `LinkSuggestionService.suggestLinks(...)`
- embedding/vector similarity
  - `SemanticLinkService`
  - `VectorEmbeddingService.findSimilarNoteIDs(...)`
  - graph-view optional semantic edges
- AI concept extraction
  - `KnowledgeExtractionService`
  - note-to-concept, not note-to-note explicit linking

It is not one coherent “semantic linking” engine.

It is also not purely AI-generated linking:

- unlinked mentions are not embedding-based
- outgoing links are not embedding-based
- backlinks are not embedding-based
- manual `[[...]]` linking is not AI-based

### Hard truth on the product label

`proven`: if the product implies that all relationship features are “semantic linking,” that overstates the implementation.

Repo-backed classification:

- inspector `Related Notes`
  - embedding/vector similarity
- graph-view dashed AI edges
  - embedding/vector similarity
- unlinked mentions
  - title/alias/path term matching with word-boundary heuristics
- backlinks/outgoing links
  - explicit wiki-link interpretation
- AI concepts
  - concept extraction, not note-to-note semantic linking

## Core Types, Files, and State Owners

### 1. Explicit link parsing

Primary parser:

- [`WikiLinkExtractor.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/Markdown/WikiLinkExtractor.swift)
  - `WikiLinkExtractor.extractLinks(from:)`
  - `WikiLinkExtractor.linkRanges(in:)`
  - `WikiLink.target`
  - `WikiLink.displayText`
  - `WikiLink.heading`

Behavior:

- parses `[[Note]]`
- parses `[[Note|Alias]]`
- parses `[[Note#Heading]]`
- skips fenced code blocks and inline code

Trust level:

- explicit syntax parsing itself: `correct but fragile`
  - parser is simple and direct
  - it is not the same thing as graph identity resolution

### 2. Canonical note identity

Primary runtime note identity:

- [`NoteDocument.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift)
  - `CanonicalNoteIdentity`
  - `CanonicalNoteIdentity.canonicalFileURL(for:)`
  - note runtime identity is standardized file URL

Important consequence:

- rename or move changes the runtime note identity intentionally

Additional identity systems also exist:

- [`GraphIdentityResolver.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
  - `NoteIdentity`
  - filename/title/aliases/tags identity record
  - `stableID(for:)` returns SHA256 hash of path string
- [`VectorEmbeddingService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift)
  - `stableNoteID(for:vaultRoot:)` returns deterministic UUID from relative path
- [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
  - graph node IDs are `URL.absoluteString` for note nodes
  - graph concept-node IDs are synthetic `concept:<name>` strings

Identity assessment:

- multiple note identity models: `proven`
- one single authoritative identity across all graph surfaces: `ruled out`

### 3. Graph identity resolution

Resolver:

- [`GraphIdentityResolver.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
  - actor
  - `register(_:)`
  - `unregister(_:)`
  - `rename(from:to:newFilename:frontmatterTitle:existingAliases:tags:)`
  - `resolve(_:, fuzzy:)`
  - `notesWithTag(_:)`
  - `identity(for:)`
  - internal indexes:
    - `identities`
    - `nameIndex`
    - `pathIndex`
    - `tagIndex`

Supported resolution inputs:

- filename
- frontmatter title
- aliases
- folder-qualified path suffixes
- optional fuzzy matching

Important architecture fact:

- production uses of `GraphIdentityResolver` are not global
- `proven`: search across production sources shows no production call to `GraphEdgeStore.setIdentityResolver(_:)`
- result: the live `GraphEdgeStore` is not wired to this richer resolver in normal app execution

### 4. Live explicit edge store

Live store:

- [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - `GraphEdgeStore`
  - `updateConnections(for:linkedTitles:allVaultURLs:)`
  - `backlinks(for:)`
  - `resolveTitle(_:)`
  - `rebuildAll(connections:allVaultURLs:)`
  - `loadFromCache(_:, allVaultURLs:)`
  - `exportForCache()`

State:

- `edges: [URL: [URL]]`
- `reverseEdges: [URL: Set<URL>]`
- `semanticEdges: [URL: [URL]]`
- `conceptEdges: [String: Set<URL>]`
- `noteConcepts: [URL: [String]]`
- fallback `titleIndex`

Resolution behavior:

- if `identityResolver` exists, `resolveWikiLink(_:)` uses it
- otherwise uses lowercased basename-only `titleIndex`

Critical discovery:

- `proven`: in production, `GraphEdgeStore` normally runs on fallback title resolution because the resolver is not wired in
- that means live explicit graph edges are simpler than `NoteReferenceCatalog` resolution

### 5. Persisted graph cache

Cache file:

- [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - `{vault}/.quartz/graph-cache.json`

Persistence model:

- `GraphCache.computeFingerprint(for:)`
- `GraphCache.loadIfValid(fingerprint:)`
- `GraphCache.save(_:)`

Writer/reader split:

- reader into live graph store on startup:
  - [`ContentViewModel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
  - `loadVault(_:)`
  - loads `GraphCache`
  - if fingerprint matches, calls `graphEdgeStore.loadFromCache(...)`
- writer:
  - [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
  - `GraphViewModel.buildGraph(...)`
  - builds its own node/edge set
  - then saves `GraphCache.CachedGraph`

Critical discovery:

- `proven`: production does not persist `GraphEdgeStore` directly
- `proven`: `GraphEdgeStore.exportForCache()` exists but production search did not reveal a production caller
- `proven`: persisted graph cache is authored by the graph-view build pipeline, not by the live editor/link graph pipeline
- `proven`: `GraphCache.CachedEdge` has only `from`, `to`, and `isSemantic`
- `proven`: graph-view `GraphEdge` also has `isConcept`, but that flag is not persisted in `GraphCache.CachedEdge`

Implication:

- the persisted graph is a graph-view snapshot, not necessarily the same model as live inspector relationships
- concept-hub edges cannot round-trip through the graph cache without losing their edge type

### 6. Outgoing links

Current outgoing-link pipeline:

- [`EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - `scheduleOutgoingLinkRefresh()`
- [`NoteReferenceCatalog.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
  - `resolvedExplicitReferences(in:graphEdgeStore:using:)`
- [`InspectorStore.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorStore.swift)
  - `OutgoingLinkItem`
  - `setOutgoingLinks(_:)`
- UI:
  - [`InspectorSidebar.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift)
  - [`OutgoingLinksPanel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/OutgoingLinksPanel.swift)

Authority:

- live editor text `EditorSession.currentText`
- current `fileTree`
- `NoteReferenceCatalog`

Notable behavior:

- outgoing links are current-note-local
- deduplicated by target note URL
- derived from live current text, not from persisted graph cache

### 7. Backlinks

Backlink computation:

- [`BacklinkUseCase.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
  - `findBacklinks(to:in:)`
  - `scanForBacklinks(...)`
  - `liveGraphBacklinks(...)`

Inputs:

- full vault file tree via `vaultProvider.loadFileTree(at:)`
- vault note bodies via `vaultProvider.readNote(at:)`
- `NoteReferenceCatalog`
- optional `GraphEdgeStore`

Merge model:

- scanned backlinks from note-body explicit reference resolution
- live graph backlinks from `graphEdgeStore.backlinks(for:)`
- merged by canonical source URL
- prefers richer payload when `referenceRange`/context exists

Authority:

- there is no single source
- it is a merged hybrid of vault scan plus live graph store

### 8. Unlinked mentions

Unlinked mention pipeline:

- [`LinkSuggestionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
  - `suggestLinks(for:currentNoteURL:allNotes:graphEdgeStore:)`
- call site:
  - [`EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - `scheduleAnalysis()`
- UI:
  - [`InspectorSidebar.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift)

Mechanics:

- builds `NoteReferenceCatalog`
- resolves explicit references first
- excludes their `noteURL`s and `matchRange`s
- then scans current note text for note `searchTerms`
- `searchTerms` come from:
  - file name
  - frontmatter title
  - frontmatter aliases
- requires word boundaries
- term length floor: 3
- one suggestion per note URL

Classification:

- semantic similarity: `ruled out`
- embedding/vector similarity: `ruled out`
- AI-generated suggestion: `ruled out`
- title/alias/path mention matching: `proven`

### 9. “Related Notes” in inspector

Inspector related-notes pipeline:

- refresh source:
  - [`EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
  - `startSemanticLinkObserver()`
  - `refreshSemanticLinks()`
- storage:
  - `GraphEdgeStore.semanticEdges`
- producer:
  - [`SemanticLinkService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift)
  - `scheduleAnalysis(for:)`
  - `runAnalysis()`

Mechanics:

- semantic link service uses `VectorEmbeddingService.findSimilarNoteIDs(...)`
- threshold is `0.82`
- limit is `5`
- result URLs are resolved by scanning the vault directory and recomputing `stableNoteID`
- semantic edges are in-memory only
- notification `.quartzSemanticLinksUpdated` refreshes inspector related notes

Classification:

- vector/embedding similarity: `proven`
- NLP/entity extraction: `ruled out`
- graph-neighbor heuristic: `ruled out`
- explicit-link inference: `ruled out`

### 10. Knowledge graph view

Graph-view builder:

- [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
  - `GraphViewModel.buildGraph(...)`
  - local `identityResolver`
  - local note reads via `vaultProvider.readNote(at:)`
  - local `WikiLinkExtractor`

What counts as nodes:

- note nodes
  - `GraphNode`
  - ID = `url.absoluteString`
- concept hub nodes
  - ID = `concept:<concept>`
  - URL = placeholder `/concept/<concept>`

What counts as edges:

- explicit wiki-link edges
  - built by scanning note bodies in `buildGraph(...)`
- semantic AI edges
  - built directly in `buildGraph(...)` via `embedding.findSimilarNoteIDs(...)`
  - threshold `0.35`
- concept hub edges
  - built in `addConceptHubNodes()`
  - sourced from `GraphEdgeStore.significantConcepts(minNotes: 2)`

Critical discovery:

- `proven`: graph view does not use `GraphEdgeStore.edges` as its primary source for explicit link edges
- `proven`: graph view rebuilds explicit edges independently from note bodies
- `proven`: graph view semantic edges are computed independently from `SemanticLinkService`
- `proven`: graph view semantic threshold (`0.35`) differs radically from inspector related-notes threshold (`0.82`)

This is two separate semantic-edge systems sharing the same embedding service but not the same threshold or cache.

### 11. AI concept graph

Concept pipeline:

- [`KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)
  - persisted `AIIndexState`
  - `scheduleExtraction(for:)`
  - `startVaultScan()`
  - `restoreConceptEdgesFromState()`
  - `extractConcepts(for:)`
  - `updateConceptsAndState(for:concepts:)`
- in-memory storage:
  - `GraphEdgeStore.conceptEdges`
  - `GraphEdgeStore.noteConcepts`
- inspector consumer:
  - `EditorSession.refreshConcepts()`
  - `InspectorStore.aiConcepts`
- graph-view consumer:
  - `GraphViewModel.addConceptHubNodes()`

Classification:

- AI-generated concept extraction: `proven`
- note-to-note semantic linking: `ruled out`

Critical discovery:

- `proven`: both [`SemanticLinkService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift) and [`KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift) gate themselves on the same `UserDefaults` / `@AppStorage` key: `semanticAutoLinkingEnabled`
- this setting is named as if it controls note-to-note semantic links, but it also gates AI concept extraction

### 12. Background indexing and AI coordinator

Coordinator:

- [`IntelligenceEngineCoordinator.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/IntelligenceEngineCoordinator.swift)
  - observes:
    - `.quartzFilePresenterDidChange`
    - `.quartzFilePresenterDidMove`
    - `.quartzFilePresenterWillDelete`
    - `.quartzNoteSaved`
  - batches `pendingURLs`
  - indexes embeddings via `VectorEmbeddingService`
  - then schedules:
    - `SemanticLinkService.scheduleAnalysis(for:)`
    - `KnowledgeExtractionService.scheduleExtraction(for:)`

Scope limitation:

- this coordinator manages embeddings, semantic related-note edges, and AI concept extraction
- it does not rebuild the explicit wiki-link graph across the whole vault

## Proven Architectural Divergences

### Divergence 1: live graph store vs inspector explicit-reference model

`proven`

- `GraphEdgeStore.updateConnections(...)` resolves linked titles through the live store resolver/fallback
- in production, that is fallback basename matching unless a resolver is manually set
- `NoteReferenceCatalog.resolveExplicitLinkTarget(...)` has richer fallback matching:
  - title
  - alias
  - path suffix
  - normalization
- `EditorSession.refreshExplicitLinkGraphConnections(...)` updates `GraphEdgeStore` with raw linked titles, then separately resolves `targetURLs` for `.quartzReferenceGraphDidChange` via `NoteReferenceCatalog`

Result:

- notification target URLs can be richer than the actual stored live graph edges
- backlinks invalidation and live graph edge state can diverge

### Divergence 2: persisted graph cache writer vs live graph reader

`proven`

- startup reader into `GraphEdgeStore` is `ContentViewModel.loadVault(_:)`
- production writer is `GraphViewModel.buildGraph(...)`
- the graph cache is not written by live editor/link updates

Result:

- persisted graph state is graph-view-derived, not editor-graph-derived
- if graph view is never opened, persisted graph may remain stale or absent

### Divergence 3: graph-view semantic edges vs inspector semantic edges

`proven`

- inspector semantic edges:
  - `SemanticLinkService`
  - threshold `0.82`
  - persisted nowhere except transient in-memory `GraphEdgeStore.semanticEdges`
- graph-view semantic edges:
  - `GraphViewModel.buildGraph(...)`
  - threshold `0.35`
  - recomputed on graph build

Result:

- “related notes” and “semantic graph links” are not the same relationship set

### Divergence 4: multiple normalization systems

`proven`

Normalization exists in at least three places:

- [`GraphIdentityResolver.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
  - `normalize(_:)`
- [`NoteReferenceCatalog.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
  - `normalize(_:)`
- [`GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
  - fallback `titleIndex` lowercased basename only

These are not equivalent.

### Divergence 5: concept graph is stored in the same actor but not the same edge type

`proven`

- `GraphEdgeStore` mixes:
  - explicit note-to-note edges
  - semantic note-to-note edges
  - concept string to note edges
- graph cache encoding does not carry `isConcept`
- graph-view `GraphEdge` does carry `isConcept`

This is not one clean graph schema.

### Divergence 6: typed event bus exists, but graph/reference flows still rely on NotificationCenter

`proven`

- [`DomainEventBus.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Events/DomainEventBus.swift) defines:
  - `graphUpdated`
  - `semanticLinksDiscovered`
  - `aiAnalysisCompleted`
- production search in this pass found the type definitions, but no production subscribers and no graph-flow ownership through the typed bus
- actual graph/reference refresh still routes primarily through `NotificationCenter`:
  - `.quartzNoteSaved`
  - `.quartzReferenceGraphDidChange`
  - `.quartzSemanticLinksUpdated`
  - `.quartzConceptsUpdated`
  - file-presenter notifications

Result:

- typed domain events are not the authoritative relationship refresh bus

## Automatic Semantic Linking: Honest Classification

### What it is

Current repo implementation is:

- `hybrid`

More precise split:

- note-to-note semantic similarity:
  - `embedding/vector similarity`
- inspector link suggestions:
  - `title/alias matching`
  - `mention matching`
- AI concept extraction:
  - `AI-assisted generation`
  - but not explicit note-to-note linking

### What it is not

`proven`

The repo does not show one unified system that does all of the following from a single semantic model:

- detect unlinked mentions semantically
- convert them into suggested note targets using embeddings
- merge those results with explicit link graph edges
- keep graph view, inspector relationships, backlinks, and unlinked mentions on one identity model

That stronger interpretation is not present.

## File-Level Discovery Map

### Graph / identity / reference core

- [`QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/GraphCache.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Graph/GraphIdentityResolver.swift)
- [`QuartzKit/Sources/QuartzKit/Data/Markdown/WikiLinkExtractor.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/Markdown/WikiLinkExtractor.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/NoteReferenceCatalog.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift)

### Editor / inspector consumers

- [`QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorStore.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorStore.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Inspector/InspectorSidebar.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/Editor/BacklinksPanel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/BacklinksPanel.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/Editor/OutgoingLinksPanel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/OutgoingLinksPanel.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteLinkPicker.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/NoteLinkPicker.swift)

### Graph / AI / indexing

- [`QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/VectorEmbeddingService.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/SemanticLinkService.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/AI/IntelligenceEngineCoordinator.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/IntelligenceEngineCoordinator.swift)
- [`QuartzKit/Sources/QuartzKit/Data/FileSystem/VaultSearchIndex.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/VaultSearchIndex.swift)
- [`QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/Vault/StartupCoordinator.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Vault/StartupCoordinator.swift)
- [`QuartzKit/Sources/QuartzKit/Data/FileSystem/FileWatcher.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/FileSystem/FileWatcher.swift)
- [`QuartzKit/Sources/QuartzKit/Domain/Editor/NoteFilePresenter.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/NoteFilePresenter.swift)

### Tests that define intended relationship behavior

- [`QuartzKit/Tests/QuartzKitTests/LinkingIntegrityTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/LinkingIntegrityTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/GraphLinkResolutionTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/GraphLinkResolutionTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/Phase1GraphRepairTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/Phase1GraphRepairTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/Phase2GraphIdentityTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/Phase2GraphIdentityTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/GraphEdgePersistenceTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/GraphEdgePersistenceTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/E2EWikiLinkFlowTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/E2EWikiLinkFlowTests.swift)
- [`QuartzKit/Tests/QuartzKitTests/InspectorStoreTests.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Tests/QuartzKitTests/InspectorStoreTests.swift)

## Discovery Conclusions So Far

1. `proven`: the app does not currently have one authoritative knowledge-graph model.
2. `proven`: explicit-link relationship logic and live graph-edge logic are not the same pipeline.
3. `proven`: graph persistence is graph-view-driven, not editor/live-edge-driven.
4. `proven`: semantic related-notes and semantic graph edges use different thresholds and refresh paths.
5. `proven`: unlinked mentions are heuristic mention matching, not semantic linking.
6. `proven`: concept extraction is AI-assisted, but it is a concept taxonomy system, not a note-link graph.
7. `plausible but unverified`: rename/move/delete consistency will remain fragile until explicit graph edges, semantic edges, and inspector relationships are all moved onto one canonical identity and refresh model.

## Phase 2 / 3 Addendum

This addendum does not replace Phase 1 discovery. It extends it with:

- enforced definitions
- runtime integrity / divergence audit
- architectural risk audit
- feature trust matrix

## Enforced Definitions

### Explicit link

- Concrete markdown wiki-link syntax parsed by [`WikiLinkExtractor.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Data/Markdown/WikiLinkExtractor.swift)
- Example:
  - `[[Note]]`
  - `[[Note|Alias]]`
  - `[[Note#Heading]]`

### Outgoing link

- A current-note inspector relationship derived from resolved explicit links in the open editor text
- Producer:
  - [`EditorSession.scheduleOutgoingLinkRefresh()`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- Stored as:
  - `InspectorStore.outgoingLinks`

### Backlink

- A note that links to the current note
- Producer:
  - [`BacklinkUseCase.findBacklinks(to:in:)`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/BacklinkUseCase.swift)
- Important:
  - it is a merged result, not a single-source graph query

### Graph edge

- This term is overloaded in current code.
- Explicit live graph edge:
  - `GraphEdgeStore.edges`
- Semantic live graph edge:
  - `GraphEdgeStore.semanticEdges`
- Concept live graph edge:
  - `GraphEdgeStore.conceptEdges`
- Graph-view display edge:
  - `GraphEdge` inside [`KnowledgeGraphView.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Graph/KnowledgeGraphView.swift)

### Unlinked mention

- A heuristic suggestion from [`LinkSuggestionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/UseCases/LinkSuggestionService.swift)
- It is not semantic similarity and not AI-generated

### Semantic suggestion

- Note-to-note similarity based on embeddings
- In inspector:
  - `SemanticLinkService` -> `GraphEdgeStore.semanticEdges` -> `InspectorStore.relatedNotes`
- In graph view:
  - local `GraphViewModel.buildGraph(...)` embedding pass

### AI-generated suggestion

- `unknown` for note links
- `proven` absent in the current repo for explicit note-link creation
- Nearest AI-generated relationship-like output is concept extraction:
  - [`KnowledgeExtractionService.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/AI/KnowledgeExtractionService.swift)

### Note title match

- Filename/frontmatter-title/path/alias matching through:
  - `NoteReferenceCatalog`
  - or `GraphIdentityResolver`
  - or `GraphEdgeStore` fallback basename index

### Alias match

- Frontmatter aliases in:
  - `NoteReferenceCatalog.makeReference(for:)`
  - `GraphIdentityResolver.register(_:)`

### Fuzzy text match

- Only implemented in `GraphIdentityResolver.resolve(_:fuzzy:)`
- `plausible but unverified` in production flows because no production caller was found using `fuzzy: true`

### Canonical note identity

- Runtime canonical note identity is standardized file URL
- Owner:
  - [`CanonicalNoteIdentity` in `NoteDocument.swift`](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Models/NoteDocument.swift)

### Persisted graph state

- `GraphCache.CachedGraph`
- `AIIndexState`
- `embeddings.idx`

### Live editor relationship state

- `EditorSession.currentText`
- `InspectorStore.outgoingLinks`
- `InspectorStore.suggestedLinks`
- `InspectorStore.relatedNotes`
- `InspectorStore.aiConcepts`
- `GraphEdgeStore`

## Phase 2 Flow Map Conclusions

Full per-flow mapping now lives in:

- [KNOWLEDGE_GRAPH_FLOW_MAP.md](/Users/I533181/Developments/Quartz/KNOWLEDGE_GRAPH_FLOW_MAP.md)

The strongest conclusions from the mapped flows are:

1. `proven`: explicit current-note relationship surfaces are computed from live editor text, not from the persisted graph cache.
2. `proven`: graph persistence is written by graph-view rebuilds, not by live explicit-link updates.
3. `proven`: rename/move/delete lifecycle handling is asymmetric:
   - shell metadata updates are present
   - embedding/AI updates are partial
   - explicit graph repair is largely absent
4. `proven`: inspector related notes and graph-view semantic edges are independent systems with different thresholds and refresh timing.
5. `proven`: there is no AI-assisted explicit note-link creation path in production code.

## Phase 3 — Integrity / Divergence Audit

### Divergence Matrix

#### Explicit links vs outgoing links

- Status:
  - `proven` partially converged
- Shared path:
  - `NoteReferenceCatalog.resolvedExplicitReferences(...)`
- Divergence:
  - outgoing links are current-note live text only
  - explicit graph edges are stored in `GraphEdgeStore`
  - `fileTree` changes do not rerun outgoing-link refresh automatically
- Result:
  - correct while the open note text and note catalog are stable
  - stale when note catalog changes after the note is already open

#### Explicit links vs backlinks

- Status:
  - `proven` diverged
- Shared path:
  - scanned backlink branch uses `NoteReferenceCatalog`
- Divergence:
  - backlink results merge vault scan + live graph backlinks
  - live graph backlinks depend on `GraphEdgeStore`
  - `GraphEdgeStore` normally resolves by basename fallback
- Result:
  - backlinks can recover from stale graph state by rescanning the vault
  - but this is a repair-through-merge pattern, not one authoritative model

#### Explicit links vs live graph edges

- Status:
  - `proven` diverged
- Evidence:
  - `EditorSession.refreshExplicitLinkGraphConnections(...)` updates `GraphEdgeStore`
  - then separately resolves richer `targetURLs` through `NoteReferenceCatalog`
- Result:
  - published invalidation payload can be richer than stored edges

#### Live graph edges vs persisted graph cache

- Status:
  - `proven` diverged
- Evidence:
  - startup reader:
    - `ContentViewModel.loadVault(_:)` -> `GraphEdgeStore.loadFromCache(...)`
  - writer:
    - `GraphViewModel.buildGraph(...)` -> `GraphCache.save(...)`
  - no production caller found for `GraphEdgeStore.exportForCache()`
- Result:
  - live graph and persisted graph are not produced by the same owner

#### Persisted graph cache vs graph-view graph edges

- Status:
  - `proven` lossy
- Evidence:
  - graph view builds `GraphEdge(isConcept: true)`
  - `GraphCache.CachedEdge` only stores `isSemantic`
- Result:
  - concept edge type is lost when graph view persists to `graph-cache.json`

#### Graph-view graph edges vs inspector related notes

- Status:
  - `proven` diverged
- Evidence:
  - inspector related notes:
    - `SemanticLinkService` threshold `0.82`
  - graph view semantic edges:
    - `GraphViewModel.buildGraph(...)` threshold `0.35`
- Result:
  - the same note can appear semantically linked in graph view and not appear in inspector related notes

#### Explicit links vs unlinked mentions

- Status:
  - `proven` mostly converged for current-note text
- Evidence:
  - `LinkSuggestionService.suggestLinks(...)` excludes explicit references by `noteURL` and `matchRange`
- Remaining divergence:
  - exclusion quality depends on `NoteReferenceCatalog.resolveExplicitLinkTarget(...)`
  - file-tree changes do not automatically rerun analysis
- Result:
  - current design is coherent on a stable file tree
  - not globally authoritative across lifecycle changes

#### SemanticLinkService results vs graph-view semantic edges

- Status:
  - `proven` diverged
- Evidence:
  - separate producers
  - separate thresholds
  - separate refresh timing
  - separate persistence assumptions
- Result:
  - “semantic links” is not one consistent relationship set

#### AI concepts vs graph view

- Status:
  - `proven` partially converged
- Shared path:
  - graph view concept hub nodes are built from `GraphEdgeStore.significantConcepts(...)`
- Divergence:
  - graph cache cannot persist concept edges faithfully
  - concept cleanup on rename/move/delete is not wired
- Result:
  - graph view can show concept hubs from live store
  - but persistence and lifecycle integrity are weak

#### AI concepts vs explicit links / backlinks / outgoing links

- Status:
  - `proven` separate systems
- Evidence:
  - AI concepts are note-to-concept only
  - they do not mutate explicit note links
- Result:
  - concept extraction should not be treated as note-linking

### Required Audits

#### Identity mismatch

- `proven`
- Runtime canonical note identity:
  - `CanonicalNoteIdentity.canonicalFileURL(for:)`
- Other active identity schemes:
  - `GraphIdentityResolver.stableID(for:)`
  - `VectorEmbeddingService.stableNoteID(for:vaultRoot:)`
  - graph-view node IDs = `url.absoluteString`
  - concept node IDs = `concept:<name>`

#### Normalization mismatch

- `proven`
- Evidence:
  - `GraphIdentityResolver.normalize(_:)`
  - `NoteReferenceCatalog.normalize(_:)`
  - `GraphEdgeStore` fallback basename-only `titleIndex`

#### Parser mismatch

- explicit wiki-link syntax parser mismatch:
  - `ruled out` as primary cause
  - same `WikiLinkExtractor` is reused across major explicit-link readers
- post-parse relationship construction mismatch:
  - `proven`
  - different systems do different things with the parsed targets

#### Cache writer / reader mismatch

- `proven`
- Reader:
  - `ContentViewModel.loadVault(_:)`
- Writer:
  - `GraphViewModel.buildGraph(...)`

#### Stale refresh ordering

- `proven`
- Evidence:
  - current note load/open refreshes note-local relationships immediately
  - embeddings, semantic edges, and concepts refresh later
  - graph cache is independent
  - file-tree changes do not rerun all relationship computations

#### Rename / move / delete fragility

- `proven`
- Evidence:
  - search/preview/Spotlight flows are wired
  - graph/semantic/concept cleanup helpers exist but are not wired broadly in production

#### Save vs reopen vs live editor divergence

- `proven`
- Live editor:
  - `currentText`-based outgoing links and unlinked mentions
- Reopen:
  - reruns note-local computations
- Relaunch:
  - hydrates persisted graph/embedding/concept systems separately
- Result:
  - different surfaces warm at different times

#### Graph-view vs inspector divergence

- `proven`
- Evidence:
  - explicit edges rebuilt independently in graph view
  - semantic edges computed independently in graph view
  - graph view does not subscribe to `.quartzReferenceGraphDidChange`, `.quartzSemanticLinksUpdated`, or `.quartzConceptsUpdated`
  - current file search only found `.task(id: semanticAutoLinkingEnabled)` in `KnowledgeGraphView`

#### Semantic threshold divergence

- `proven`
- Evidence:
  - `SemanticLinkService` threshold `0.82`
  - `GraphViewModel.buildGraph(...)` threshold `0.35`

#### Overclaimed “semantic linking”

- `proven`
- Evidence:
  - `AISettingsView` describes “Auto-Discover Related Notes” as one knowledge-graph setting
  - same setting also gates `KnowledgeExtractionService`
  - unlinked mentions are heuristic mention matching, not semantic similarity

## Architectural Risk Audit

### Duplicated relationship parsers

- `plausible but unverified`
- Explicit syntax parsing itself is mostly shared through `WikiLinkExtractor`
- The stronger problem is duplicated post-parse interpretation, which is already `proven`

### Duplicated normalization rules

- `proven`

### Multiple note identity models

- `proven`

### Stale graph caches

- `proven`

### Stale backlink caches

- dedicated backlink cache:
  - `ruled out`
- stale backlink UI state:
  - `proven`

### Inconsistent alias handling

- `proven`
- `NoteReferenceCatalog` and `GraphIdentityResolver` understand aliases
- `GraphEdgeStore` fallback title index does not

### Refresh only on save, not on edit

- explicit live graph:
  - `ruled out`
  - it refreshes on edit for the current open note
- embeddings / semantic / concept systems:
  - `proven`
  - primarily save/file-change driven

### Refresh only on reopen, not on save

- `plausible but unverified` as a generalized claim
- some note-local surfaces refresh on save and edit
- persisted graph and graph view do not

### Live editor state diverging from persisted graph state

- `proven`

### Inspector using different relationship logic than graph view

- `proven`

### Semantic suggestions not using the same note identity model

- `proven`

### Rename / move breaking graph edges

- `proven`

### Note delete leaving stale edges

- `proven`

### Async refresh ordering bugs

- `proven`

### Cross-window graph inconsistencies

- `unknown`
- current repo review did not establish a definitive cross-window graph corruption path

### Background scan overwriting newer live relationship state

- `plausible but unverified`
- strongest candidate is concept restore / rescan ordering, not explicit-link state

### Unlinked mentions counting already linked references

- current current-note exclusion model:
  - `proven` coherent on stable input
- lifecycle-wide guarantee:
  - `fragile`

### “Semantic linking” label overstating capability

- `proven`

## Feature Trust Matrix

| Area | Classification | Why |
| --- | --- | --- |
| Explicit links | correct but fragile | Parsing is solid, but resolution and lifecycle integrity split across `NoteReferenceCatalog`, `GraphEdgeStore`, and graph-view-local rebuilds |
| Outgoing links | correct but fragile | Current-note computation is good, but it is not recomputed on all note-catalog changes and is not persisted |
| Backlinks | visually present but not truly trustworthy | Results are a merge of vault scans and live graph edges rather than one canonical source |
| Unlinked mentions | correct but fragile | Heuristic mention matching is coherent for stable inputs, but refresh and lifecycle invalidation are incomplete |
| Related notes | visually present but not truly trustworthy | Inspector related notes and graph-view semantic edges are different systems |
| Graph view | visually present but not truly trustworthy | It rebuilds explicit and semantic edges independently and also owns persisted graph snapshots |
| AI concepts | partially implemented | Concept extraction exists and is persisted, but cleanup and graph-cache fidelity are weak |
| Refresh / invalidation integrity | architecturally wrong and should be replaced | Multiple producers, NotificationCenter fan-out, and partial lifecycle wiring |
| Rename / move / delete integrity | partially implemented | Metadata surfaces update; graph integrity does not |
| Semantic-linking truthfulness | visually present but not truly trustworthy | Product language over-collapses embeddings, heuristic mentions, and AI concepts into one idea |

## Phase 3 Conclusions

1. `proven`: explicit links are the only truly hard relationship signal in the product.
2. `proven`: outgoing links are the cleanest current-note relationship surface.
3. `proven`: backlinks are operationally useful, but they are not sourced from one authoritative model.
4. `proven`: unlinked mentions are heuristic title/alias/path mention suggestions, not semantic linking.
5. `proven`: inspector related notes are embedding-based similarity, not explicit graph structure.
6. `proven`: AI concepts are ontology-like note-to-concept annotations, not note-to-note links.
7. `proven`: the current “knowledge graph” is a federation of overlapping systems, not one graph.
