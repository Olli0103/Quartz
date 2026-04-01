# CODEX.md — Quartz Forensic Recovery Plan (Authoritative, Evidence-Driven)

**Scope:** Current codebase reality + executable recovery plan for Quartz (macOS/iOS/iPadOS).  
**Mode:** Ruthless, test-first, implementation-grounded.  
**Constraint:** This document reflects what is verifiably in source now, not aspirations from README/comments.

---

## 1) Executive Summary

Quartz is **partially sound but still architecturally fragmented**.

What is genuinely strong:
- A real `EditorSession` exists and is integrated as the primary editor state machine in `ContentViewModel.openNote`.
- TextKit 2-backed editor infrastructure exists (custom content manager + representables) and avoids classic SwiftUI text-binding feedback loops.
- iCloud-aware primitives exist (`NSFileCoordinator`, `NSFilePresenter`, conflict resolution surface, sync status monitoring).
- There is significant test volume in `QuartzKit/Tests`.

What is still high-risk:
- App shell remains oversized (`ContentView` still orchestrates lifecycle, deep links, restoration, command routing, exports, sync notifications, multiple sheets/alerts, bookmark persistence).
- `WorkspaceStore` still runs **boolean route algebra** (`showGraph`, `showDashboard`, `selectedNoteURL`) while also declaring `DetailRoute`; route model is not the enforced source of truth.
- NotificationCenter remains the dominant cross-subsystem transport for core behavior (editor/sync/graph/intelligence/list updates), which preserves race and ordering fragility.
- State restoration is only partially real (note path and cursor persisted, scroll persisted in scene storage but not restored into editor session from shell flow).
- Graph identity architecture is split: robust resolver exists, but edge updates still rebuild fallback title maps per update and can bypass canonical identity indexing.
- CI regression safety is weak: only tag-triggered release workflow is present; no mandatory PR/branch test workflow.

**Top risk call:** Quartz can feel modern on happy paths, but reliability under churn (rapid routing, sync conflicts, restoration, background AI updates) is not yet structurally guaranteed.

---

## 2) Reality Matrix (Current State Classification)

Legend: ✅ Exists and works · ♻️ Exists but duplicated · ⚠️ Under-tested · ☠️ Architecturally dangerous · 🧪 Claimed but not enforced · 🧩 Partially implemented · ❌ Missing

### App shell and navigation
- **ContentView / app shell / routing:** ☠️ Exists but architecturally dangerous  
  (too many responsibilities concentrated in `ContentView` event layer)
- **Workspace state:** 🧩 Partially implemented  
  (`WorkspaceStore` exists, but route truth is split across booleans + computed enum)
- **Sidebar → Note List → Editor synchronization:** 🧩 Partially implemented  
  (works via bindings + onChange tasks; not reducer-driven deterministic transitions)

### Note lifecycle flows
- **Note creation / selection / rename / delete propagation:** 🧩 Partially implemented  
  (propagation depends on NotificationCenter fan-out and cache/list refresh heuristics)
- **EditorSession:** ✅ Exists and works (primary editor session in use)
- **legacy NoteEditorViewModel:** ❌ Missing (appears removed from QuartzKit source)

### Editor behavior
- **TextKit 2 editor behavior:** ✅ Exists and works (custom TextKit 2 stack, representables)
- **Formatting / list continuation / syntax hiding / selection safety / undo-redo:** 🧩 Partially implemented  
  (substantial machinery exists; correctness under all edge cases not systemically guarded)

### Persistence and sync
- **File saving and autosave:** ✅ Exists and works (autosave + manual save paths in editor session)
- **Coordinated file I/O:** ✅ Exists and works (`CoordinatedFileWriter`, `CloudSyncService` coordinated read/write)
- **iCloud coordination and conflict handling:** 🧩 Partially implemented  
  (conflict operations exist; end-to-end deterministic conflict semantics + regression gates incomplete)
- **Security-scoped bookmarks:** 🧩 Partially implemented  
  (persist/restore exists, but duplicated in multiple views and error handling is inconsistent)
- **Scene restoration / note restoration:** 🧩 Partially implemented  
  (note path restoration exists; cursor/scroll restoration not fully closed-loop)
- **Version history:** 🧩 Partially implemented  
  (snapshot system exists, but throttled snapshots in editor are periodic and not full revision-control semantics)

### Graph + intelligence
- **Knowledge graph / backlinks / note identity:** ☠️ Exists but architecturally dangerous  
  (canonical resolver exists but graph edge update path still relies on fallback index rebuild behavior)
