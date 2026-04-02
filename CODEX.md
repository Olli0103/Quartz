# CODEX.md — Quartz Forensic Recovery Plan (Authoritative, Evidence-Driven)

**Scope:** Real implementation audit + executable recovery blueprint for Quartz (macOS, iOS, iPadOS).  
**Method:** Evidence from source only. No README optimism, no architectural fiction.  
**Goal:** Recover Quartz to a fully working, test-enforced, performance-stable premium native Markdown product.

---

## 1) Executive Summary

### Blunt assessment
Quartz is **structurally improving but still partially fragmented**.

### What is solid right now
- `EditorSession` is the primary editor state machine and is actually wired as the active editor pipeline via `ContentViewModel.openNote` and `WorkspaceView`.
- Routing has improved: `WorkspaceStore` now has an explicit `route: DetailRoute` and compatibility accessors.
- Vault lifecycle has been extracted into `VaultCoordinator` + `VaultAccessManager` (bookmark persistence/restoration is no longer in `ContentView`).
- Coordinated file I/O exists (`CoordinatedFileWriter`, `CloudSyncService`, `VersionHistoryService`) and is not hand-wavy.
- CI exists (`.github/workflows/ci.yml`) and runs multi-platform builds + package tests.

### Critical current risks
- `ContentView` remains overburdened with lifecycle/event glue (deep links, commands, restoration, sheet routing, notification fan-in, export flow).
- NotificationCenter is still core infrastructure (editor, note list, AI, sync, indexing). Typed eventing exists (`DomainEventBus`) but adoption is partial.
- `WorkspaceView` still resolves dependencies via `ServiceContainer.shared` inside view rendering paths.
- Conflict state machine exists but is not wired into the conflict UI/service flows.
- Graph identity model is mixed: canonical resolver support exists, but fallback title indexing remains in hot paths when resolver is absent.
- Audio recording still runs timer-driven update loops on `@MainActor`; improved metering processor exists but UI state churn remains high-frequency.

### Structural status
Quartz is **partially sound**: strong building blocks exist, but deterministic cross-subsystem behavior under churn (sync conflicts, external edits, rapid route changes, long sessions) is not yet guaranteed.

---

## 2) Reality Matrix

Legend:  
✅ Exists and works · ♻️ Exists but duplicated · ⚠️ Exists but under-tested · ☠️ Exists but architecturally dangerous · 🧪 Claimed but not truly enforced · 🧩 Partially implemented · ❌ Missing

### Shell, routing, and workspace
- **ContentView / app shell / routing:** ☠️ (improved, but still orchestration-heavy)
- **Workspace state:** ✅ (`route` SSOT exists in `WorkspaceStore`)
- **Sidebar → Note List → Editor synchronization:** 🧩 (works, but still event-bridged and async-callback heavy)

### Note lifecycle
- **Note creation / selection / rename / delete propagation:** 🧩 (works with mixed immediate local mutation + notification-based refresh)
- **EditorSession:** ✅ (primary state owner)
- **legacy NoteEditorViewModel:** ❌ (not present in source)

### Editor behavior
- **TextKit 2 editor behavior:** ✅ (custom text content manager + representables in place)
- **Formatting / list continuation / syntax hiding / selection safety / undo-redo:** 🧩 (broad implementation exists, edge-case determinism not fully locked)

### Persistence, sync, restoration
- **File saving and autosave:** ✅ (`EditorSession.save`, autosave scheduling)
- **Coordinated file I/O:** ✅ (`NSFileCoordinator` wrappers in writer/sync/history)
- **iCloud coordination and conflict handling:** 🧩 (real operations + UI, but no fully enforced state-machine contract)
- **Security-scoped bookmarks:** ✅ (centralized manager exists and used)
- **Scene restoration / note restoration:** 🧩 (path + cursor + scroll restoration exists but timing uses delayed best-effort)
- **Version history:** 🧩 (snapshot-based history exists; not full transactional revision model)

