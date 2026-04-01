# CODEX.md — Quartz Ruthless Refactor & Dominance Plan (Strict TDD)

**Audience:** Claude Code autonomous implementation agent.  
**Project:** Quartz (macOS/iOS/iPadOS Markdown ecosystem).  
**Operating mode:** Zero-mercy audit + phased execution with mandatory Red→Green→Refactor.

---

## 0) Non-Negotiable Laws (Read Before Touching Any Code)

1. **No production code before failing tests.** Every phase starts by creating tests that fail for the right reason.
2. **No "quick fixes" inside SwiftUI views.** Any non-trivial logic in view bodies is architectural debt.
3. **No main-thread heavy work.** File traversal, parsing, AI, embedding, transcription, and graph layout must be off the MainActor unless explicitly rendering UI.
4. **No silent fallback.** Every AI/audio fallback path must emit deterministic telemetry and user-visible state.
5. **No state amnesia.** Split-view columns, selection, scroll position, editor selection, and inspector visibility must survive pane toggles, background AI updates, and app lifecycle transitions.
6. **No undocumented behavior.** Every core subsystem gets a short architecture note and a deterministic test matrix.
7. **Every phase = one vertical slice.** Includes tests, implementation, perf assertions, migration notes, and rollback plan.

---

## 1) Brutal Teardown of Current Quartz (What Is Rotting Right Now)

## 1.1 SwiftUI anti-patterns and architecture leaks

### A. `ContentView` is still a command center monster
- `ContentView` owns routing, sheet orchestration, overlays, keyboard shortcuts, export flow, and vault lifecycle glue in one type. This is still too much volatility in one render surface. It behaves like an unbounded God View even if comments claim otherwise.  
- This guarantees accidental invalidation cascades across unrelated concerns (e.g., command palette visibility can trigger re-evaluation across export/sheets/main layout).

**Action:** Split into:
- `WorkspaceShellView` (layout only)
- `PresentationRouter` (sheets/alerts)
- `CommandSurfaceHost` (palette + keyboard)
- `ExportCoordinatorView`

### B. Duplicate editor architecture running in parallel
- `ContentViewModel.openNote` instantiates **legacy** `NoteEditorViewModel` while also loading `EditorSession`. You currently run two editor state machines for one note switch.
- This creates race potential, duplicated file watcher activity, and conceptual drift between “legacy” and “session” paths.

**Action:** Hard-delete legacy path in phased migration after parity tests pass.

### C. View-local state bridging that can desync selection
- `WorkspaceView` keeps `@State sidebarNoteSelection` and then mirrors into `store.selectedNoteURL` via `.onChange`. This two-step sync invites transient mismatch and flicker under rapid updates.

**Action:** Single-source selection binding from `WorkspaceStore` directly.

---

## 1.2 State/reload failures in 3-pane + inspector model

### A. MainActor store orchestrating async I/O in reaction handlers
- In `WorkspaceView`, source changes trigger `Task { await noteListStore.changeSource(...) }` from view modifiers. That hides control flow and makes ordering fragile when multiple state changes happen quickly.

### B. Inspector refresh tied to notifications instead of deterministic state stream
- `EditorSession` updates inspector data through notification observers (`quartzSemanticLinksUpdated`, `quartzConceptsUpdated`, scan progress), increasing out-of-order risk.

### C. Graph/dashboard/editor detail routing is mutually exclusive booleans
- `showGraph`, `showDashboard`, `selectedNoteURL` interact via didSet side effects. This is brittle state algebra and easy to break when adding inspector/workflow states.

**Action:** Replace with enum route:
```swift
enum DetailRoute { case dashboard, graph, note(URL) }
```
plus tested reducer transitions.

---

## 1.3 Main-thread blocking and perf hazards

### A. `AudioRecordingService` is `@MainActor` and drives timers + meter history on main
- Continuous metering updates and waveform history mutation happen on main run loop.
- For long sessions + active UI, this competes with typing/rendering and can degrade 120Hz smoothness.

