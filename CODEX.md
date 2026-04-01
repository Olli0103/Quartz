# CODEX — Quartz Autonomous Execution Blueprint (Strict TDD)

> Audience: Claude Code agent operating in iterative PR cycles.
> 
> Mission: Upgrade Quartz into an Apple Design Award-level Markdown ecosystem (macOS, iOS, iPadOS) with zero regressions, resilient AI graph wiring, and premium on-device audio intelligence.

---

## 0) Non-Negotiable Operating Rules

1. **Red → Green → Refactor (always).**
   - Every phase starts by writing failing tests that define behavior.
   - No production code may be added/changed until the new tests fail for the expected reason.
2. **No regressions allowed.**
   - Full relevant test suites run before merge.
   - If any unrelated baseline test fails, stop and fix before proceeding.
3. **Main-thread safety.**
   - AI, graph indexing, transcription, and sync work must never block UI.
4. **Platform fidelity first.**
   - Native behavior over custom gimmicks.
5. **Accessibility parity is mandatory.**
   - VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency.
6. **Feature flags for risky rollouts.**
   - Gate large subsystems (new graph linker, live preview pipeline, compact recorder shell).
7. **Each PR must be one bounded vertical slice.**
   - Include tests, implementation, docs, and migration notes.

---

## 1) Current Quartz Architecture Snapshot (Ground Truth)

### 1.1 Existing strengths

- **Text editor foundation already uses TextKit 2 wrappers** (`MarkdownTextView`, `MarkdownTextContentManager`) and includes hardening/circuit-breaker tests.
- **Knowledge graph has a capable visual model** with hard links, semantic links, concept nodes, cached graph snapshots, and simulation policy caps.
- **AI indexing stack exists** (`VectorEmbeddingService`, `IntelligenceEngineCoordinator`) with on-device embeddings and file-event wiring.
- **Audio stack exists** (`AudioRecordingService`, `TranscriptionService`, `SpeakerDiarizationService`, `MeetingMinutesService`) and includes a first pass compact recording pill UI.
- **Command palette and Liquid Glass design system are present** and can be elevated instead of rewritten.
- **Cloud sync service exists** with coordination/conflict operations.

### 1.2 Diagnosed weak points to fix

1. **Graph auto-wiring reliability gap**
   - `KnowledgeGraphView` builds hard links by exact lowercase note display-name matching from wiki links.
   - This is brittle for aliases, renamed files, punctuation differences, folder-prefixed wikilinks, and frontmatter title divergence.
   - Concept node insertion depends on edge store coherence and can silently under-connect.

2. **Semantic/AI fallback policy is not explicit enough**
   - On-device embeddings exist, but fallback orchestration (remote fail → local takeover) is not codified as a tested policy layer.

3. **Audio UX is still modal-heavy, not truly Granola-grade**
   - Compact mode exists but lacks robust matched geometry orchestration, detached-floating behavior strategy, and production diarization confidence UX.

4. **Onboarding/help are not tutorial-driven enough**
   - Current onboarding focuses on storage/template setup, but not an interactive “learn by doing” markdown note.

5. **Testing is broad but not yet codified around these critical business guarantees**
   - Need explicit E2E graph wiring specs, fallback specs, performance budgets, and snapshot/accessibility gates.

---

## 2) Competitive Benchmark Translation → Quartz Requirements

### Bear 2 parity/surpass targets
- TextKit 2 inline markdown styling must be stable under rapid edits.
- Nested tags and hierarchical tags must parse/render/search consistently.
- Typography/theme quality must be intentional with predictable baseline grids.

### Ulysses parity targets
- Sheet-style document management: robust grouping/filtering, export presets, deterministic export fidelity.

### iA Writer parity targets
- Focus mode: frictionless, keyboard-first, minimal chrome, stable scroll/selection anchoring.

### Apple Notes parity targets
- Instant quick capture and frictionless sync experience.
- Startup-to-first-character latency under strict threshold.