- **AI fallback architecture:** 🧩 Partially implemented  
  (`AIExecutionPolicy` exists; not consistently the single entrypoint across all AI services)

### Audio and media
- **Audio recording:** 🧩 Partially implemented  
  (functional, but `@MainActor` timer-driven metering/history updates create responsiveness risk)
- **Transcription:** 🧩 Partially implemented  
  (on-device speech path exists; resilience and long-session production hardening limited)
- **Diarization:** 🧩 Partially implemented  
  (heuristic K-means on handcrafted features; useful baseline, not production-grade diarization)
- **Tables / attachments / OCR:** 🧩 Partially implemented  
  (attachments/import paths and OCR services exist; full table UX parity and integration depth vary)

### Quality, accessibility, delivery
- **Accessibility:** 🧩 Partially implemented  
  (some labels + UI tests; broad accessibility contract not systematically enforced)
- **Current tests / performance tests / UI tests:** 🧩 Partially implemented  
  (many tests exist, but coverage concentration is uneven and app-level flows remain under-locked)
- **CI / regression safety:** ❌ Missing (no branch/PR CI workflow; release-only tag pipeline)

---

## 3) Evidence-Based Forensic Findings (Harsh Teardown)

### F1 — ContentView is still effectively a god object
- **Problem:** `ContentView` coordinates vault restoration/opening, deep links, scene lifecycle persistence, command routing, sheet routing, alerts, export pipeline, note-open propagation, sync/index update observers, and bookmark persistence.
- **Danger:** High blast radius for any UI/state change; hard to enforce deterministic transitions.
- **User impact:** Intermittent UI inconsistencies under rapid interactions (route changes + background updates).
- **Architectural impact:** Prevents isolation, reducer-level testability, and dependable ownership boundaries.
- **Severity:** **Critical**.
- **Concrete area:** `Quartz/ContentView.swift` (`.task`, `.onChange`, multiple `.onReceive`, restoration and vault methods).

### F2 — Workspace routing still uses brittle boolean algebra despite `DetailRoute`
- **Problem:** `WorkspaceStore` defines `DetailRoute`, but canonical state remains `showGraph` + `showDashboard` + `selectedNoteURL` with side-effectful `didSet` coupling.
- **Danger:** Invalid/intermediate states and precedence coupling remain possible; route intent is not explicit in one mutation path.
- **User impact:** Potential flicker/misrouting when multiple route flags update near-simultaneously.
- **Architectural impact:** Reducer migration stalled; route model is compatibility veneer, not SSOT.
- **Severity:** **High**.
- **Concrete area:** `WorkspaceStore` boolean properties + `currentRoute` computed adapter.

### F3 — Duplicate editor pipeline is **not** the current primary problem; legacy VM appears removed
- **Problem claim audited:** prior `NoteEditorViewModel` parallelism claim is stale.
- **Evidence:** No `NoteEditorViewModel` in QuartzKit source; `ContentViewModel.openNote` drives `EditorSession` directly.
- **Actual danger now:** stale call sites in `ContentView` still reference `viewModel?.editorViewModel` for scanner triggers, indicating incomplete cleanup and potential compile/config drift.
- **Severity:** **Medium**.
- **Concrete area:** `ContentView` references `editorViewModel`, absent from `ContentViewModel`.

### F4 — NotificationCenter remains overloaded for core data flow
- **Problem:** Core graph/intelligence/editor/list/sync events use broad NotificationCenter events instead of typed domain streams/reducers.
- **Danger:** ordering races, hidden coupling, weak compiler guarantees, hard reproducibility.
- **User impact:** Delayed or stale inspector/list/graph refreshes under concurrent edits/sync.
- **Architectural impact:** inhibits deterministic testing and causal tracing.
- **Severity:** **High**.
- **Concrete area:** `EditorSession`, `ContentView`, `NoteListStore`, `IntelligenceEngineCoordinator`, `SemanticLinkService`, `KnowledgeExtractionService`, etc.

### F5 — Graph identity model is split between robust resolver and fallback title-index rebuild path
- **Problem:** `GraphIdentityResolver` is robust, but `GraphEdgeStore.updateConnections` rebuilds title index from all URLs on each update and still has fallback simple resolution path.
- **Danger:** inconsistency under alias/path/title cases and avoidable CPU churn during active edits.
- **User impact:** missing/incorrect link wiring; graph drift after rename/alias scenarios.
- **Architectural impact:** canonical identity contract not enforced end-to-end.
- **Severity:** **High**.
- **Concrete area:** `GraphCache.swift` (`GraphEdgeStore`) + `GraphIdentityResolver.swift`.