### Graph + intelligence
- **Knowledge graph / backlinks / note identity:** 🧩 (good primitives; fallback resolution path still tolerated)
- **AI fallback architecture:** 🧩 (`AIExecutionPolicy` exists; not uniformly enforced across AI services)

### Audio and media
- **Audio recording:** 🧩 (functional; main-thread timer/state pressure remains risk)
- **Transcription:** 🧩 (on-device pipeline implemented; operational hardening gaps remain)
- **Diarization:** 🧩 (heuristic k-means approach; baseline only)
- **Tables / attachments / OCR:** 🧩 (feature surface exists but integration depth and UX completeness vary)

### Quality and delivery
- **Accessibility:** 🧩 (baseline labels/tests exist; no comprehensive accessibility contract gate)
- **Current tests / performance tests / UI tests:** ⚠️ (large volume, uneven enforcement and flow depth)
- **CI / regression safety:** 🧩 (CI exists and runs builds/tests; no strict performance/UI flow gate discipline yet)

---

## 3) Evidence-Based Forensic Findings

## F1 — `ContentView` is still a high-risk orchestration hub
- **Problem:** It still owns initialization, vault restoration fallback, scene restoration writes, deep-link handling, command dispatch, multiple notification subscriptions, export plumbing, and sheet/alert composition.
- **Why dangerous:** State transitions are spread across `.task`, `.onChange`, `.onReceive`; causal ordering is implicit.
- **User impact:** Intermittent mis-sequencing risk during startup/relaunch and rapid state changes.
- **Architectural impact:** Difficult to unit-test deterministic transitions.
- **Severity:** Critical.
- **Evidence area:** `Quartz/ContentView.swift`.

## F2 — Routing SSOT exists, but legacy compatibility accessors still dominate call sites
- **Problem:** `WorkspaceStore.route` is canonical, but most UI code still toggles `showGraph/showDashboard/selectedNoteURL` accessors.
- **Why dangerous:** Transitional API slows full reducer-style route discipline and can hide route intent.
- **User impact:** Lower risk than before, but route semantics remain implicit at call sites.
- **Architectural impact:** Migration incomplete.
- **Severity:** Medium.
- **Evidence area:** `WorkspaceStore`, `ContentView`, `WorkspaceView`.

## F3 — Parallel legacy editor VM is not present (previous claim invalid)
- **Problem audited:** A legacy `NoteEditorViewModel` running in parallel is not found.
- **Reality:** `EditorSession` is current primary pipeline.
- **Residual risk:** TODO comments still reference historical architecture; scanner flow is still incomplete/placeholder from app state to editor presentation.
- **Severity:** Medium (documentation/flow gap, not dual-VM corruption).
- **Evidence area:** repo-wide search for `NoteEditorViewModel` and `editorViewModel`; scanner TODO in `ContentView`.

## F4 — NotificationCenter remains core transport despite typed event bus availability
- **Problem:** Numerous subsystems rely on NotificationCenter for critical updates (save, rename, preview cache, AI updates, sync conflict events).
- **Why dangerous:** Weak type safety, hidden coupling, ordering ambiguity.
- **User impact:** Possible stale UI sections or race-induced lag under concurrency.
- **Architectural impact:** Deterministic replay/testing remains hard.
- **Severity:** High.
- **Evidence area:** `EditorSession`, `NoteListStore`, `SidebarViewModel`, `SemanticLinkService`, `KnowledgeExtractionService`, `CloudSyncService`; `DomainEventBus` exists but partial adoption.

## F5 — `WorkspaceView` still performs service resolution in render path
- **Problem:** `ServiceContainer.shared.resolveVaultProvider()` is called directly inside detail column composition.
- **Why dangerous:** Hidden global dependencies in view layer, poor testability, harder multi-window isolation.
- **User impact:** Subtle inconsistency risks across windows/scenes.
- **Architectural impact:** Violates dependency injection boundaries.
- **Severity:** Medium.
- **Evidence area:** `QuartzKit/.../WorkspaceView.swift`.

