# 1. Forensic Competitor Teardown & Market Strategy

## 1.1 Strategic Positioning: “Native Apple Notes Fluidity + Obsidian-Grade Local Graph + OpenOats-Grade Ambient Intelligence”
Quartz should not compete as “another markdown app.” It must win as the **only truly-native Apple ecosystem knowledge operating system**:
- **Bear 2 UX smoothness** in text layout and syntax invisibility.
- **Ulysses information architecture** for long-form workflow and export reliability.
- **Obsidian file sovereignty** with a low-latency graph/index layer.
- **iA Writer focus purity** for distraction-free drafting.
- **OpenOats ambient intelligence** for local-first voice capture + retrieval + promptable synthesis.

## 1.2 Bear 2 Reverse-Engineering (How Quartz Surpasses It)
### Inferred architecture pattern (from observed UX + Apple text stack constraints)
- Bear-class editor smoothness implies **TextKit 2 with paragraph-fragment invalidation**, not full-document restyle passes.
- Syntax hiding behavior implies a **dual representation model**:
  1. canonical markdown source buffer,
  2. attributed render overlay with selective glyph de-emphasis/opacity reductions.
- 120fps-feeling scroll implies no synchronous AST parse on keystroke; likely **debounced AST + incremental spans + cached text fragments**.
- Math and inline media quality implies inline attachment runs mapped to paragraph layout fragments, not ad hoc NSTextAttachment hacks.

### Quartz beat-plan
- Enforce **incremental AST patching** keyed by edited paragraph ranges.
- Add **syntax-visibility modes**: Full / Gentle fade / Hidden-until-caret.
- Implement **equation and table semantic tokens** in highlighter pipeline, with editor-safe atomic undo groups.
- Gate with performance budgets:
  - keystroke-to-frame P95 < 8ms (macOS),
  - syntax pass P95 < 12ms for 20k-char notes,
  - no full-document attribute resets during normal typing.

## 1.3 Ulysses Reverse-Engineering (How Quartz Surpasses It)
### Inferred architecture pattern
- Ulysses’ 3-pane stability indicates a **single route state machine** with explicit pane authority, not distributed booleans.
- Export reliability suggests **dedicated export service layer** with format-specific renderers and deterministic templates.
- Mac/iPad scaling quality implies breakpoint-aware pane collapsing with persisted UI intent.

### Quartz beat-plan
- Promote one authoritative route model:
  - `sidebarSelection`
  - `listSelection`
  - `detailRoute`
  - `auxPanelState`
- Build export pipeline contracts:
  - Markdown → AST → format adapters (PDF/HTML/RTF).
  - test snapshots for typography across macOS/iPadOS/iOS.
- Add commandable export presets (“Meeting Minutes PDF”, “Research HTML bundle”).

## 1.4 Obsidian Reverse-Engineering (How Quartz Surpasses It)
### Inferred architecture pattern
- Obsidian advantage: filesystem truth + flexible plugin indexing.
- Weakness to exploit: non-native feel and uneven Apple platform coherence.

### Quartz beat-plan (Hybrid persistence done right)
- **Raw files remain source of truth** in user-visible vault folder.
- **SwiftData graph/index store as acceleration cache**, fully rebuildable.
- Identity strategy:
  - primary key = file bookmark + canonical relative path + content hash lineage,
  - backlinks resolved by stable note IDs, not titles.
- Zero-lock-in guarantee: deleting cache never harms `.md` files.

## 1.5 iA Writer Reverse-Engineering (How Quartz Surpasses It)
### Inferred architecture pattern
- Focus mode quality comes from ruthless chrome suppression + typography discipline + minimal animation.

### Quartz beat-plan
- Introduce `FocusSurfaceModifier` stack:
  - hide nonessential panes,
  - center text column with adaptive measure,
  - suppress non-critical badges,
  - enforce reduced motion behavior parity.
- Add “Focus Ritual” quick transitions via matched geometry and spring presets.

## 1.6 Granola + OpenOats Teardown (How Quartz Surpasses It)
### OpenOats-significant patterns (from public repo metadata/README behavior)
- Local-first call transcription and suggestion loops emphasize:
  - stream ingestion,
  - periodic retrieval over local corpus,
  - templated synthesis from rolling context windows.
- Practical product lessons:
  - session-level autosave,
  - transcript artifacts persisted plainly,
  - privacy defaults and explicit legal/compliance prompts.

### Quartz beat-plan
- Build **native Swift 6 audio intelligence core** shared across platforms:
  - AVAudioEngine capture graph,
  - bounded ring-buffer chunking,
  - on-device ASR and summarization templates,
  - diarization target under 150MB RAM ceiling.