### F6 — Restoration is only partially wired through
- **Problem:** scene storage persists note path/cursor/scroll values, but shell restoration only reliably reopens note path; cursor/scroll reinjection into active editor on reopen is incomplete at shell level.
- **Danger:** perceived state loss across relaunch/background transitions.
- **User impact:** reopened note may not restore exact editing context.
- **Architectural impact:** weak lifecycle determinism and UX trust.
- **Severity:** **Medium**.
- **Concrete area:** `ContentView` restoration methods and scene storage usage.

### F7 — Bookmark persistence is duplicated and error semantics are inconsistent
- **Problem:** bookmark persist/restore logic appears in both `ContentView` and `VaultPickerView` with near-duplicate code.
- **Danger:** divergence in stale-bookmark handling and recovery behavior.
- **User impact:** vault reopen reliability differs by entry path.
- **Architectural impact:** duplicated security-critical flow.
- **Severity:** **High**.
- **Concrete area:** bookmark methods in `ContentView` and `VaultPickerView`.

### F8 — Audio pipeline puts frequent metering/history mutation on MainActor
- **Problem:** `AudioRecordingService` is `@MainActor` with recurring timers mutating metering state/history at ~12Hz plus duration timer.
- **Danger:** avoidable contention with typing/rendering on slower devices or heavy UI states.
- **User impact:** editor responsiveness degradation during recording.
- **Architectural impact:** processing/UI concerns coupled in single actor.
- **Severity:** **Medium-High**.
- **Concrete area:** `AudioRecordingService` timers and mutable waveform history.

### F9 — AI fallback policy exists but is not a universally enforced choke point
- **Problem:** `AIExecutionPolicy` is substantial, but intelligence services still contain independent behavior and notification pipelines.
- **Danger:** inconsistent fallback/health semantics across AI features.
- **User impact:** uneven behavior across concept extraction vs other AI operations when provider degrades.
- **Architectural impact:** fractured reliability guarantees.
- **Severity:** **Medium-High**.
- **Concrete area:** `AIExecutionPolicy` vs `KnowledgeExtractionService`/`SemanticLinkService` orchestration patterns.

### F10 — CI regression gate is absent for normal development
- **Problem:** only release workflow (`push tags v*`) is present.
- **Danger:** regressions can merge without automated gate on branches/PRs.
- **User impact:** quality drift and unpredictable releases.
- **Architectural impact:** weak enforcement of TDD/perf promises.
- **Severity:** **Critical**.
- **Concrete area:** `.github/workflows/release.yml` only.

### F11 — `WorkspaceView` still leaks container-level dependency resolution
- **Problem:** view directly resolves providers via `ServiceContainer.shared` for graph/dashboard.
- **Danger:** hidden global dependencies in view layer.
- **User impact:** hard-to-reproduce behavior in test and multi-window contexts.
- **Architectural impact:** inversion-of-control violation.
- **Severity:** **Medium**.
- **Concrete area:** `WorkspaceView` detail column provider construction.

### F12 — File coordination exists, but conflict semantics are not fully encoded as domain state transitions
- **Problem:** Cloud conflict operations exist, but user-facing resolution semantics are still mostly operation-driven, not explicit state machine transitions with post-conditions.
- **Danger:** hard to guarantee no lost updates under concurrent edits + sync.
- **User impact:** rare but severe data trust incidents.
- **Architectural impact:** difficult to prove correctness.
- **Severity:** **High**.
- **Concrete area:** `CloudSyncService`, conflict resolver views, editor external-modification handling.

---

## 4) Optimization Ledger (Mandatory)