## F6 — Conflict architecture is split: rich operations exist, but state machine is disconnected
- **Problem:** `ConflictStateMachine` exists but appears unused by current conflict resolver flows.
- **Why dangerous:** Conflict correctness is operation-sequence dependent, not state-enforced.
- **User impact:** Higher risk of edge-case conflict UX inconsistency.
- **Architectural impact:** Invariants are not enforced where they matter.
- **Severity:** High.
- **Evidence area:** `Domain/Sync/ConflictStateMachine.swift` vs conflict views/services usage.

## F7 — Bookmark handling is centralized but still duplicated at workflow edges
- **Problem:** Manager exists and is used, but both `VaultCoordinator` and `VaultPickerView` directly drive bookmark persistence/restore entrypoints.
- **Why dangerous:** Divergence risk in error UX and side-effect sequencing.
- **User impact:** Inconsistent vault-open/reopen behavior by entry path.
- **Architectural impact:** Flow standardization incomplete.
- **Severity:** Medium.
- **Evidence area:** `VaultCoordinator.swift`, `VaultPickerView.swift`, `VaultAccessManager.swift`.

## F8 — Restoration exists but is timing-based, not handshake-based
- **Problem:** Cursor/scroll restoration relies on delayed `Task.sleep(100ms)` after selection restore.
- **Why dangerous:** Race-prone on slow devices/large notes/layout delays.
- **User impact:** Occasionally wrong cursor/scroll restoration.
- **Architectural impact:** Non-deterministic lifecycle dependency.
- **Severity:** Medium.
- **Evidence area:** `ContentView.restoreSelectedNoteIfNeeded`.

## F9 — Graph identity is improved but fallback path still exists
- **Problem:** `GraphEdgeStore` uses canonical resolver when configured, otherwise rebuilds fallback title index.
- **Why dangerous:** Resolver not guaranteed everywhere; fallback can create ambiguity and extra compute.
- **User impact:** Mis-resolved links in ambiguous title scenarios.
- **Architectural impact:** Single identity contract not mandatory.
- **Severity:** Medium-High.
- **Evidence area:** `GraphEdgeStore` + `GraphIdentityResolver` integration points.

## F10 — AI fallback policy is not universal
- **Problem:** `KnowledgeExtractionService` can route through `AIExecutionPolicy`, but `SemanticLinkService` and other paths do not share one enforced policy funnel.
- **Why dangerous:** Inconsistent degraded-mode behavior.
- **User impact:** Feature-to-feature variability under provider failures.
- **Architectural impact:** Reliability semantics fragmented.
- **Severity:** Medium.
- **Evidence area:** `AIExecutionPolicy`, `KnowledgeExtractionService`, `SemanticLinkService`.

## F11 — Audio pipeline still pushes frequent UI state on main actor
- **Problem:** Metering and waveform updates are timer-driven on main actor with frequent task hops.
- **Why dangerous:** Main-thread contention during typing + recording.
- **User impact:** Potential typing/frame jitter while recording.
- **Architectural impact:** Processing/UI concerns not fully isolated.
- **Severity:** Medium.
- **Evidence area:** `AudioRecordingService`.

## F12 — CI exists, but regression governance is not strict enough for recovery mission
- **Problem:** CI runs builds/tests, but there is no explicit mandatory performance budget gate or high-value end-to-end flow gate policy encoded in this plan.
- **Why dangerous:** Slow regressions and user-flow regressions can leak.
- **User impact:** Quality drift.
- **Architectural impact:** Recovery cannot be proven durable.
- **Severity:** Medium.
- **Evidence area:** `.github/workflows/ci.yml`.

---

## 4) Optimization Ledger