### Granola/OpenOats surpass targets
- Persistent compact floating recorder shell.
- On-device transcription + diarization + language detection + templated minutes.
- Clear confidence/error recovery UX without cloud dependency.

---

## 3) Master Delivery Map (Strict TDD Phases)

## Phase 1 — Knowledge Graph Wiring Reliability (Highest Priority)

### Red (tests first)
Add/extend tests in `QuartzKit/Tests/QuartzKitTests`:

1. `GraphLinkResolutionTests`
   - `test_wikiLink_resolvesByCanonicalTitle_andFilenameAlias`
   - `test_wikiLink_resolvesWithFolderPrefix_andCasePunctuationDifferences`
   - `test_rename_preservesStableNodeIdentity_andRewiresEdges`
   - `test_projectX_note_autoWiresTo_projectX_conceptNode`
2. `GraphBuildDeterminismTests`
   - deterministic node/edge sets given same vault snapshot.
3. `GraphCacheInvalidationTests`
   - content rename/link-change invalidates cache correctly.
4. `GraphCircuitFallbackTests`
   - large vault triggers graceful graph policy without crash.

### Green (implementation)
1. Introduce `GraphIdentityResolver` domain component:
   - canonical key generation from filename, frontmatter title, aliases.
   - normalized compare pipeline (casefolding, punctuation stripping, whitespace collapse).
2. Introduce `WikiLinkTargetResolver`:
   - parse `[[folder/note|alias]]` and path-like links.
   - fallback resolution order: explicit path > alias index > canonical title > fuzzy threshold.
3. Add stable graph identity map:
   - keep `stableNoteID` separate from URL string display identity.
4. Refactor graph build pipeline in `GraphViewModel`:
   - split into testable pure steps: collect notes, index identities, resolve hard links, attach semantic edges, attach concept hubs.
5. Harden concept hub insertion:
   - reject orphan concept edges, enforce existing note membership.

### Refactor
- Remove duplicate normalization logic from view model.
- Add DocC for resolver and graph pipeline invariants.

### Done criteria
- New graph tests pass.
- Existing graph/editor tests stay green.
- No UI freeze during graph rebuild for capped node set.

---

## Phase 2 — AI Fallback Orchestration (Remote ↔ On-Device)

### Red
Create tests:

1. `AIFallbackPolicyTests`
   - `test_remoteFailure_triggersOnDeviceEmbeddingFallback`
   - `test_offlineMode_forcesOnDevicePath`
   - `test_timeout_remoteProvider_switchesToLocalWithinBudget`
2. `KnowledgeExtractionFallbackTests`
   - concept extraction still returns minimal graph entities when provider unavailable.
3. `MainThreadIsolationTests`
   - assert fallback orchestration does not execute heavy work on `MainActor`.

### Green
1. Add `AIExecutionPolicy` + `ProviderHealthState`:
   - states: healthy, degraded, unavailable, circuit-open.
2. Add unified interface for graph/link/tag generation:
   - primary provider (API) + secondary local provider (`NLEmbedding`/CoreML path).
3. Add bounded retries + timeout budgets + circuit breaker integration.
4. Persist provider health telemetry for UX indicators.
5. Update settings UI for transparent fallback status.

### Refactor
- Consolidate policy logic into a single testable actor.
- Ensure all async calls are cooperative and cancellable.

### Done criteria
- Forced API failure still produces graph links/tags via local path.
- No main-thread stalls in performance tests.

---

## Phase 3 — TextKit 2 Live Preview + Performance-Safe Rendering

### Red
Add tests:

1. `LivePreviewASTTests`
   - inline emphasis, links, checkboxes, code spans, nested lists.
2. `TextKitRenderingStabilityTests`
   - no selection jump during style updates.
3. `LargeDocumentPerformanceTests`
   - `measure` scroll/edit for 10k+ words.
4. `FocusModeBehaviorTests`
   - chrome suppression, cursor visibility, keyboard command consistency.

### Green
1. Build a dual-lane pipeline:
   - editing lane: plain text correctness + lightweight token hints.
   - preview lane: incremental AST diff + attributed patches.