### B. `KnowledgeExtractionService` and `SemanticLinkService` still perform vault scans/enumeration inside actor flows with unclear isolation boundaries
- Directory scans, content reads, and noteID resolution are expensive and currently coupled to service actors that also manage orchestration state.

### C. `GraphEdgeStore.updateConnections` rebuilds title index every call
- Rebuilding a full title index for each note update scales badly and causes avoidable CPU churn in active editing scenarios.

**Action:** Move heavyweight work to dedicated background workers and feed results into lightweight actor commits.

---

## 1.4 Spaghetti coupling blocking isolated tests

1. `ContentViewModel.loadVault` wires almost every subsystem (sidebar, search, spotlight, embeddings, semantic links, knowledge extraction, session, chat, sync, backup, observer setup) in one method.
2. `ServiceContainer.shared` use inside views and view models creates hidden dependencies and weak test seams.
3. Graph identity logic exists in multiple places (`GraphEdgeStore` title matching + `GraphIdentityResolver` actor) with overlapping responsibilities.

**Action:** Introduce composition root + protocolized dependency graph + feature modules with independent test harnesses.

---

## 1.5 Knowledge Graph auto-wiring failure root causes

**Why links fail today:**
1. `GraphEdgeStore` resolves links via simplified lowercase lastPathComponent index, ignoring aliases/frontmatter titles/path-qualified wiki links.
2. Identity strategy is split: robust resolver exists (`GraphIdentityResolver`) but graph edge update paths still rely on simplistic title maps.
3. No single canonical note identity contract shared across parsing, graph, and AI concept assignment.
4. Concept extraction pipeline depends on external provider availability and weakly typed prompt output parsing; missing resilient local fallback.

**Fix mandate:** One canonical identity pipeline used by parser, graph builder, backlinks, and AI concept linker.

---

## 2) Forensic Competitor Teardown (What to Beat, Not Copy)

## 2.1 OpenOats forensic teardown (baseline for meeting minutes)

From OpenOats public architecture/docs:
- Local real-time dual-side transcription emphasis.
- Knowledge base chunking with heading-aware segmentation (80–500 words), batched embeddings, local cache reuse.
- Suggestion pipeline appears gated by conversational triggers + cooldown.
- Privacy model is explicit (local-only option with Ollama).

### OpenOats strengths to absorb
1. Explicit pipeline framing (capture → transcribe → retrieve → suggest).
2. Clear data-boundary/privacy communication.
3. Operational batching strategy for embeddings/search.

### OpenOats weaknesses Quartz must punish
1. Not deeply integrated with a native Markdown editor state model (Quartz can unify capture with active document context and backlinks).
2. Meeting output quality depends on remote providers unless fully-local stack is configured manually.
3. Architecture appears tuned for call-assist first, not a first-class note graph with long-lived semantic memory in-app.

### Quartz superiority target
- End-to-end native pipeline: `AudioCaptureOrchestrator` + on-device diarization + local language detection + deterministic markdown minutes generator + direct insertion into active note and graph.

---

## 2.2 Bear 2 / Ulysses / Obsidian / Notion teardown translation

### Bear 2 parity requirements
- TextKit 2-level visual polish: inline markdown elision, typographic rhythm, stable editing under heavy document load.
- Tag sidebar performance with deep hierarchies and zero-jank filtering.

### Ulysses parity requirements
- 3-pane reliability with perfect state retention (selection, scroll, focus) across route changes.
- Inspector that never steals editor focus during background metadata recomputation.

### Obsidian/Notion table bar
- Rich table editing affordances while preserving source markdown fidelity.
- Keyboard navigation (Tab/Shift+Tab/Enter) and drag-to-resize UX with native feel.

---

## 3) Target Architecture (Macro)

1. **Presentation Layer**
   - `WorkspaceReducer` + immutable `WorkspaceState`.
   - Route-driven detail pane (`DetailRoute`).

2. **Editor Core**
   - `EditorSession` is sole source of truth.
   - Incremental markdown parser + render diff engine.