| Subsystem | Current inefficiency | Likely root cause | User-visible cost | Expected benefit | Measurement strategy | Regression guard |
|---|---|---|---|---|---|---|
| Typing latency | Save/index/AI side effects fan out during edits | Notification-driven cascades + mixed main-actor workloads | Keystroke jitter on larger notes | Smoother typing | Signpost keypress→frame and keypress→save latency | Performance XCTest threshold per doc size |
| Highlighting/parsing | Frequent broad re-analysis/highlight schedules | Conservative invalidation windows | Stutter on long docs | Lower CPU spikes | Measure parse/highlight duration P50/P95 by size buckets | Perf test fixtures (10k, 50k, 100k chars) |
| View invalidation | Shell handles many concerns, broad recomposition risk | `ContentView` coordination density | UI flicker/latency under route/sheet churn | Better frame stability | SwiftUI Instruments body recomposition counts | Route transition snapshot + perf CI |
| Vault loading | Many startup tasks launched in one sequence | Monolithic `loadVault` bootstrapping | Slower time-to-interactive | Faster first usable editor/list | TTI from open-vault action to note list + first note editable | Integration SLA test with synthetic vault |
| Note switching | Async session load + concurrent side effects | No explicit transition barrier | Perceived switching lag | Faster note open confidence | Trace select→loaded→interactive milestones | UI test latency assertions |
| List refresh | `refreshSingleItem` still reads full preview set | Repository API granularity | List churn and extra work | Lower refresh cost | Count full-cache fetches per mutation | Unit test requiring O(1)-style targeted path when possible |
| Graph updates | Fallback index rebuild when resolver missing | Resolver not mandated | CPU overhead + ambiguous resolution | Predictable graph correctness | Measure updateConnections duration on large vault fixtures | Identity contract tests + perf budget |
| AI fallback latency | Mixed policy entrypoints | Non-unified policy enforcement | Inconsistent degraded behavior | Stable AI UX | Measure timeout→fallback completion across features | Integration tests with forced provider failures |
| File I/O | Multiple coordination paths with mixed abstractions | No unified I/O scheduler/priority policy | Variable save/open latency | Better I/O predictability | Signpost coordinated read/write durations | Stress test with synthetic iCloud delays |
| Audio memory/timers | Frequent main-actor waveform updates | UI/proc boundary still chatty | Recording can degrade editor smoothness | Stable recording + editing | Frame time + main-thread occupancy during 30-60 min session | Long-session perf test gate |
| Main-thread pressure | UI + orchestration + observer callbacks converge on main | Global event patterns | Responsiveness degradation under load | Better concurrency headroom | Time Profiler main-thread % during stress scenarios | Static lint + perf baseline check |
| Repeated recomputation | Multiple scans/builds for mappings and caches | Incremental indexing not universal | Battery/CPU waste | Better efficiency | Count recompute operations per user action | Counter-based regression assertions |

---

## 5) Core Architectural Recommendations (Directives)

1. **Finish route migration:** Make `route` the only route mutation API in UI code; retire direct compatibility toggles.
2. **Split `ContentView` event hub:** Extract startup/lifecycle/deep-link/notification orchestration into dedicated coordinators with explicit state transitions.
3. **Adopt typed event bus for core flows:** Keep NotificationCenter only at platform boundaries; internal note/sync/index/AI events must be typed and replayable.
4. **Inject services at composition boundary only:** Remove `ServiceContainer.shared` lookups from view bodies.
5. **Wire `ConflictStateMachine` into conflict UI/services:** Every conflict flow must pass explicit transitions and postconditions.
6. **Make graph identity resolver mandatory:** Fail fast if resolver not configured for graph-building contexts; remove fallback title heuristics from production path.
7. **Replace timing-based restoration with readiness handshake:** Restore cursor/scroll only after editor explicitly reports mounted + content-applied.
8. **Unify vault-open entrypoints:** All open/create/restore flows should go through one coordinator API surface with identical error semantics.
9. **Enforce a single AI execution policy facade:** All remote/on-device AI operations route through one policy contract.
10. **Move high-frequency audio projection off main where possible:** Keep main actor for UI assignment only, with bounded update cadence.
11. **Convert vault load and indexing to staged pipeline:** explicit “minimum interactive state” before heavy background indexing.
12. **Make performance budgets merge-blocking in CI:** typing, switching, graph update, and long-session audio must have enforced thresholds.