- Floating compact UI (“Live Capsule”) with recorder state, latency meter, and insertion destination.
- Provide note-safe transcript insertion templates:
  - decision log,
  - action items,
  - Q&A digest,
  - follow-up email draft.

---

# 2. Current Codebase Diagnostics (The Brutal Teardown)

## 2.1 What Quartz Already Does Well (Do Not Regress)
- Strong modular package split (`QuartzKit`) with meaningful domain/presentation boundaries.
- TextKit 2 foundation is present and functional.
- High test volume exists across editor, sync, graph, performance, accessibility, and store surfaces.
- Hybrid file vault concept is already integrated with sync and versioning primitives.

## 2.2 Architectural Rot Map (Immediate Priority)

### A. TextKit 2 editor rot
**Observed risk shape**
- Full-buffer replacement paths still exist in certain programmatic updates.
- Highlighting phases still over-touch full ranges under some conditions.
- Undo coalescing and IME safety are vulnerable during async highlight/edit overlap.

**Mandated fix**
- Replace all full-document mutation call sites with range-diff patching.
- Introduce `EditorMutationTransaction`:
  - `source` (`userTyping`, `listContinuation`, `aiInsert`, `syncMerge`, `ocrInsert`)
  - `editedRanges`
  - `undoGroupingPolicy`
  - `selectionPolicy`
- AST feature completeness:
  - interactive markdown tables with Tab/Shift-Tab navigation,
  - nested task list toggles,
  - LaTeX spans with inline/block token distinction,
  - deterministic undo bundles per semantic action.

### B. State and persistence rot (“Vault amnesia”)
**Observed risk shape**
- Restoration timing uses heuristic delays in parts of flow.
- Cross-scene restoration can desync pane state and selected note.

**Mandated fix**
- Centralize security-scoped URL acquisition and stale bookmark repair.
- Use `@SceneStorage` for route + viewport restoration tokens.
- Add granular `@Observable` stores to avoid broad invalidation cascades.
- Add startup handshake states:
  - `vaultResolved`
  - `indexWarm`
  - `editorMounted`
  - `restorationApplied`

### C. Hybrid file system + sync conflict rot
**Observed risk shape**
- Conflict resolution pathways are partially fragmented.
- Identity fallback paths can still permit ambiguous resolution.

**Mandated fix**
- CRDT/timestamp hybrid policy:
  - vector clock per note lineage,
  - last-writer metadata only as tiebreaker, never sole authority,
  - semantic merge for markdown blocks when line-level merge conflicts.
- Add Time Machine history:
  - append-only local revisions,
  - diff viewer with “restore as new note” and “overwrite current”.
- Absolute guarantee: no-byte-loss invariant in merge tests.

### D. Liquid Glass and accessibility rot
**Observed risk shape**
- Liquid materials exist but need tighter platform consistency and animation governance.

**Mandated fix**
- Standardize materials via one design token surface:
  - `.ultraThinMaterial` primary glass,
  - fallback solid backgrounds for reduce transparency.
- Morph transitions with `.matchedGeometryEffect` and spring curves tuned per platform.
- Accessibility hard requirements:
  - VoiceOver navigability for every actionable control,
  - Dynamic Type through AX5,
  - contrast-compliant fallback palettes,
  - keyboard-first parity on macOS/iPad.

## 2.3 Non-Negotiable Recovery KPIs
- Typing frame budget: **<16ms main thread**, P95.
- Audio intelligence memory budget: **<=150MB** steady-state.
- Sync guarantee: **0 bytes lost** under offline concurrent edits.
- Editor correctness: no cursor jumps, no IME corruption, deterministic undo/redo.

---

# 3. Cross-Platform Target Architecture & Hardware (Mac/iPad/iOS)

## 3.1 Unified Core
Single shared core in QuartzKit:
- Markdown engine (AST parse + incremental patches).
- Graph/index services (SwiftData + file watcher).
- Sync conflict engine (CRDT + revision history).
- Audio intelligence (capture, ASR, summarization templates, diarization).
- Capability-gated adapters compiled with `#if os()`.

## 3.2 Platform Branching Contract

### macOS Desktop (`#if os(macOS)`)
- AppKit-bridged menu commands and keyboard routing.
- True multi-window note sessions.
- Command Palette (`Cmd+K`) with global actions and scoped note actions.
- Graceful degradation for absent camera devices.

### iPadOS Tablet (`#if os(iOS)` + idiom `.pad`)
- Multi-column `NavigationSplitView` with persistent widths.
- Inline PencilKit canvases embeddable in notes.
- Real-time handwriting recognition pipeline:
  - stroke capture → OCR extraction → markdown insertion anchors.