| Subsystem | Current inefficiency | Likely root cause | User-visible cost | Expected benefit if fixed | Measurement strategy | Regression guard |
|---|---|---|---|---|---|---|
| Typing latency | Work fan-out on save/notifications and frequent highlighter/analysis updates | Notification-based cascading + shared main-thread pressure | Typing jitter under heavy background activity | Lower input latency, smoother cursor | Signpost keystroke→frame and keystroke→highlight completion | XCTest performance budget test + signpost threshold CI check |
| Editor highlighting/parsing | Repeated broad highlight/analysis passes | Invalidation granularity not fully constrained in all paths | Occasional stutter on long notes | Reduced CPU spikes | Measure parse/highlight duration by document size buckets | Perf test with 10k+ word fixture and strict percentile budget |
| View invalidation boundaries | Shell-level state changes reevaluate large view surface | Oversized `ContentView` orchestration | UI flicker/lag on route/sheet changes | Better frame pacing and lower recomposition | SwiftUI Instruments diff before/after coordinator split | UI performance snapshot test on route toggles |
| Vault loading | Multiple service bootstraps + indexing passes at load | Monolithic `loadVault` orchestration | Slow first interactive note list/editor readiness | Faster time-to-interactive | Measure TTI from vault open to note list populated + first note open | Integration test with synthetic vault and SLA |
| Note switching | Secondary async refreshes triggered post-switch | cross-service side effects | Perceived switch latency | More immediate editor readiness | Trace note-select→editor mounted→text interactive | UI test with note-switch latency assertion |
| List refresh | Full refresh fallback frequently used | Notification granularity coarse | list flicker, wasted work | smoother list updates | Compare full refresh count vs targeted refresh count | Unit tests forcing targeted updates for common mutations |
| Graph rebuilds | Title index rebuild on each connection update | non-incremental fallback logic in edge store | background CPU churn | lower CPU and consistent wiring | Track graph update duration and frequency | Graph contract + perf tests on large vault |
| AI fallback latency | parallel/serial fallback behavior varies by entrypoint | policy not universal | inconsistent wait times on provider failure | predictable degraded-mode UX | record remote timeout→fallback completion latency | AI fallback integration tests with deterministic stubs |
| File I/O | repeated coordinator wraps + polling for iCloud downloads | no unified I/O scheduler/priority model | sporadic delays | more predictable save/read latency | signpost read/write timings + iCloud download wait timings | stress tests with mocked delayed coordination |
| Audio memory/timers | level history mutate on main, fixed history shifts | main-thread timer model | UI hitch during recording | smoother editor + recording coexistence | frame-time + main-thread occupancy during 30-60 min record | long-session perf/memory XCTest with threshold |
| Main-thread work | mixed UI + service orchestration on main | shell/service coupling | reduced responsiveness | better parallelism | Main Thread Checker + Instruments time profile | CI lint/check for MainActor heavy operations in services |
| Caching/indexing | duplicate index-like maps (graph title index + resolver indices) | split identity architecture | unnecessary recompute | less churn, higher consistency | measure memory and rebuild time of identity+graph updates | identity contract tests + perf benchmarks |
| Object churn | repeated formatter creation in hot paths; repeated service setup in flows | convenience over pooling/context objects | alloc overhead | reduced GC/alloc pressure | Allocations instrument sampling | microbenchmarks for hot path allocations |

---

## 5) Core Architectural Recommendations (Directives)

1. **Make route state explicit and singular.**  
   Replace boolean routing state in `WorkspaceStore` with a single mutable `DetailRoute` + reducer-style transition API. Keep compatibility shims only temporarily behind tests.

2. **Split shell orchestration now.**  
   Break `ContentView` into:
   - `WorkspaceShellView` (layout only),
   - `VaultLifecycleCoordinator`,
   - `PresentationRouter` (sheets/alerts),
   - `AppEventBridge` (external notifications/deeplinks).

3. **Enforce EditorSession as sole editor state owner and remove stale references.**  
   Remove/replace `editorViewModel` references in shell code; scanner hooks must target explicit APIs on `EditorSession` or dedicated scanner coordinator.

4. **Replace NotificationCenter for critical domain flows with typed streams/reducers.**  
   Keep NotificationCenter only for external integrations/legacy interoperability. Internal core flows must become strongly typed async streams.

5. **Unify note identity contract.**  
   `GraphIdentityResolver` (or successor) must be the single resolver for graph/backlinks/AI references. Remove per-update fallback `titleIndex` rebuild behavior.

6. **Centralize bookmark authority.**  
   One `VaultAccessManager` for bookmark create/restore/stale refresh/error policy. Remove duplicate logic from views.

7. **Introduce sync conflict state machine.**  
   Model conflict lifecycle (`detected -> diff_loaded -> user_choice -> coordinated_apply -> verified_clean`) with explicit invariants and tests.

8. **Move heavy non-UI loops off MainActor.**  
   Audio metering processing, semantic/graph recomputation, and indexing orchestration should use background actors/tasks with main-thread projection only for UI state.