3. **Graph Core**
   - `NoteIdentityIndex` (canonical IDs, aliases, path keys, title variants).
   - `LinkResolutionEngine` (deterministic resolution ordering + confidence).

4. **AI Core**
   - `AIExecutionPolicyActor` (remote/local fallback, health, budget).
   - `ConceptExtractionEngine` with typed output schema.

5. **Audio Core**
   - `MeetingCaptureOrchestrator` state machine.
   - stages: capture → VAD/chunking → ASR → diarization → language detection → minutes templater.

6. **Infra**
   - Unified telemetry events + circuit breakers + perf budget assertions.

---

## 4) Strict TDD Execution Plan (Phases)

## Phase 0 — The Great Purge (Expose the rot before rewriting)

### Red (write failing tests)
Create:
- `WorkspaceRouteReducerTests`
  - route transitions from graph/dashboard/note are deterministic.
- `WorkspaceStateRetentionTests`
  - scroll + cursor + split visibility survive inspector updates and background graph refresh.
- `DualEditorRegressionTests`
  - assert only one editor pipeline is active after note open.
- `GraphIdentityContractTests`
  - aliases/title/path/fuzzy rules resolve identically across all graph entry points.

### Green
- Replace boolean detail routing with `DetailRoute`.
- Remove legacy `NoteEditorViewModel` usage path from `openNote` after passing parity tests.
- Introduce unified `WorkspaceAction` reducer.

### Refactor
- Move sheet/alert/export orchestration out of `ContentView` into dedicated coordinators.

---

## Phase 1 — Knowledge Graph Repair (Critical path)

### Red
Add failing tests:
- `GraphWiringE2ETests`
  - wiki-link using alias resolves to correct note.
  - folder-qualified links resolve regardless of case/punctuation.
  - rename keeps stable node ID and rewires edges.
- `ConceptHubIntegrityTests`
  - no orphan concept node without note membership.
- `BacklinkDeterminismTests`
  - backlink sets stable across rebuilds.

### Green
- Build `NoteIdentityIndex` and deprecate ad-hoc title lookup in `GraphEdgeStore`.
- Route all resolution through `GraphIdentityResolver`-compatible API.
- Persist stable IDs (not path strings) in graph cache; map ID→URL separately.

### Refactor
- Make graph build pipeline pure/data-first:
  1) collect note manifests
  2) build identity index
  3) resolve edges
  4) merge semantic edges
  5) attach concept hubs

---

## Phase 2 — AI fallback hardening (remote failure cannot break graph)

### Red
- `AIExecutionPolicyTests`
  - remote timeout/open circuit triggers local model path within budget.
  - repeated remote errors open circuit and cool down.
- `ConceptExtractionFallbackTests`
  - local fallback returns minimal concept set even when provider unavailable.
- `SchemaValidationTests`
  - malformed model output cannot crash parser.

### Green
- Implement `AIExecutionPolicyActor`:
  - states: healthy/degraded/open.
  - per-task timeout budgets.
  - retry with jitter + max attempt cap.
- Add on-device concept extraction fallback (CoreML/NL embedding heuristics + noun phrase extraction).
- Persist provider health + last error for inspector diagnostics.

### Refactor
- Remove provider selection logic from UI-facing view models.

---

## Phase 3 — 3-pane + Inspector zero-stutter architecture

### Red
- `InspectorFocusRetentionTests`
- `SplitViewColumnPersistenceTests`
- `BackgroundGraphUpdateNoFlickerTests`
- UI test: typing during AI graph update never drops insertion point.

### Green
- Introduce `InspectorProjectionStore` (derived, throttled state).
- Apply transactional state updates with coalescing.
- Ensure note list refresh supports item-level diffing only.

### Refactor
- Remove notification spaghetti; use typed async streams for graph/inspector events.

---

## Phase 4 — TextKit 2 top-tier editor (Bear-grade)