2. Incremental range invalidation only (avoid full-document restyle).
3. Add `EditorRenderBudget` heuristics:
   - degrade expensive decorations under load.
4. Implement iA Writer-grade focus mode:
   - hide non-essential UI, preserve command palette and escape hatch.
5. Expose typography/theme tokens with strict baseline/spacing system.

### Refactor
- Isolate markdown styling engine from view wrappers.
- Add DocC with “selection stability contract.”

### Done criteria
- 10k-word edit/scroll metrics pass agreed threshold.
- No flicker/cursor drift regressions.

---

## Phase 4 — Granola-Style Audio Capture + On-Device Intelligence

### Red
Add tests:

1. `AudioPipelineIntegrationTests`
   - record → transcribe → diarize → minutes generation chain.
2. `DiarizationMappingTests`
   - speaker segment boundaries map correctly to transcription segments.
3. `LanguageDetectionTests`
   - mixed-language samples choose expected dominant language/fallback.
4. `RecorderCompactUITests` + snapshots
   - transition full ↔ compact preserves timer/state.
   - matched geometry frame continuity and control hit targets.
5. `AudioPerformanceTests`
   - measure time-to-transcribe 5-minute sample; verify no main-thread blocking.

### Green
1. Build `MeetingCaptureOrchestrator` actor:
   - owns recording session state machine and post-processing stages.
2. Add language detection stage before transcription recognizer selection.
3. Improve diarization confidence scoring and segment merge heuristics.
4. Promote compact recorder to true floating shell architecture:
   - iOS/iPadOS: overlay scene/panel strategy.
   - macOS: resizable mini window/panel behavior parity.
5. Add templates engine for meeting minutes with local summarization fallback.

### Refactor
- Separate UI animation state from audio domain state.
- Add DocC for pipeline contracts and failure recovery.

### Done criteria
- End-to-end local meeting capture works offline.
- Compact UI is resilient during navigation/app state changes.

---

## Phase 5 — Quick Capture, Sync Reliability, Conflict Safety

### Red
Add tests:

1. `QuickCaptureFlowTests`
   - global hotkey/new capture route writes note in under latency budget.
2. `CloudSyncConflictPolicyTests`
   - CRDT/merge policy deterministic for same conflicting edits.
3. `SyncRecoveryTests`
   - interrupted write resumes safely with no data loss.

### Green
1. Introduce explicit `QuickCaptureUseCase` shared across macOS/iOS entrypoints.
2. Add instant note stub creation + deferred enrichment strategy.
3. Extend conflict resolver toward CRDT-inspired merge metadata (operation timestamps/author/session).
4. Add fast-path sync state indicator updates tied to coordinated writes.

### Refactor
- Unify write paths to avoid divergent save logic.

### Done criteria
- “Capture thought now” flow is one gesture/shortcut and robust offline.

---

## Phase 6 — Interactive FTUE Note + Help System + DocC Expansion

### Red
Add tests:

1. `FTUEDefaultNoteTests`
   - first launch creates interactive tutorial note exactly once.
2. `FTUEProgressionTests`
   - user actions inside note unlock/mark tutorial sections.
3. `HelpSearchIndexTests`
   - help entries searchable and command-routable.
4. `DocCCompletenessTests` (scripted check)
   - all AI/Graph/Audio public complex types have DocC comments.

### Green
1. Ship interactive onboarding markdown note template:
   - includes guided tasks for graph linking, compact recording, command palette usage.
2. Add macOS Help menu integration:
   - deep links to help topics and in-app contextual anchors.
3. Add iOS/iPadOS help modal with searchable sections.
4. Expand DocC catalog:
   - architecture guides, troubleshooting, extension points.

### Refactor
- Keep onboarding content versioned for future migrations.

### Done criteria
- New users learn by doing, not by tooltip overload.
- Help is searchable and platform-native.

---

## Phase 7 — Visual Polish, Accessibility, and ADA-Level Quality Gate