9. **Eliminate view-layer service resolution.**  
   No `ServiceContainer.shared` calls inside view rendering paths.

10. **Add real CI enforcement.**  
   PR/branch CI must run unit/integration/UI/perf smoke suites and fail on regressions.

---

## 6) Fully Working App Mandate (User-Flow Contract)

Quartz is "fully working" only when all flows below are deterministic and test-verified:

1. **Open vault** from picker/panel and load tree+list without stale/empty intermediate state glitches.
2. **Relaunch and retain vault access** via security-scoped bookmark with stale bookmark refresh handled.
3. **Restore prior note** on relaunch with valid path and preserve editing context (cursor + visible region).
4. **Create note and see it instantly in note list**, selectable without manual refresh.
5. **Edit continuously without flicker/cursor jump/state loss** during background indexing/AI activity.
6. **Save safely** (autosave + manual save) with coordinated I/O and durable file contents.
7. **Rename/move/delete consistently** across sidebar, note list, editor, graph, spotlight/index previews.
8. **Survive external file changes** (present clear conflict/external-modification UX, no silent overwrite).
9. **Maintain graph/inspector/preview/search consistency** after edits/renames/deletes/conflict resolutions.
10. **Export succeeds** for supported formats with correct content.
11. **Accessibility remains intact** (labels, focus order, dynamic type/reduce motion behavior as applicable).

No feature is "done" unless these user flows remain green with synthetic fixtures and automated tests.

---

## 7) Strict TDD Recovery Plan (Phased, Foundational Risks First)

### Phase 0 — Stabilize Truth Boundaries (Routing + Shell Decomposition)
- **Objective:** remove state ambiguity and shell blast radius.
- **Why:** current route algebra + god-view behavior is the highest multiplier of defects.
- **Defects addressed:** F1, F2, F11.
- **Optimization opportunities:** view invalidation boundaries, note switching latency.
- **Failing tests first:**
  - `WorkspaceRouteReducerTests`
  - `ContentShellEventIsolationTests`
  - `DashboardGraphNoteMutualExclusionTests`
- **Implementation direction:** introduce reducer-backed route state; move lifecycle/presentation logic out of `ContentView`.
- **Refactor direction:** remove direct service resolution in views.
- **Regression protection:** snapshot tests for route transitions; UI smoke for sidebar/list/detail coherence.
- **Exit criteria:** no boolean route coupling in store; shell file significantly reduced and coordinatorized.

### Phase 1 — Editor & Restoration Determinism
- **Objective:** guarantee stable editor lifecycle and restoration behavior.
- **Why:** editing trust is the product core.
- **Defects addressed:** F3, F6.
- **Optimization opportunities:** typing latency, note switching smoothness.
- **Failing tests first:**
  - `EditorSessionRestorationTests` (cursor/scroll on reopen)
  - `OpenNoteScannerHookTests` (no stale editor VM references)
  - `ExternalChangeNoCursorLossTests`
- **Implementation direction:** remove stale `editorViewModel` callsites; explicit restoration API from shell→session.
- **Refactor direction:** unify selection+session open sequencing.
- **Regression protection:** end-to-end UI test: relaunch restores note and editing context.
- **Exit criteria:** restoration path verified across platform targets; no stale editor API references.

### Phase 2 — Identity and Graph Integrity
- **Objective:** enforce single note identity contract across graph/backlinks/intelligence.
- **Why:** graph correctness is impossible with split identity semantics.
- **Defects addressed:** F5.
- **Optimization opportunities:** graph rebuild CPU, repeated recomputation.
- **Failing tests first:**
  - `GraphIdentityCanonicalResolutionTests`
  - `AliasPathRenameRewireTests`
  - `GraphIncrementalUpdatePerfTests`
- **Implementation direction:** remove fallback title-index rebuild path from hot update loop; all resolution through canonical resolver/index.
- **Refactor direction:** separate identity indexing from edge updates.
- **Regression protection:** large-vault fixture with deterministic edge assertions.
- **Exit criteria:** identical resolution outcomes for filename/title/alias/path links; update perf budget met.

### Phase 3 — Sync, Bookmark, and Conflict Hardening
- **Objective:** make vault access and conflict resolution robust and explicit.
- **Why:** data integrity failures are catastrophic.
- **Defects addressed:** F7, F12.
- **Optimization opportunities:** file I/O latency predictability.
- **Failing tests first:**
  - `VaultBookmarkLifecycleTests`
  - `ConflictStateMachineTests`
  - `CoordinatedWriteConflictRaceTests`