### Red
- `MarkdownElisionCursorTests` (**, ## hide/show rules by cursor scope)
- `TableEditingKeyboardTests` (Tab traversal, row/column insert semantics)
- `InlineMediaLayoutTests` (lazy image decode, resize handles)
- `LargeDocRenderingPerfTests` (10k words + 50 images)

### Green
- Incremental AST + range invalidation renderer.
- Markdown syntax elision when block unfocused.
- Native table interaction layer preserving markdown serialization.
- Media manager with background decoding/cache.

### Refactor
- Separate parser/render/editor command handling into independent modules.

---

## Phase 5 — On-device audio intelligence (OpenOats++)

### Red
- `CaptureStateMachineTests`
- `AudioBufferBackpressureTests` (60+ min sessions)
- `DiarizationAlignmentTests`
- `LanguageDetectionSwitchTests`
- `MinutesTemplateDeterminismTests`

### Green
- Implement `MeetingCaptureOrchestrator` actor with explicit states.
- Add chunked processing pipeline and memory budget enforcement.
- Add speaker diarization labels + confidence thresholds.
- Add language detection pre-pass and recognizer routing.
- Add compact floating recording UI transitions with tested continuity.

### Refactor
- Move `AudioRecordingService` off monolithic MainActor responsibilities; isolate UI-bound state from processing core.

---

## Phase 6 — Advanced tables, inspector intelligence, export parity

### Red
- `MarkdownTableRoundTripTests`
- `TableDragResizeUITests`
- `InspectorStatsAccuracyTests`
- `ExportFidelitySnapshotTests` (PDF/Markdown)

### Green
- Canonical markdown table model + editor command set.
- Drag-resize overlays and keyboard-driven cell navigation.
- Inspector adds graph neighborhood, backlink deltas, AI provenance.

### Refactor
- Establish plugin-like export architecture.

---

## Phase 7 — Full performance/security hardening

### Red
- `TypingLatencyBudgetTests`
- `GraphBuildTimeBudgetTests`
- `LongSessionMemoryTests` (audio)
- `SyncConflictRecoveryTests`

### Green
- Enforce perf budgets in CI using XCTest measure baselines.
- Add signposts and telemetry thresholds.
- Tighten sync conflict UX + deterministic recovery logs.

### Refactor
- Remove dead code and fallback branches made obsolete by policy actor.

---

## 5) Mandatory test matrix per PR

1. Unit tests for touched module.
2. Integration tests for cross-module contract.
3. UI/snapshot tests if any layout change.
4. Performance test if any render/audio/graph logic change.
5. Regression tests for prior bug in same area.

No PR merges without all five categories (or explicit documented exception).

---

## 6) Required implementation standards

- Swift 6.3 strict concurrency compliance.
- Avoid `NotificationCenter` for core domain orchestration; prefer typed streams/actions.
- No singleton dependency resolution inside domain logic.
- No I/O in view bodies or `.onChange` closures directly.
- Every async operation must be cancellable.
- Every background pipeline must expose progress + backpressure behavior.

---

## 7) Definition of Done (Global)

Quartz is considered fixed only when all are true:
1. Knowledge graph auto-wiring resolves aliases/path/title variants reliably and passes E2E graph tests.
2. Background AI updates do not flicker UI or steal editor focus.
3. Editor supports stable markdown elision, advanced tables, and media workflows without frame drops.
4. Audio recording/transcription/diarization/minutes pipeline is robust for 60+ minute sessions on Apple Silicon.
5. Remote AI outage still yields functional local graph/minutes generation with transparent status.
6. CI enforces latency/memory budgets and catches regressions before merge.

---

## 8) Claude Code execution protocol

For each phase:
1. Create failing tests first (`RED`).
2. Implement minimum code to pass (`GREEN`).
3. Refactor for clarity/perf (`REFACTOR`).
4. Update docs + migration notes.
5. Commit with phase-scoped message.
6. Do not start next phase until current phase test suite is green.

If a phase exposes hidden coupling, stop and open a sub-phase named `Phase X.a - Decoupling` with dedicated failing tests.

This document is intentionally unforgiving. Follow it exactly.