---

## 6) Fully Working App Mandate (User-Flow Contract)

Quartz is “fully working” only when all flows are deterministic and automated:

1. Open vault (existing or new) and reach interactive workspace with populated sidebar/list.
2. Relaunch app and retain vault access through bookmark restoration.
3. Restore previous note plus cursor and visible region reliably.
4. Create note and observe immediate note-list visibility + selectable editor load.
5. Edit continuously without flicker/cursor jump/state loss during background indexing/AI.
6. Autosave + manual save must persist durable content with coordinated I/O semantics.
7. Rename/move/delete must stay consistent across sidebar, list, editor, graph, preview/search index.
8. External file modification/conflicts must surface clear resolution path with no silent data loss.
9. Graph/inspector/preview/search must converge to consistent state after every mutation.
10. Export flows must produce correct files and complete without corrupting session state.
11. Accessibility contract (labels, keyboard/focus order, dynamic type/reduce motion behavior where applicable) must remain intact.

If any one of these is non-deterministic, Quartz is not fully recovered.

---

## 7) Strict TDD Recovery Plan (Foundational Risk First)

## Phase 0 — Deterministic Shell and Routing
- **Objective:** Remove orchestration ambiguity and finalize route SSOT usage.
- **Why:** Most regressions currently originate from cross-cutting shell/event glue.
- **Defects addressed:** F1, F2, F5.
- **Optimization addressed:** view invalidation and note-switch responsiveness.
- **Write failing tests first:**
  - `RouteMutationSurfaceTests` (only route API mutations)
  - `ContentLifecycleOrderingTests`
  - `WorkspaceDependencyInjectionTests`
- **Implementation direction:** isolate lifecycle/deep-link/notification handling from `ContentView`; route reducer semantics.
- **Refactor direction:** eliminate container resolution in view bodies.
- **Regression protection:** route transition replay tests + smoke UI flow tests.
- **Exit criteria:** no direct route boolean toggling in app shell call sites; shell complexity materially reduced.

## Phase 1 — Restoration and Note Lifecycle Determinism
- **Objective:** Replace timing heuristics with explicit readiness contracts.
- **Why:** restoration trust is core to premium editor UX.
- **Defects addressed:** F8 plus note lifecycle edge races.
- **Optimization addressed:** note switching and startup predictability.
- **Write failing tests first:**
  - `EditorRestorationHandshakeTests`
  - `RelaunchRestoresCursorAndViewportTests`
  - `CreateRenameDeletePropagationConsistencyTests`
- **Implementation direction:** editor-mounted readiness signal; deterministic restoration pipeline.
- **Refactor direction:** unify note lifecycle propagation through typed events.
- **Regression protection:** integration tests with synthetic vault fixtures.
- **Exit criteria:** restoration flow is race-free across cold launch, background/foreground, and note switches.

## Phase 2 — Eventing Unification and Conflict Correctness
- **Objective:** Move core domain traffic off NotificationCenter; enforce conflict state machine.
- **Why:** reliability cannot be proven with implicit event buses.
- **Defects addressed:** F4, F6.
- **Optimization addressed:** reduced redundant refresh/recomputation.
- **Write failing tests first:**
  - `TypedEventOrderingTests`
  - `ConflictStateMachineIntegrationTests`
  - `NoSilentConflictResolutionTests`
- **Implementation direction:** typed domain event adapters + conflict flow state enforcement.
- **Refactor direction:** remove critical NotificationCenter observers progressively.
- **Regression protection:** deterministic replay harness for save/rename/delete/conflict sequences.
- **Exit criteria:** conflict UI/service path is state-machine backed end-to-end; typed events cover critical note/sync flows.