### Red
Add UI/accessibility tests:

1. Snapshot matrix across light/dark, dynamic type sizes, reduce transparency.
2. VoiceOver navigation order tests for editor, graph, recorder compact UI.
3. Gesture/keyboard parity tests (Cmd+K palette, graph navigation, focus mode exits).

### Green
1. Tighten Liquid Glass boundaries/material usage consistency.
2. Fix hit target sizes, contrast ratios, and focus rings.
3. Add motion-reduced animation variants for all major transitions.

### Refactor
- Centralize visual tokens and accessibility modifiers.

### Done criteria
- Accessibility test suite green on all supported platforms.
- Snapshot baselines approved.

---

## 4) Cross-Phase Test Matrix (Must Exist by End State)

1. **Unit**
   - Markdown AST parse/diff
   - Link resolution normalizer
   - Diarization/transcription mapping
   - CRDT conflict policy
2. **Integration**
   - Graph auto-wiring from note creation/rename
   - AI fallback handoff (forced failures)
   - Audio full pipeline orchestration
3. **UI/Snapshot**
   - Focus mode, command palette, compact recorder, graph overlays
4. **Performance (XCTest measure)**
   - 10k-word editor scroll/edit
   - 5-minute transcription turnaround
   - Graph rebuild under capped node counts
   - Verify no heavy AI/audio tasks on main thread

---

## 5) Implementation Guardrails for Claude Code

1. **Before each phase:**
   - run targeted existing tests to establish baseline.
   - write new failing tests for that phase only.
2. **During phase:**
   - smallest production changes that satisfy tests.
   - maintain API compatibility where possible.
3. **After phase:**
   - run targeted + neighboring suites + performance checks.
   - update DocC and developer notes.
4. **Commit strategy:**
   - one commit per coherent test+implementation slice.
5. **PR template contents (mandatory):**
   - problem statement
   - tests added (red/green proof)
   - risks + rollback plan
   - performance impact
   - accessibility impact

---

## 6) Suggested File-Level Work Plan

- **Graph reliability:**
  - `Presentation/Graph/KnowledgeGraphView.swift` (extract logic out)
  - New domain files: `Domain/Graph/GraphIdentityResolver.swift`, `Domain/Graph/WikiLinkTargetResolver.swift`
  - tests under `QuartzKitTests/*Graph*`
- **AI fallback:**
  - `Domain/AI/IntelligenceEngineCoordinator.swift`
  - new `Domain/AI/AIExecutionPolicy.swift`
- **TextKit live preview:**
  - `Presentation/Editor/MarkdownTextView.swift`
  - `Presentation/Editor/MarkdownTextContentManager.swift`
  - new renderer/diff domain helpers
- **Audio intelligence + compact UI:**
  - `Domain/Audio/*`
  - `Presentation/Audio/AudioRecordingView.swift`
  - new orchestrator under `Domain/Audio/MeetingCaptureOrchestrator.swift`
- **Onboarding/help/docs:**
  - `Presentation/Onboarding/OnboardingView.swift`
  - new tutorial note seeding service
  - DocC catalog files under package docs

---

## 7) Definition of "Apple Design Award Ready" for Quartz

A release candidate qualifies only if all are true:

1. Editing remains correct and smooth under stress.
2. Graph auto-linking succeeds on realistic vault datasets with renames/aliases.
3. Audio capture/transcription/diarization works locally and gracefully degrades.
4. Quick capture + sync are trustworthy and near-instant.
5. UI polish + motion + materials feel natively Apple across platforms.
6. Accessibility and performance gates are continuously enforced in CI.

---

## 8) Immediate Next Action (Start Here)

**Execute Phase 1, Step 1:**
1. Create `GraphLinkResolutionTests` with at least 4 failing tests described above.
2. Run only those tests and capture failing output.
3. Implement minimal resolver layer.
4. Re-run tests to green.
5. Run existing graph-related regression suites.
6. Commit with message: `Phase 1: add graph identity/link resolvers with TDD coverage`.