- Scribble-friendly tool affordances and Apple Pencil hover cues where available.

### iOS Mobile (`#if os(iOS)` + idiom `.phone`)
- Swipe-first interactions for note operations.
- Bottom-sheet navigation for inspector/graph actions.
- Haptic confirmation for key editor/sync states.

### VisionKit scanning (iPhone+iPad)
- Native `VNDocumentCameraViewController` integration in editor toolchain.
- On-device OCR extraction mapped into generated markdown:
  - headings,
  - bullet heuristics,
  - table inference where confidence threshold passes.

## 3.3 Hardware Capability Matrix
- Camera unavailable → disable scan actions + surface graceful explanation.
- Pencil unavailable → hide drawing insertion affordances, keep OCR import path.
- Low-memory devices → reduce diarization parallelism and waveform fidelity.

## 3.4 Data Topology
- Filesystem vault: user-owned `.md` corpus.
- SwiftData index: graph links, embeddings metadata, search shards, revision pointers.
- Rebuild command: full index reconstruction from filesystem without data loss.

---

# 4. Onboarding, FTUE & DocC Strategy

## 4.1 Mandatory Interactive FTUE (“Welcome to Quartz”)
On first launch, auto-open a seeded markdown note that forces user to execute:
1. create internal link,
2. run focus mode,
3. trigger glass UI morph transition,
4. record 10-second audio note,
5. scan a document snippet,
6. open graph and follow backlink.

Completion unlocks “Power User Ready” state and creates a personalized cheatsheet note.

## 4.2 In-Product Learning Design
- Inline coach marks only for first three uses of complex features.
- Feature discovery from Command Palette (`Learn: <Feature>` actions).
- Recoverable onboarding: re-run tutorial from Settings.

## 4.3 DocC Mandate
Generate Apple-standard DocC for:
- audio buffering and diarization pipeline,
- graph identity resolution and merge logic,
- editor mutation transactions,
- OCR and scan insertion flow.

DocC must include:
- architecture article,
- tutorials with code snippets,
- troubleshooting pages tied to self-healing matrix IDs.

---

# 5. Phase-by-Phase Multi-Platform TDD Execution Plan

## 5.0 Global Rules (Apply to every phase)
- **100% TEST COVERAGE RULE**: every function, state mutation, and UI transition gets unit/integration/UI test coverage.
- No feature merge without failing tests first, then implementation, then passing green matrix.
- Every PR includes performance and snapshot checks for touched views.

## Phase 1 — Editor Core Hardening (TextKit 2 + Markdown Semantics)
**Goals**
- Remove full-text replacement pathways.
- Ship incremental AST patching and robust undo coalescing.

**Tests first**
- Unit: range diff calculator, transaction policies, IME protection guards.
- Integration: list continuation, table tabbing, latex insertion, external merge while typing.
- UI: cursor stability snapshots across iPhone/iPad/Mac.

**Done when**
- No full-document mutation during standard editing.
- All editor mutation origins covered by transaction logs and tests.

## Phase 2 — Persistence + Sync Reliability
**Goals**
- Deterministic security-scoped vault restoration.
- CRDT merge with zero-byte-loss under concurrent offline edits.

**Tests first**
- Unit: vector clock compare, tie-break logic, merge semantics.
- Integration: simulated iCloud outage/rejoin, stale bookmark repair, conflict UI flows.
- Property tests: randomized concurrent edit streams.

**Done when**
- 10,000 randomized merge scenarios pass with zero data loss.

## Phase 3 — Cross-Platform UX Parity + Liquid Glass ADA Pass
**Goals**
- Platform-adaptive UI that feels native on each device class.
- Consistent accessibility and motion/transparency behavior.

**Tests first**
- UI snapshots per platform and dynamic type tiers.
- Accessibility tests: VoiceOver labels, rotor order, keyboard traversal.
- Motion tests: reduced-motion paths produce expected transitions.

**Done when**
- Snapshot diff suite green across macOS/iPhone/iPad footprints.

## Phase 4 — Audio Intelligence + Scan-to-Markdown
**Goals**
- OpenOats-inspired local-first transcript + templated insertion pipeline.
- Native VisionKit scanning + OCR-to-markdown.

**Tests first**
- Mocked AVAudioEngine input buffers + diarization throughput checks.
- VisionKit mock camera frames and OCR post-processing tests.
- Integration: transcript to note insertion while editor remains interactive.

**Done when**
- 60+ min session meets memory ceiling and main-thread budget.