## Phase 3 — Identity, Graph, and AI Consistency
- **Objective:** enforce one identity model + one AI fallback policy facade.
- **Why:** graph and intelligence must agree on note identity and degraded behavior.
- **Defects addressed:** F9, F10.
- **Optimization addressed:** graph update cost and AI fallback latency variance.
- **Write failing tests first:**
  - `CanonicalIdentityResolutionTests`
  - `GraphIncrementalUpdatePerfTests`
  - `UnifiedAIPolicyEnforcementTests`
- **Implementation direction:** mandatory resolver injection; shared AI policy interface across services.
- **Refactor direction:** remove fallback ambiguity and duplicate policy logic.
- **Regression protection:** large-vault deterministic graph fixtures + AI failure simulation matrix.
- **Exit criteria:** graph/backlinks/AI references converge under rename/alias/path scenarios.

## Phase 4 — Audio and Long-Session Performance Hardening
- **Objective:** preserve editor responsiveness during recording/transcription workloads.
- **Why:** premium workflow must tolerate long sessions.
- **Defects addressed:** F11.
- **Optimization addressed:** main-thread occupancy and memory stability.
- **Write failing tests first:**
  - `AudioMainThreadBudgetTests`
  - `RecordingWhileEditingLatencyTests`
  - `LongSessionMemoryStabilityTests`
- **Implementation direction:** throttle projection updates, isolate processing, bound waveform buffers.
- **Refactor direction:** explicit audio state machine with minimal main-thread writes.
- **Regression protection:** automated 60-minute synthetic session tests.
- **Exit criteria:** typing/frame budgets remain within target while recording and post-processing.

## Phase 5 — CI Governance and Non-Negotiable Gates
- **Objective:** block regressions automatically.
- **Why:** recovery fails without enforcement.
- **Defects addressed:** F12.
- **Optimization addressed:** continuous performance budget integrity.
- **Write failing tests first:**
  - `CIBudgetGateValidationTests`
  - `CriticalFlowSmokeMatrixTests`
- **Implementation direction:** add mandatory performance + critical-flow UI gates to CI.
- **Refactor direction:** test partitioning for reliable runtime/flake control.
- **Regression protection:** baseline versioning policy + flaky quarantine protocol.
- **Exit criteria:** merges fail on performance or critical flow regression.

---

## 8) Zero Manual QA Execution Model

Manual spot checks are not accepted as evidence of recovery.

The autonomous agent must produce and continuously run:
1. **Targeted unit tests** for every changed contract.
2. **Integration tests** spanning note lifecycle, sync, restoration, graph, AI, and export.
3. **UI tests** for critical user journeys across supported form factors.
4. **Performance tests** with explicit thresholds (typing latency, switching latency, graph update, long-session recording).
5. **Smoke flow tests** as fast PR gates.
6. **Synthetic fixtures** (large vaults, conflict vaults, rename-heavy graph fixtures, long audio sessions).
7. **Stubs/mocks** for AI providers, microphone/speech services, and external file/sync events.
8. **Regression ledger**: each bug fix includes a reproducer test + permanent guard + perf assertion when relevant.

No phase can close without green automated evidence.

---

## 9) Definition of Done (Strict)

Quartz is done only if **all** are true:
1. **Architecture truth:** clear single ownership for route, editor state, vault access, identity, conflict semantics, AI policy.
2. **Flow reliability:** all “Fully Working App Mandate” flows pass automated tests consistently.
3. **Data safety:** coordinated I/O + conflict handling prove no silent loss through deterministic tests.
4. **Performance:** enforced budgets pass in CI for typing, note switching, graph updates, and long audio sessions.
5. **Accessibility:** core screens/interactions satisfy automated accessibility checks and stay green.
6. **Regression governance:** CI gates block merges on functional and performance regressions.
7. **No cosmetic victory:** “cleaner structure” without proven reliability/performance does not count.

If any condition is false, Quartz recovery is incomplete.