- **Implementation direction:** centralize bookmark logic in `VaultAccessManager`; formal conflict state transitions with invariant checks.
- **Refactor direction:** remove bookmark duplication from views.
- **Regression protection:** integration harness simulating external writes + unresolved conflicts.
- **Exit criteria:** deterministic vault reopen and conflict lifecycle with no silent data loss paths.

### Phase 4 — Typed Eventing and AI Policy Unification
- **Objective:** replace NotificationCenter core paths with typed streams and enforce one AI execution policy surface.
- **Why:** hidden event coupling blocks reliability.
- **Defects addressed:** F4, F9.
- **Optimization opportunities:** AI fallback latency consistency, reduced event churn.
- **Failing tests first:**
  - `TypedEventOrderingTests`
  - `AIExecutionPolicyEnforcementTests`
  - `InspectorConsistencyUnderConcurrentUpdatesTests`
- **Implementation direction:** event bus/state reducer per subsystem; adapter layer for legacy notifications.
- **Refactor direction:** shrink observer counts in stores/sessions.
- **Regression protection:** deterministic replay tests for concurrent save/sync/intelligence updates.
- **Exit criteria:** critical flows no longer require NotificationCenter observers.

### Phase 5 — Audio & Long-Session Performance Hardening
- **Objective:** make recording/transcription/diarization usable under long sessions without UI degradation.
- **Why:** premium workflow requires sustained performance.
- **Defects addressed:** F8.
- **Optimization opportunities:** main-thread load, memory stability.
- **Failing tests first:**
  - `AudioMainThreadBudgetTests`
  - `LongRecordingMemoryStabilityTests`
  - `DiarizationQualityFixtureTests`
- **Implementation direction:** split processing actor from UI projection model; bounded ring buffer for metering history.
- **Refactor direction:** isolate capture/transcription/diarization orchestration state machine.
- **Regression protection:** 60-minute synthetic session perf tests.
- **Exit criteria:** typing/frame budgets remain within target while recording/transcribing.

### Phase 6 — CI and Regression Governance
- **Objective:** ensure no regression reaches mainline unnoticed.
- **Why:** current release-only workflow is insufficient.
- **Defects addressed:** F10.
- **Optimization opportunities:** institutionalized perf monitoring.
- **Failing tests first:** CI pipeline validation tests and required-status checks.
- **Implementation direction:** add PR/branch workflows for unit/integration/UI/perf smoke suites.
- **Refactor direction:** test suite partitioning and runtime budget controls.
- **Regression protection:** mandatory checks + flaky-test quarantine policy + baseline update process.
- **Exit criteria:** merges blocked on failing automated quality gates.

---

## 8) Zero Manual QA Execution Model (Mandatory)

Manual spot-checking is supplementary only. Autonomous agent must produce and run:

1. **Targeted unit tests** for every changed domain contract.
2. **Integration tests** for cross-subsystem flows (vault load, note lifecycle, sync/graph updates).
3. **UI tests** for critical user journeys (open vault, create/edit/save, restore, conflict handling).
4. **Performance tests** with enforceable budgets (typing latency, graph update time, long-session memory).
5. **Smoke flow tests** as fast gate on every PR.
6. **Synthetic fixtures** for large vaults, conflict files, renamed/aliased note sets, long audio sessions.
7. **Stubs/mocks** for AI providers and hardware-dependent components (microphone, speech, network AI).
8. **Regression ledger** in-repo: for each fixed bug, add failing test + permanent guard + benchmark where relevant.

No phase may be marked complete without new tests proving the fixed behavior and guarding against relapse.

---

## 9) Definition of Done (Strict, Non-Negotiable)

Quartz is done only when all are true:

1. **Architecture truthfulness:** route/editor/identity/bookmark/conflict ownership is explicit and singular.
2. **Flow reliability:** all mandate flows in Section 6 pass automated tests across supported platforms.
3. **Data safety:** coordinated I/O + conflict resolution have deterministic, test-verified outcomes (no silent loss).
4. **Performance:** documented budgets for typing, note switching, graph updates, and long audio sessions are consistently met.
5. **Accessibility:** critical screens and core interactions pass accessibility checks and UI tests.
6. **CI enforcement:** PR/branch workflows enforce quality gates; failures block merge.
7. **No illusion of progress:** "cleaner structure" without verified user-flow reliability does **not** count as done.

If any item above is unmet, Quartz is not recovered.