## Phase 5 — Knowledge Graph Supremacy + FTUE
**Goals**
- Lightning-fast graph queries with filesystem-grounded truth.
- Interactive onboarding that trains feature mastery.

**Tests first**
- Graph identity persistence and backlink correctness across rename/move/delete.
- FTUE path completion tests for all required tutorial actions.

**Done when**
- Graph and onboarding flows pass full integration matrix on all supported platforms.

## Required headless CI commands (per phase)
- `xcodebuild test -scheme Quartz -destination 'platform=macOS'`
- `xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- `xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'`
- plus package tests and snapshot suites.

---

# 6. The Autonomous Self-Healing & Error Resolution Matrix (Strict CLI Instructions)

## 6.1 Execution Doctrine
Claude Code must run in an autonomous loop:
1. Reproduce failure.
2. Localize fault to smallest module.
3. Patch minimally with explicit rationale.
4. Re-run targeted tests.
5. Re-run full matrix.
6. If still failing, escalate to next matrix strategy.

No manual human intervention allowed except secrets/signing constraints.

## 6.2 Self-Healing Matrix

| Failure Class | Trigger Signal | Mandatory Autonomous Action | Stop Condition |
|---|---|---|---|
| Build-time concurrency | Swift 6 strict concurrency warnings/errors | Trace actor isolation boundaries; add `@MainActor`, actor wrappers, or `Sendable` conformances; remove unsafe shared mutable state | Zero concurrency diagnostics |
| Runtime frame budget | XCTest measure >16ms main-thread in editor/audio flows | Refactor hot path: move work off main actor, batch UI updates, reduce redraw scopes | P95 <16ms |
| Memory budget breach | Audio transcription >150MB | Reduce buffer retention, chunk size, and model residency; defer cold assets; tighten ring buffer backpressure | <=150MB steady-state |
| Snapshot mismatch | pixel-diff fail in snapshot suite | Parse diff; tune `.padding`, `.frame`, `.layoutPriority`, material layering; regenerate deterministic fixtures only when intentional | Snapshots green across all form factors |
| State desync | 3-pane integration mismatch | Trace `@Observable` propagation graph; restore single source of truth; remove mirrored state | Sidebar/list/editor stay coherent in tests |
| Sync data loss | CRDT merge simulation loses bytes | Rewrite vector clock compare and merge strategy; add adversarial regression fixture | Zero-byte-loss invariant passes |
| OCR regression | scan import formatting invalid | Adjust OCR normalization heuristics and markdown block reconstruction | Golden OCR fixtures pass |
| Accessibility regressions | AX audit/snapshot failures | Patch labels, traits, focus order, dynamic type constraints | AX suite fully green |

## 6.3 CLI Autopilot Script Contract
Each failure category must map to executable scripts:
- `scripts/heal_concurrency.sh`
- `scripts/heal_performance.sh`
- `scripts/heal_snapshots.sh`
- `scripts/heal_state.sh`
- `scripts/heal_sync.sh`

Scripts must:
- run diagnosis command,
- apply deterministic fix templates,
- rerun relevant tests,
- emit machine-readable report (`.json`) for CI annotations.

## 6.4 Zero-Exception Quality Gate
A change cannot merge unless all gates pass:
- unit + integration + UI + snapshot + accessibility + performance.
- cross-platform test destinations all green.
- coverage report proves 100% rule for changed modules.

---

# 7. The Future Ecosystem Roadmap (visionOS, watchOS, & Monetization)

## 7.1 6–12 Month Apple Ecosystem Expansion

### visionOS
- Spatial knowledge workspace with infinite linked canvases.
- Gaze+gesture note graph traversal.
- “Context Bubbles” that pin live transcript, source notes, and decisions in 3D space.

### watchOS
- One-tap voice memo capture complication.
- Background sync to iPhone/macOS meeting pipeline.
- Quick action intents: “Capture thought”, “Append to Daily Note”, “Mark action item”.

### tvOS
- Read-only dashboard mode for presentations:
  - project graph,
  - session recaps,
  - timeline of decisions and action items.

## 7.2 Monetization Without Lock-In
- Core app remains fully useful local-first.
- Optional Pro tier:
  - advanced automation templates,
  - team knowledge overlays,
  - premium visual themes and export packs.
- Never monetize user data. No forced cloud dependency.

## 7.3 Strategic Moat
By combining:
- native Apple interaction fidelity,
- sovereign markdown filesystem ownership,
- high-performance graph intelligence,
- private on-device audio/scan ingestion,
Quartz can own the “personal knowledge cockpit” category on Apple platforms.

The final bar is Apple Design Award quality: fluid, humane, accessible, technically uncompromising.
