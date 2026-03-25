# Quartz Master Refactoring Plan (ADA Trajectory)

_Date: 2026-03-25_

## Executive Intent

Quartz already has high-value primitives (TextKit 2 editor bridge, SidebarViewModel, Spotlight indexing, iCloud monitoring), but the shell is still conceptually a **two-column app** with substantial presentation state in `ContentView` and mixed concerns between app shell, navigation, and editor orchestration. This plan defines how to migrate to a true **ADA-grade three-pane architecture**:

1. **Navigation / Source Sidebar** (vaults, smart lists, hierarchy)
2. **Content List Sidebar** (fast previews, sort/filter, recents)
3. **Editor Canvas** (TextKit 2, zero-jitter editing)
4. **Inspector Sidebar** (ToC, metadata, tags, publish/export)

---

## 1) Diagnosis of Current Structural Gaps

### What is strong today
- Native `NavigationSplitView` baseline exists in `AdaptiveLayoutView`.
- Sidebar already uses `List(selection:)` + `OutlineGroup` and supports drag/drop.
- Editor host already uses a custom TextKit 2 stack (`MarkdownTextContentManager` + layout manager) with async highlighting.
- A right-side inspector exists on macOS.

### Core limitations preventing “top-tier native” feel
1. **App shell remains two-pane, not three-pane.**
   - `AdaptiveLayoutView` currently models sidebar + detail only, so note discovery and note editing are overloaded into one selection flow.
2. **`ContentView` owns too much orchestration state.**
   - Vault routing, modal presentation, selection restoration, command handling, spotlight sync callbacks, and sheet toggles are coupled in one view.
3. **No dedicated content list domain model.**
   - There is no persistent, cache-aware `NoteListItem`/preview pipeline; file tree is reused as both navigation model and list data source.
4. **Inspector parity gap.**
   - Inspector is macOS-only and its outline is static text, not scroll-position synchronized with the editor viewport.
5. **Text editing pipeline still does full-text assignment on SwiftUI sync boundaries.**
   - Works, but can regress into cursor jitter/selection fight under heavy typing or external updates.
6. **Markdown parsing/rendering stack is not trustworthy enough yet for an elite editor.**
   - Highlighting/rendering are too tightly coupled to edit cycles; parser behavior must be re-validated with a deterministic test corpus and split into explicit edit/analysis/render stages.
7. **Toolbar visual/interaction quality is below premium-native bar.**
   - Action density, icon rhythm, grouping, and affordance hierarchy need a full redesign system pass, not incremental patching.

---

## 2) Target ADA Architecture

## 2.1 Layout: canonical 3+1 pane shell

### Proposed shell composition
- **Primary column (left):** `VaultNavigationSidebar`
- **Supplementary column (middle):** `NoteListSidebar`
- **Detail column (center):** `EditorContainerView`
- **Inspector (right):** `InspectorSidebar` (toggleable)

### Implementation strategy
- Keep `NavigationSplitView` as first-class container.
- Move from 2-column abstraction (`AdaptiveLayoutView`) to explicit 3-column split wrapper:
  - `.sidebar`: source list
  - `.content`: note previews
  - `.detail`: editor
- Inspector is not a split column; keep it as platform-native inspector:
  - macOS: `.inspector(isPresented:)`
  - iPadOS: adaptive trailing panel sheet/column using size class + detents where needed

### Why this matters
- Matches cognitive model of Bear/Ulysses/Xcode/Pages: **choose source → choose note → edit note**.
- Allows independent performance tuning of middle list (preview rendering and incremental loading) without touching editor state.

---

## 2.2 Left Sidebar (Navigation / Source List)

### Feature set
- Vault switcher at top (current vault + quick switch menu)
- Smart sections:
  - All Notes
  - Favorites
  - Recent
  - Tags
  - Attachments / Tasks (future)
- Collapsible folder tree
- Drag/drop (move note/folder) with clear drop affordances

### APIs / patterns
- `List(selection:)` + `OutlineGroup`
- `dropDestination`, `draggable`, `Transferable`
- `DisclosureGroup` state persistence per folder UUID
- `@Observable` source state in dedicated store: `VaultNavigatorStore`

### Performance strategy
- Keep tree model minimal (metadata-only).
- Defer expensive derived data (tag counts, task counts) to background actors and publish snapshots.

### Anti-patterns to avoid
- Recomputing full tree/tag aggregations on every keystroke.
- Embedding costly filesystem traversals in row views.
- Using transient URL strings as the only identity for large-scale state restoration.

---

## 2.3 Middle Sidebar (Note List + 2–3 line previews)

### New domain model (required)
Create a dedicated projection model:
- `NoteListItem`:
  - `id` (stable UUID from path hash + inode fallback)
  - `url`
  - `title`
  - `modifiedAt`
  - `snippet` (2–3 lines)
  - `tags` (optional compact set)
  - `isFavorite`

### Preview extraction pipeline
1. `NotePreviewIndexer` actor monitors candidate files.
2. For each file, read **bounded prefix** only (e.g. first 8–16 KB), not full file.
3. Strip frontmatter and markdown syntax markers cheaply (regex/token pass).
4. Produce first non-empty title + normalized snippet lines.
5. Store in SQLite/SwiftData cache keyed by file ID + modification date.

### Efficiency details
- Use `TaskGroup` for batch preview parsing with bounded concurrency.
- Skip unchanged files via mtime/size fingerprint.
- Use cooperative cancellation while typing filters.
- Warm cache on vault open, then incremental updates from `FileWatcher`.

### UX behaviors
- Native selection highlight and keyboard navigation.
- Swipe actions (favorite, pin, delete) on iOS/iPadOS.
- Context menus on macOS.
- Section headers for time buckets (Today, Yesterday, This Week, Older) when sorted by recency.

### Anti-patterns to avoid
- Loading whole markdown body for each row render.
- Parsing markdown synchronously on main thread.
- Coupling preview extraction with editor `NoteDocument` loading pipeline.

---

## 2.4 Editor (Main Content) — TextKit 2 excellence

### Non-negotiable product decision (per current quality gap)
- Treat the current markdown editing/rendering implementation as **replaceable**.
- Keep TextKit 2 as the rendering/editing substrate, but rebuild the markdown pipeline around deterministic parsing + incremental updates.
- The goal is not “fix a few glitches”; the goal is **Ulysses/Bear-grade smoothness** under stress (long files, rapid typing, IME, paste bursts, external file edits).

### Editor architecture target
- Keep platform text views (`UITextView`/`NSTextView`) in representables for performance.
- Introduce `EditorSession` actor/object per open note:
  - authoritative text buffer
  - incremental diff application
  - selection/caret state
  - undo checkpoint policy
  - autosave debounce policy

### TextKit 2 strategy
- Continue custom content manager; add explicit external update path:
  - if change originates from user typing, never assign full text back from SwiftUI state.
  - apply deltas only for external mutations (file watcher merge, AI transform, template insert).
- Keep syntax highlight parse async; throttle by edit cadence and viewport proximity.

### Parsing/rendering reboot (critical)
1. **Source of truth parser:** choose one markdown grammar path and lock it (e.g., cmark-gfm-compatible semantics for block structure + app-level inline extensions).
2. **Three-lane pipeline:**  
   - Lane A: editing buffer (fast, synchronous, minimal work)  
   - Lane B: incremental structural parse (background, cancellable)  
   - Lane C: render decorations (highlights, list/task visuals, heading map)
3. **Incremental invalidation:** only re-parse and re-style dirty ranges + affected block boundaries.
4. **Deterministic fixture suite:** build a markdown corpus with pathological cases (nested lists, mixed fences, tables, task lists, blockquotes, escaped markers, links, footnotes if supported).
5. **Golden output checks:** parser AST and rendered spans must be snapshot-tested so regressions are caught before shipping.
6. **Latency budgets:** enforce per-keystroke frame budget and parse deadline budgets in CI perf checks.

### Selection/IME correctness contract (must-have)
- Define immutable editor invariants:
  - selection anchor/focus must survive incremental styling passes
  - undo/redo must preserve selection intent, not just text
  - external file merges must map cursor/selection predictably
- Add an explicit input-method validation matrix:
  - CJK IME composition (marked text lifecycle)
  - RTL scripts and bidirectional selection movement
  - emoji/ZWJ grapheme clusters
  - dead keys, dictation insertions, handwriting/pencil text insertion
- Block release if any matrix case causes cursor jumps, text duplication, composition breakage, or visual flicker.

### Typographic system
- Define `EditorTypographyProfile`:
  - base text style
  - line height multiple (platform tuned)
  - paragraph spacing
  - code font mapping
  - dynamic type clamping per platform
- Provide live scaling with smooth interpolation and no relayout spikes.

### Anti-patterns to avoid
- Treating SwiftUI `@State String` as the sole source of truth for high-frequency text editing.
- Full attributed-string reapply on each keystroke.
- Mixing preview-render markdown pipeline and editing pipeline.
- Using regex-only parsing as the long-term markdown architecture.
- Shipping editor changes without measurable typing/scrolling performance telemetry.
- Treating composed text ranges as plain scalar offsets without grapheme-safe mapping.

---

## 2.5 Right Sidebar (Inspector)

### Components
1. **Table of Contents**
   - heading list from parsed markdown AST
   - actively synced with scroll position via visible range mapping
2. **Document Stats**
   - word count, character count, reading time
   - created / modified / location
3. **Tag Manager**
   - editable chips with suggestions and conflict-safe frontmatter updates

### Sync model
- Build `InspectorViewModel` backed by `EditorSession` snapshots.
- ToC updates from incremental parser deltas, not full reparses.
- Scroll sync from text layout manager visible fragment callback.

### Anti-patterns to avoid
- Computing word count on main thread for entire file on every keypress.
- ToC generation only on view appearance.
- Inspector updates directly mutating editor state without transactional layer.

---

## 3) ADA-Level Polish Standards

## 3.1 Micro-interactions

### Required motion language
- Sidebar collapse/expand: spring with subtle opacity cross-fade.
- Focus mode entry: dim non-editor chrome + smooth content expansion.
- Task checkbox toggles: immediate glyph animation + semantic haptic.

### Implementation notes
- Centralize animation tokens in design system (duration, spring, curve).
- Respect `accessibilityReduceMotion` by switching to fade/scale minimal transitions.
- Prefer intent-based APIs (`animateFocusEntry()`, `animateInspectorToggle()`) over ad hoc `withAnimation` scatter.

## 3.2 Typography quality

- Use Dynamic Type-aware font ramps and platform-specific defaults.
- Manage line heights via paragraph style, not just padding hacks.
- Add opt-in serif/sans/mono editorial profiles with persisted preference.
- Keep title/body/code hierarchy semantically consistent across editor and preview list.

## 3.3 Materials and “Liquid Glass” without perf regressions

- Use materials on structural surfaces only (sidebars/toolbars), not deep nested row backgrounds.
- Keep gradients/mesh backgrounds static or slowly animated; avoid per-row dynamic blur.
- Instrument GPU overdraw and offscreen rendering during scroll and typing.
- Provide low-power fallback theme variant.

## 3.4 Toolbar and iconography redesign (explicit focus area)

### Visual language requirements
- Define a single toolbar grammar: primary actions, secondary actions, overflow actions.
- Normalize icon weight/scale (SF Symbols variants) and optical alignment across macOS/iPadOS/iOS.
- Apply consistent hit targets, spacing cadence, and hover/pressed/selected states.
- Use role color sparingly: neutral by default, accent only for mode/state emphasis.

### Interaction requirements
- Remove “button wall” feeling via grouping and progressive disclosure.
- Ensure toolbar behavior is context-aware (editing, selection-active, focus mode, preview mode).
- Keep destructive/rare actions in menus, not top-level icon rows.
- Align keyboard shortcuts with visible affordances and menu command hierarchy.

### Anti-patterns to avoid
- Inconsistent symbol rendering modes across adjacent controls.
- Mixing bordered, borderless, capsule, and plain buttons without a system.
- Overloading top toolbar with every feature instead of contextual surfaces.

## 3.5 Command parity and discoverability

- Every high-value action must have parity across:
  - visible UI affordance (toolbar/menu/context)
  - keyboard shortcut (where platform-appropriate)
  - command palette discoverability
- Build a command registry matrix and test it in CI (snapshot/contract tests) to prevent drift.
- Enforce naming consistency between menu title, tooltip/help text, and command palette labels.

---

## 4) Recommended Data Flow Architecture

## Decision: Hybrid native SwiftUI flow + reducer-style feature modules

### Why
- Full TCA migration is high-cost given current codebase surface.
- Plain `@Observable` everywhere can drift into shared mutable state and broad redraws.

### Recommendation
- Keep `@Observable` for leaf view models.
- Introduce reducer-like stores for shell-critical domains:
  - `WorkspaceStore` (pane selection, column visibility, active vault)
  - `NavigatorStore` (left sidebar)
  - `NoteListStore` (middle previews + filters + sorting)
  - `EditorStore` (session lifecycle)
  - `InspectorStore` (metadata/ToC/tags)
- Communicate across stores with explicit actions + async effects, not direct property mutation.

### Rendering control
- Prefer immutable snapshots for large lists.
- Use fine-grained bindings only for editable local controls.
- Ensure note selection changes do not rebuild entire sidebar trees.

---

## 5) Step-by-Step Refactoring Roadmap (Prioritized)

## Phase A — Foundation (1–2 sprints)

### Step A1: Introduce new workspace shell
- **Goal:** Replace 2-pane shell with 3-pane `WorkspaceView`.
- **APIs:** `NavigationSplitView` (3-column), `NavigationSplitViewVisibility`.
- **Avoid:** Embedding modal sheet logic inside shell layout struct.
- **Architecture:** New `WorkspaceStore` owns selection (`sourceID`, `noteID`) and column visibility.

### Step A2: Extract orchestration out of `ContentView`
- **Goal:** Move command routing, vault lifecycle, and deep links into coordinator.
- **APIs:** `@MainActor` coordinator, `SceneStorage`, `onOpenURL`.
- **Avoid:** Monolithic `View` with dozens of boolean sheet flags.
- **Architecture:** `AppCoordinator` + feature stores.

## Phase B — Middle sidebar and preview engine (2–3 sprints)

### Step B1: Build preview cache/indexer
- **Goal:** Introduce fast note preview pipeline for large vaults.
- **APIs:** `actor`, `TaskGroup`, file resource values, SQLite/SwiftData.
- **Avoid:** Parsing full file contents on main thread.
- **Architecture:** `NotePreviewIndexer` + `NotePreviewRepository`.

### Step B2: Implement `NoteListSidebar`
- **Goal:** Add performant note list with title/date/snippet rows.
- **APIs:** `List`, `Section`, `.searchable`, `.swipeActions`, `.contextMenu`.
- **Avoid:** Deriving row view state by traversing entire tree each render.
- **Architecture:** `NoteListStore` fed by cached projections.

## Phase C — Editor hardening (2–4 sprints)

### Step C1: Introduce `EditorSession`
- **Goal:** Stabilize typing/selection/autosave under heavy edits.
- **APIs:** TextKit 2 managers, `UndoManager`, background parse tasks.
- **Avoid:** Bidirectional full-string mirroring between SwiftUI and text view.
- **Architecture:** session-owned buffer + diff-based external mutations.

### Step C2: Incremental parser services
- **Goal:** Feed syntax highlight + ToC + stats from shared parse graph.
- **APIs:** background actor pipelines, debounced parsing, cancellation.
- **Avoid:** duplicate parsing per feature panel.
- **Architecture:** `MarkdownAnalysisService` publishes deltas.

### Step C3: Editor quality strike team (flicker/render correctness)
- **Goal:** Eliminate flicker, cursor jumps, and markdown mis-rendering before adding new editor features.
- **APIs:** Instruments + signposts, text layout profiling, snapshot tests.
- **Avoid:** “feature-forward” development while core editing remains unstable.
- **Architecture:** temporary hardening track with explicit exit criteria (typing stability, rendering correctness, selection reliability).

### Step C4: Durability and recovery hardening
- **Goal:** Guarantee user trust with crash-safe autosave and deterministic recovery.
- **APIs:** atomic writes, edit journal/checkpoint files, background recovery tasks.
- **Avoid:** assuming in-memory state will always flush cleanly on app lifecycle transitions.
- **Architecture:** `EditorRecoveryService` with replayable checkpoints and conflict-aware restore.

## Phase D — Inspector parity + scroll sync (1–2 sprints)

### Step D1: Cross-platform inspector
- **Goal:** Bring right sidebar parity to iPadOS and refine macOS inspector.
- **APIs:** `.inspector`, `.presentationDetents`, adaptive size-class layouts.
- **Avoid:** platform forks with divergent feature sets.
- **Architecture:** shared `InspectorSidebar` + platform container wrappers.

### Step D2: Interactive ToC with scroll tracking
- **Goal:** Highlight active heading and jump-to-section reliably.
- **APIs:** TextKit layout fragment/selection APIs, scroll-to-range bridge.
- **Avoid:** geometry hacks based solely on SwiftUI scroll proxies.
- **Architecture:** `InspectorStore` subscribes to `EditorSession` viewport updates.

## Phase E — ADA polish and system depth (ongoing)

### Step E1: Motion + haptics pass
- **Goal:** Add semantic micro-interactions and reduced-motion variants.
- **APIs:** `sensoryFeedback`, animation tokens, `PhaseAnimator` where appropriate.
- **Avoid:** global heavy animation on list updates.

### Step E2: Typography + themes pass
- **Goal:** Add professional typography presets and performant materials.
- **APIs:** Dynamic Type, paragraph style control, material backgrounds.
- **Avoid:** per-cell blur/material stacking.

### Step E2.1: Toolbar harmonization pass
- **Goal:** Deliver a polished, harmonized toolbar/button/icon system that feels Apple-first and premium.
- **APIs:** `ToolbarItemGroup`, `controlSize`, `labelStyle`, SF Symbols hierarchical/palette rendering, platform-specific toolbar placements.
- **Avoid:** ad hoc styling per view.
- **Architecture:** shared toolbar style tokens + component wrappers (`QuartzToolbarButton`, `QuartzToolbarGroup`).

### Step E3: Performance and accessibility gates
- **Goal:** Ship only after measurable editor/list smoothness and a11y quality.
- **APIs:** Instruments (Time Profiler, Core Animation, Memory), VoiceOver audits.
- **Avoid:** qualitative-only “feels fast” validation.

### Step E4: Progressive rollout and kill-switch strategy
- **Goal:** De-risk parser/editor rewrite in production.
- **APIs:** feature flags, staged rollout cohorts, remote kill switch, telemetry dashboards.
- **Avoid:** all-users cutover with no rollback path.
- **Architecture:** dual-path editor runtime (`LegacyEditor` vs `NextEditor`) until quality gates are consistently met.

## Phase F — The Super-App Layer (Knowledge, AI, Audio, Security) (ongoing after core stability)

### Product principle: “Power without clutter”
- Keep the **default writing surface calm** (source list + note list + editor + inspector).
- Advanced modalities are contextual overlays, side panels, or dedicated routes — never always-on chrome.
- Every advanced tool must answer: “Why now, in this writing moment?”

### F1: KnowledgeGraphView integration
- **Goal:** Integrate graph exploration as a first-class capability without polluting primary editor workflows.
- **UX pattern:** launch from contextual affordances:
  - selected wiki-link / backlink chip,
  - command palette (`Open Knowledge Graph`),
  - optional utility tab in inspector on large screens.
- **Architecture:** `KnowledgeGraphStore` consumes `NoteGraphProjection` snapshots produced off the editor/main-thread.
- **Avoid:** embedding always-live graph canvases directly in the editor column.

### F2: VaultChatView (AI) integration
- **Goal:** Make AI assistance context-aware and non-intrusive.
- **UX pattern:**
  - chat presented as detachable panel/sheet,
  - optional split mode on macOS/iPad landscape,
  - default to “Ask about this note” scope, with explicit “entire vault” escalation.
- **Architecture:** `VaultChatStore` + `ChatContextAssembler` that fuses:
  - current note selection,
  - editor selection range,
  - preview/search index signals,
  - embedding retrieval results.
- **Avoid:** auto-injecting AI controls in every toolbar region.

### F3: SpeakerDiarizationService + audio workflow integration
- **Goal:** unify recording, diarization, transcript insertion, and summary actions into one coherent capture flow.
- **UX pattern:**
  - lightweight “Capture” entry point in toolbar overflow or command palette,
  - dedicated capture panel with modes (voice note, meeting minutes, diarization),
  - post-processing results appear as structured insert cards in editor.
- **Architecture:** `AudioCaptureStore` orchestrates:
  - `AudioRecordingService` session state,
  - `SpeakerDiarizationService` pipeline,
  - transcript chunk persistence + retry queue,
  - note insertion intents via `EditorSession`.
- **Avoid:** long-running audio/ML tasks tied to the view lifecycle only.

### F4: AppLockView + security orchestration integration
- **Goal:** preserve trust and privacy while staying friction-light.
- **UX pattern:**
  - lock state represented at app-shell level (not per-screen hacks),
  - fast biometric unlock path,
  - graceful degraded states for unavailable biometrics / policy-denied contexts.
- **Architecture:** `SecurityOrchestrator` coordinates:
  - `BiometricAuthService`,
  - vault encryption state,
  - inactivity timeout policies,
  - redaction of sensitive previews in note list/search while locked.
- **Avoid:** loading full note preview/snippet content while app is locked.

### F5: Unified advanced-surface navigation model
- **Goal:** prevent modality sprawl.
- **Approach:**
  - add a single `AdvancedSurfaceCoordinator` managing graph/chat/audio/security surfaces,
  - enforce one-primary + one-secondary advanced surface visible at once,
  - serialize presentation priorities (security > active capture > chat > graph).
- **Avoid:** independent sheet booleans in root views that conflict under rapid interactions.

### F6: Super-App interaction quality and a11y standards
- All advanced surfaces must support:
  - keyboard navigation + shortcuts,
  - VoiceOver landmarks/labels,
  - continuity between iOS/iPadOS/macOS interactions,
  - state restoration on relaunch where appropriate.
- Add telemetry for:
  - modal open/close churn,
  - interruption rates during writing,
  - recovery success after backgrounding during active capture/chat.

---

## 6) Proposed File/Module Restructure

```text
QuartzKit/
  Sources/QuartzKit/
    Presentation/
      Workspace/
        WorkspaceView.swift
        WorkspaceStore.swift
        AppCoordinator.swift
      Sidebar/
        VaultNavigationSidebar.swift
        VaultNavigatorStore.swift
      NoteList/
        NoteListSidebar.swift
        NoteListStore.swift
        NoteListRow.swift
      Editor/
        EditorContainerView.swift
        EditorSession.swift
        EditorStore.swift
        EditorRecoveryService.swift
      Inspector/
        InspectorSidebar.swift
        InspectorStore.swift
        TOCView.swift
      SuperApp/
        AdvancedSurfaceCoordinator.swift
        KnowledgeGraphStore.swift
        VaultChatStore.swift
        AudioCaptureStore.swift
        SecurityOrchestrator.swift
    Domain/
      Notes/
        NoteListItem.swift
        NotePreview.swift
    Data/
      PreviewIndex/
        NotePreviewIndexer.swift
        NotePreviewRepository.swift
        SnippetExtractor.swift
```

---

## 7) Delivery Gates (Definition of Done)

1. **Layout gate:** three-pane workflow functional on macOS + iPadOS, graceful compact fallback on iOS.
2. **Performance gate:**
   - 10k-note vault loads preview list under target budget.
   - typing remains stable (no cursor jump regressions) on long docs.
   - no perceptible flicker during typing, scrolling, selection, or mode toggles on reference devices.
   - IME/RTL matrix passes (CJK, composed text, bidirectional scripts, dictation, handwriting).
3. **Inspector gate:** active ToC sync + metadata/tag edits live-update safely.
4. **Design gate:** focus mode, sidebar transitions, and task toggles have semantic micro-interactions.
   - toolbar/icon system passes consistency checklist (spacing, hierarchy, symbol sizing, interaction states).
   - command parity matrix passes (toolbar/menu/shortcut/palette alignment).
5. **Accessibility gate:** Dynamic Type, VoiceOver rotor headings, keyboard-first navigation pass.
6. **Durability gate:** crash-recovery replay restores unsaved edits safely and predictably.
7. **Super-App gate:** advanced modalities (graph/chat/audio/security) integrate without degrading core writing flow or causing modal conflicts.

---

## 8) Final Strategic Guidance

Do not chase “feature parity” first. ADA-level products win by **coherence**: architecture, motion, typography, and system behaviors feel like one intentional product.

For Quartz, the highest-leverage sequence is:
1. **three-pane shell**,
2. **preview index pipeline**,
3. **editor session hardening**,
4. **inspector synchronization**,
5. **micro-interaction and typography polish**.

Execute this in measured phases with instrumentation, and Quartz can credibly surpass current markdown leaders on native quality.

---

## 9) Deep Research Appendix — Inline Markdown Parsing Options (Implementation Proposals + Source Docs)

This section is a practical research pack for implementation agents (including Claude/Codex) so they can build against primary docs and concrete parser choices.

### 9.1 Parser strategy options (ranked)

#### Option A (Recommended): `cmark-gfm` core + Quartz incremental invalidation layer
- **Why:** battle-tested CommonMark/GFM behavior with broad ecosystem confidence; deterministic AST baseline.
- **How to use in Quartz:**
  1. Parse full document snapshots in background for canonical AST truth.
  2. Keep TextKit 2 editing lane independent and low-latency.
  3. Recompute only dirty block neighborhoods on keystrokes for decorations.
  4. Periodically reconcile incremental view-state with canonical AST.
- **Tradeoff:** C interop/FFI and AST bridge code required, but behavior quality is predictable.

#### Option B: `tree-sitter-markdown` incremental CST for live editor + canonical parser for export/validation
- **Why:** excellent incremental parsing model for editor responsiveness and dirty-range updates.
- **How to use in Quartz:**
  1. Use tree-sitter for live structural updates during typing.
  2. Map CST nodes to styling spans and ToC updates incrementally.
  3. Validate/save/export with canonical CommonMark/GFM parser to keep output semantics stable.
- **Tradeoff:** dual-parser architecture complexity; requires robust reconciliation tests.

#### Option C (Not recommended for core): regex/token-only inline parser
- **Why not:** fastest to prototype, but correctness debt explodes on nested edge cases and IME/composed text.
- **Use only for:** lightweight snippet extraction in preview list (never as canonical editor parser).

### 9.2 Proposed decision framework

Score each candidate parser architecture against:
1. CommonMark/GFM conformance on fixture corpus.
2. Incremental update cost per keystroke.
3. IME/composed-text safety under rapid edits.
4. Ease of mapping AST/CST ranges to TextKit 2 ranges.
5. Long-term maintainability (bug surface + testability).

Recommendation today: **A as canonical + B-style incremental techniques where needed** (hybrid).

### 9.3 Benchmark & validation harness to add before final parser choice

- Build a `ParserBench` target with:
  - cold parse latency (small/medium/huge docs),
  - incremental edit latency (insert/delete around emphasis/list/table/fence boundaries),
  - peak memory during sustained typing,
  - correctness delta vs golden snapshots.
- Maintain three fixture sets:
  1. spec-conformance fixtures (CommonMark/GFM),
  2. editor-stress fixtures (real vault notes),
  3. pathological fixtures (deep nesting, mixed unicode/emoji/RTL/IME).

### 9.4 Primary documentation & repositories (implementation references)

#### Markdown specs / parsers
- CommonMark Spec: https://spec.commonmark.org/spec
- GFM Spec: https://github.github.com/gfm/
- `cmark-gfm` (GitHub fork of cmark): https://github.com/github/cmark-gfm
- `tree-sitter-markdown`: https://github.com/tree-sitter-grammars/tree-sitter-markdown

#### Apple text system references
- Meet TextKit 2 (WWDC21): https://developer.apple.com/videos/play/wwdc2021/10061/
- What’s new in TextKit and text views (WWDC22): https://developer.apple.com/videos/play/wwdc2022/10090/
- `NSTextLayoutManager`: https://developer.apple.com/documentation/uikit/nstextlayoutmanager
- `NSTextContentManager`: https://developer.apple.com/documentation/uikit/nstextcontentmanager
- `NSTextContentStorage`: https://developer.apple.com/documentation/uikit/nstextcontentstorage
- `NSTextRange`: https://developer.apple.com/documentation/appkit/nstextrange

### 9.5 “Use this with Claude/Codex” implementation brief

When delegating implementation:
1. Specify the canonical parser choice (A vs hybrid A+B) before coding.
2. Require new code to include fixture-based tests for each markdown feature touched.
3. Require benchmark output for any parser/render pipeline changes.
4. Reject PRs that improve speed but regress AST correctness or IME selection stability.
5. Keep parser, styling, and TextKit bridging code in separate modules for traceability.

---

## 10) Apple Documentation Canon (Liquid Glass, Native UI, Text, AI, Audio, Security)

This is the curated Apple-first documentation stack to use while implementing Quartz.  
Rule: if a design/engineering choice conflicts with these references, default to Apple guidance unless there is a measured product reason not to.

### 10.1 Human Interface + platform design foundations

- Apple Human Interface Guidelines (overview): https://developer.apple.com/design/human-interface-guidelines/
- Designing for iOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-ios
- Designing for iPadOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados
- Designing for macOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
- Color and contrast: https://developer.apple.com/design/human-interface-guidelines/color
- SF Symbols (design and usage): https://developer.apple.com/sf-symbols/
- Apple Design Resources: https://developer.apple.com/design/resources/

### 10.2 “Liquid Glass” aesthetic (materials, vibrancy, depth)

Use this cluster for the “glass” look while keeping performance and legibility:
- SwiftUI `Material`: https://developer.apple.com/documentation/swiftui/material
- SwiftUI `foregroundStyle(_:)`: https://developer.apple.com/documentation/swiftui/view/foregroundstyle(_:)
- SwiftUI `background(_:in:fillstyle:)`: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
- SwiftUI `compositingGroup()`: https://developer.apple.com/documentation/swiftui/view/compositinggroup()
- HIG materials/background depth guidance: https://developer.apple.com/design/human-interface-guidelines/materials
- HIG blur/translucency legibility guidance: https://developer.apple.com/design/human-interface-guidelines/visual-design

Implementation note: treat “Liquid Glass” as a composition of **material + depth + motion restraint + contrast correctness**, not as heavy blur everywhere.

### 10.3 Navigation, split view, toolbars, and commands

- `NavigationSplitView`: https://developer.apple.com/documentation/swiftui/navigationsplitview
- `NavigationStack`: https://developer.apple.com/documentation/swiftui/navigationstack
- `ToolbarItem` / `ToolbarItemGroup`: https://developer.apple.com/documentation/swiftui/toolbaritem
- `Commands` (macOS/iPad keyboard/menu): https://developer.apple.com/documentation/swiftui/commands
- `searchable`: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)
- WWDC: The SwiftUI cookbook for navigation: https://developer.apple.com/videos/play/wwdc2022/10054/

### 10.4 Text editing + TextKit 2 core references

- Meet TextKit 2 (WWDC21): https://developer.apple.com/videos/play/wwdc2021/10061/
- What’s new in TextKit and text views (WWDC22): https://developer.apple.com/videos/play/wwdc2022/10090/
- `NSTextLayoutManager`: https://developer.apple.com/documentation/uikit/nstextlayoutmanager
- `NSTextContentManager`: https://developer.apple.com/documentation/uikit/nstextcontentmanager
- `NSTextContentStorage`: https://developer.apple.com/documentation/uikit/nstextcontentstorage
- `NSTextSelectionNavigation`: https://developer.apple.com/documentation/uikit/nstextselectionnavigation
- `NSTextRange`: https://developer.apple.com/documentation/appkit/nstextrange

### 10.5 Animation, interaction feel, and feedback

- SwiftUI animation overview: https://developer.apple.com/documentation/swiftui/animation
- `withAnimation`: https://developer.apple.com/documentation/swiftui/withanimation(_:_:)
- `PhaseAnimator`: https://developer.apple.com/documentation/swiftui/phaseanimator
- `symbolEffect`: https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)
- `sensoryFeedback`: https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)
- HIG motion: https://developer.apple.com/design/human-interface-guidelines/motion

### 10.6 Typography and readability

- SF Pro and platform typography guidance: https://developer.apple.com/fonts/
- Dynamic Type: https://developer.apple.com/documentation/swiftui/dynamictypesize
- `Font` in SwiftUI: https://developer.apple.com/documentation/swiftui/font
- HIG typography: https://developer.apple.com/design/human-interface-guidelines/typography

### 10.7 Accessibility requirements

- Accessibility overview: https://developer.apple.com/accessibility/
- SwiftUI accessibility modifiers: https://developer.apple.com/documentation/swiftui/accessibility
- VoiceOver and assistive tech guidance: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Reduced motion handling: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion

### 10.8 AI, App Intents, and system integration

- App Intents: https://developer.apple.com/documentation/appintents
- Spotlight indexing (Core Spotlight): https://developer.apple.com/documentation/corespotlight
- User Activities / Handoff: https://developer.apple.com/documentation/foundation/nsuseractivity
- Writing Tools (platform availability dependent): https://developer.apple.com/documentation/uikit/uitextview/writingtoolsbehavior

### 10.9 Audio + speech + diarization-adjacent stack

- Speech framework: https://developer.apple.com/documentation/speech
- AVAudioSession: https://developer.apple.com/documentation/avfaudio/avaudiosession
- AVAudioRecorder (or modern capture pipeline alternatives): https://developer.apple.com/documentation/avfaudio/avaudiorecorder
- SoundAnalysis (where relevant): https://developer.apple.com/documentation/soundanalysis

### 10.10 Security and privacy stack

- LocalAuthentication (Face ID / Touch ID): https://developer.apple.com/documentation/localauthentication
- Keychain Services: https://developer.apple.com/documentation/security/keychain_services
- File protection and data security: https://developer.apple.com/documentation/foundation/fileprotectiontype
- App Transport Security and privacy fundamentals: https://developer.apple.com/documentation/security/preventing_insecure_network_connections

### 10.11 Implementation rule for agents

When Claude/Codex proposes architecture or UI changes:
1. It must cite at least one relevant Apple doc from this canon.
2. It must explicitly state any intentional deviation from HIG and why.
3. It must include performance/accessibility implications of the chosen API/pattern.

---

## 11) Open-Source Product Research Addendum (Markdown, Highlighting, Transcription, Diarization)

This addendum captures actionable lessons from adjacent products and projects, then maps them to Quartz decisions.

### 11.1 Obsidian (what we can learn despite closed-source core)

Observed:
- `obsidian-releases` explicitly states Obsidian core is not open source, but exposes an extensive plugin system (https://github.com/obsidianmd/obsidian-releases).  
- The published API typings import CodeMirror modules (`@codemirror/state`, `@codemirror/view`) and expose a metadata cache architecture around headings/links/tags/blocks (https://raw.githubusercontent.com/obsidianmd/obsidian-api/master/obsidian.d.ts).

Implication for Quartz:
- Keep Quartz core native (TextKit 2) and **do not introduce a public plugin runtime**; only borrow internal architecture discipline:
  - stable metadata cache contracts,
  - clear command surfaces,
  - strong workspace/vault abstractions for ecosystem growth.

### 11.2 ThiefMD (open-source writing-first editor)

Observed:
- Feature set emphasizes focus modes, library/document switching, live preview, and syntax highlighting.
- Build dependencies include `libgtksourceview-5` and `libmarkdown2`, and acknowledgements reference `highlight.js`, KaTeX, and Pandoc.
- Source: ThiefMD repository/readme (https://github.com/kmwallio/ThiefMD, https://raw.githubusercontent.com/kmwallio/ThiefMD/master/README.md).

Implication for Quartz:
- Preserve “writing-first” behaviors as first-class quality bars:
  - focus/typewriter modes should be latency-safe and animation-light,
  - preview and editor must remain tightly synchronized without keystroke lag,
  - export pipeline should stay decoupled from interactive editing pipeline.

### 11.3 MarkText / Zettlr (open-source markdown workbenches)

Observed:
- MarkText positions speed/usability and explicitly targets CommonMark + GFM + selective Pandoc support.
- MarkText describes virtual-DOM rendering and focused editing modes.
- Zettlr emphasizes publication workflows, citations, code highlighting, and Pandoc-based export flexibility.
- Sources: https://github.com/marktext/marktext, https://github.com/Zettlr/Zettlr

Implication for Quartz:
- Define Quartz markdown conformance envelope explicitly:
  - CommonMark + GFM canonical behavior,
  - clearly documented extension set,
  - publication/export features separated from core typing/render path.

### 11.4 Logseq (knowledge graph + sync complexity lesson)

Observed:
- Logseq publicly frames privacy-first local knowledge with DB graph and RTC evolution, and explicitly warns about data-loss risk in beta phases.
- Source: https://github.com/logseq/logseq

Implication for Quartz:
- For our Super-App layer (graph/chat/audio), use staged rollout + backups + migration safety from day one.
- Treat graph/sync evolution as data-model migrations, not just UI features.

### 11.5 Transcription & diarization stack research (OpenOATS-adjacent)

Observed:
- `OpenOats` (https://github.com/yazinsai/OpenOats) is a SwiftUI/macOS app emphasizing on-device transcription, local-first operation, and auto-saved transcript/session logs.
- OpenOats documents that audio stays on-device, with configurable local/cloud providers for text/embedding/suggestion layers.
- `WhisperX` documents a production-oriented stack: batched Whisper inference, forced alignment, VAD preprocessing, and pyannote-powered diarization with known limitations.
- `pyannote.audio` provides open-source diarization building blocks and pretrained pipelines.
- Sources: https://github.com/yazinsai/OpenOats, https://github.com/m-bain/whisperX, https://github.com/pyannote/pyannote-audio

Implication for Quartz:
- Recommended audio pipeline for Phase F implementation spikes:
  1. ASR transcription (batch-friendly),
  2. VAD segmentation,
  3. forced alignment for timestamp precision,
  4. diarization labeling,
  5. post-editable transcript insertion into notes.
- Keep OpenOats-style operational hygiene:
  - auto-saved transcript/session artifacts,
  - explicit privacy mode messaging,
  - clear consent/legal acknowledgement UX before recording.
- Build explicit UX for imperfect diarization:
  - speaker relabel tools,
  - confidence badges,
  - fast correction workflow in transcript cards.

### 11.6 Plan updates required from this research

1. Add a “Markdown Conformance Contract” doc in-repo:
   - canonical syntax set (CommonMark/GFM),
   - extension policy,
   - parser fallback behavior.
2. Add a “Metadata Cache Contract” for headings/links/tags/blocks updates to support graph/chat without reparsing whole files.
3. Add a transcription “quality budget”:
   - diarization DER targets,
   - timestamp alignment tolerance,
   - correction-time UX KPI.
4. Add a “beta safety protocol” for advanced modalities:
   - migration backups,
   - kill switch,
   - user-visible beta labeling.

---

## 12) Native iCloud Sync, Automation-First Testing, and Self-Healing Operations

This section addresses the product constraints explicitly requested: Apple-native iCloud behavior, intuitive onboarding choices, exhaustive automation, and robust observability/recovery.

### 12.1 Native iCloud sync architecture (Apple-first, file-based vaults)

#### Onboarding choice model (required)
At onboarding, user must choose one of:
1. **Quartz iCloud (Native)**  
   - Create/use vault in the app’s ubiquity container Documents folder (`FileManager.url(forUbiquityContainerIdentifier:)`).  
   - Presents as app-owned iCloud Drive area with native app identity semantics.
2. **Open existing folder vault**  
   - User selects any local/iCloud folder via picker/bookmark flow.
3. **Create folder vault (manual location)**  
   - User chooses path; app creates vault structure.

#### Architectural guardrails
- Add `VaultStorageMode`:
  - `.ubiquityContainer`
  - `.externalFolderBookmark`
- Route all file I/O through a `VaultFileCoordinator` abstraction so sync mode differences do not leak into editor/preview code.
- Keep Core Spotlight indexing mode-aware (domain identifier per vault + storage mode).
- Add explicit conflict-resolution policy:
  - auto-merge safe metadata updates,
  - queue manual resolution UI for content conflicts,
  - never silently discard remote changes.

### 12.2 UX requirements for intuitive onboarding

- Onboarding copy should explain tradeoffs in one sentence per mode:
  - “Quartz iCloud: easiest sync across Apple devices.”
  - “Folder Vault: full manual control and compatibility.”
- Show recommended option first: **Quartz iCloud (Recommended)**.
- Provide migration path later in Settings (folder vault → native iCloud container).
- Add “sync health” indicator in sidebar/footer with human-readable status and actionable remediation.

### 12.3 Automation-first quality strategy (“manual testing minimized”)

#### Testing pyramid (enforced in CI)
1. **Parser/editor unit tests** (AST/span, selection mapping, IME matrix fixtures)
2. **Service integration tests** (preview indexer, cloud sync flows, conflict paths, recovery)
3. **UI tests** (onboarding flows, three-pane navigation, editor interactions, inspector, chat/audio/security surfaces)
4. **Resilience tests** (app termination during write/sync/capture + recovery assertions)
5. **Performance tests** (typing latency, list scroll FPS, parse deadlines)

#### CI policy
- PRs touching editor/sync/audio/security cannot merge without:
  - passing unit + integration + UI suites,
  - zero new crashers in resilience scenarios,
  - performance budget non-regression.
- Keep deterministic fixtures for cloud/sync tests (local test containers + mocked iCloud events where needed).

### 12.4 Error handling, logs, and “self-healing” behavior

#### Logging architecture
- Add structured logging with severity levels (`debug/info/warn/error/fault`) and stable event IDs.
- Persist warning/error logs to:
  - native iCloud mode: app container log folder (rotating files),
  - external folder mode: vault-local `.quartz/logs/`.
- Redact sensitive content by default (no raw note bodies in error logs unless explicit dev mode).

#### Self-healing mechanisms
- Automatic retries with backoff for transient sync/index/network failures.
- Dead-letter queue for operations that repeatedly fail (user-visible recovery actions).
- Recovery jobs on launch:
  - replay pending write journal,
  - re-run failed spotlight/index sync tasks,
  - verify cache consistency and rebuild if checksum drift detected.

#### Developer support
- Add “Export Diagnostics” action from Settings:
  - anonymized logs,
  - recent error timeline,
  - environment/build metadata,
  - optional user-consented session traces.

### 12.5 Concrete plan deltas to enforce this section

1. Add **Phase G — Cloud + Reliability Hardening** after Phase F:
   - onboarding storage-mode flows,
   - ubiquity container provisioning checks,
   - sync conflict automation suite,
   - logging/self-healing services.
2. Add modules:
   - `Cloud/VaultStorageMode.swift`
   - `Cloud/VaultFileCoordinator.swift`
   - `Cloud/UbiquityVaultProvider.swift`
   - `Reliability/QuartzLogger.swift`
   - `Reliability/RecoveryCoordinator.swift`
3. Add release gates:
   - iCloud onboarding E2E passes on clean device,
   - sync conflict scenarios have deterministic expected outcomes,
   - diagnostics export produces valid redacted bundle,
   - resilience suite passes forced-termination scenarios.

---

## 13) Agentic Organization Proposal (Claude-Driven, Apple-True, Low-Hallucination)

This section defines an operational “AI software organization” so roadmap items can be handed off and executed with high autonomy and tight quality control.

### 13.1 Core operating principles

1. **Apple-source-first**  
   Every architecture/UI decision must cite at least one Apple primary source from Section 10.
2. **Evidence before implementation**  
   Agents must gather and attach evidence (docs, existing code references, tests) before coding.
3. **Two-layer review minimum**  
   No change merges without one technical review + one UX/HIG review.
4. **Deterministic delivery**  
   Every task has explicit acceptance tests, performance budgets, and rollback notes.
5. **No silent assumptions**  
   Any uncertainty is logged as a “decision risk” with owner + deadline.

### 13.2 Suggested subagent org chart

#### A) Product/Program Layer
- **Roadmap Orchestrator Agent**
  - owns backlog decomposition by phase (A–G, Super-App)
  - writes milestone briefs, dependencies, and release scope
- **Specification Agent**
  - turns feature requests into implementation specs + acceptance criteria
  - maps requirements to Apple docs and existing Quartz modules

#### B) Architecture/Platform Layer
- **Apple Architecture Agent**
  - enforces split-view, state-flow, and module boundaries
  - blocks non-native patterns unless explicitly approved
- **Editor Core Agent**
  - owns `EditorSession`, parser/render pipeline, IME/selection correctness
- **Cloud & Reliability Agent**
  - owns `VaultStorageMode`, iCloud flows, recovery, logging/self-healing

#### C) Feature Layer
- **Workspace UX Agent**
  - three-pane shell, sidebar/note-list/inspector interactions
- **Super-App Modalities Agent**
  - graph/chat/audio/security integration and modal coordination
- **Audio Intelligence Agent**
  - transcription/diarization pipeline and transcript UX

#### D) Quality Layer
- **Test Automation Agent**
  - generates/maintains unit, integration, UI, resilience, and perf suites
- **HIG/Accessibility Reviewer Agent**
  - checks design coherence, Dynamic Type, VoiceOver, motion compliance
- **Release Safety Agent**
  - feature flags, kill switches, migration checks, rollback playbooks

### 13.3 Anti-hallucination protocol (mandatory)

For every task, each agent must produce:
1. **Source Pack**
   - Apple docs used (URLs),
   - repository files touched,
   - external OSS references (if any).
2. **Claim Ledger**
   - each major claim tagged as `verified`, `inferred`, or `assumed`.
3. **Risk Ledger**
   - unresolved uncertainties + mitigation plan.
4. **Verification Log**
   - exact commands run,
   - test outputs,
   - perf comparisons vs baseline.

If a claim cannot be verified from source pack, it must not be presented as fact.

### 13.4 Standard execution workflow per roadmap item

1. **Intake**
   - Roadmap Orchestrator opens a task brief (goal, scope, dependencies, owner agents).
2. **Spec pass**
   - Specification Agent writes acceptance criteria + test matrix.
3. **Architecture gate**
   - Apple Architecture Agent validates alignment with Sections 10–12.
4. **Implementation**
   - feature agents code in bounded scope branches.
5. **Automation gate**
   - Test Automation Agent updates/executes tests; failures block merge.
6. **Dual review**
   - technical review + HIG/accessibility review.
7. **Release gate**
   - Release Safety Agent validates flags, rollback path, migration notes.

### 13.5 Artifact templates to keep org scalable

- **Feature Spec Template**
  - user outcome, Apple doc references, API choices, anti-patterns, acceptance tests.
- **PR Template**
  - summary, source pack, claim ledger, risk ledger, test evidence, rollback notes.
- **Post-merge Report**
  - production metrics impacted, regressions seen, follow-up tasks.

### 13.6 Agent KPIs (organization health)

- Merge success rate without hotfix.
- Regression rate per subsystem (editor/cloud/audio/ui).
- Test coverage trend (unit/integration/ui/perf).
- Performance budget compliance rate.
- Accessibility/HIG review pass rate on first submission.
- Mean time to recovery from failed releases.

### 13.7 Hand-off contract for future roadmap items

When you provide a new roadmap item, the org should always return:
1. implementation plan,
2. source-backed rationale,
3. task breakdown by subagent,
4. automated test plan,
5. rollout + rollback strategy,
6. known risks and open questions.

This keeps the system autonomous while still predictable and auditable.

### 13.8 Expanded specialist agents (Agents 6–12)

These agents are explicitly empowered to block releases when their constraints are violated.

#### 🛡 Agent 6: Security & Privacy Auditor (Phase F4 + system-wide)
- **Role:** SecOps & Cryptography Engineer
- **Primary mission:**
  - red-team all data flows touching note content,
  - validate `VaultEncryptionService` and `BiometricAuthService`,
  - ensure Spotlight indexing and logging never leak plaintext while locked.
- **Hard constraints:**
  - no UI work,
  - must audit background tasks, temp files, caches, and crash/memory dump exposure paths,
  - must produce leakage-proof evidence before release sign-off.

#### 🏎 Agent 7: Performance & Instruments Agent (Phase C3 + E3)
- **Role:** Optimization & Memory Profiler
- **Primary mission:**
  - protect 120fps interaction targets on ProMotion devices,
  - write XCTest metrics and Instruments-driven perf baselines,
  - audit `KnowledgeGraphView` and TextKit 2 pipeline for leaks/retain cycles/GPU overdraw.
- **Hard constraints:**
  - focus only on complexity, frame pacing, memory, and rendering latency,
  - has release-block authority for frame drops/perf regressions.

#### 🗄 Agent 8: Schema & Migration Agent (data persistence)
- **Role:** CoreData/SwiftData & SQLite Architect
- **Primary mission:**
  - manage schema/versioning for `NotePreviewIndexer`, `GraphCache`, and reliability stores,
  - provide zero-data-loss migrations and crash-safe write semantics.
- **Hard constraints:**
  - no UI work,
  - every migration must be reversible or recoverable,
  - must implement self-healing startup checks after interrupted writes.

#### 👔 Agent 9: Market Intelligence Agent (strategy)
- **Role:** Competitor Analyst & Product Director
- **Primary mission:**
  - benchmark planned features vs Bear/Ulysses/Obsidian/Craft,
  - align sequencing with StoreKit packaging and monetization strategy,
  - ensure Quartz differentiation remains native-first (not a clone roadmap).
- **Hard constraints:**
  - no production code,
  - output only product specs, positioning briefs, and prioritization memos.

#### ⚖️ Agent 10: Principal Code Reviewer (merge gatekeeper)
- **Role:** Staff Swift Engineer & Gatekeeper
- **Primary mission:**
  - enforce Swift 6 concurrency (`Sendable`, actors, isolation correctness),
  - enforce SOLID/modularity boundaries and componentized SwiftUI design,
  - reject oversized view/state coupling patterns.
- **Hard constraints:**
  - final technical sign-off required before merge,
  - can reject any PR with monolithic views or unsafe concurrency.

#### 🏆 Agent 11: ADA Judge (Phase E excellence gate)
- **Role:** Apple Design Award Reviewer
- **Primary mission:**
  - score features on magic/taste/delight (not just correctness),
  - enforce PhaseAnimator usage where meaningful, semantic `sensoryFeedback`, and editorial typography quality,
  - validate “Liquid Glass” depth without legibility/perf compromise.
- **Hard constraints:**
  - cannot approve “basic HIG compliance” as sufficient,
  - can block release on interaction/design quality deficits.

#### 🌪 Agent 12: Chaos & Functional QA Agent (reliability)
- **Role:** Chaos Engineer
- **Primary mission:**
  - design destructive/race-condition scenarios across editor, sync, audio, and lock state,
  - force automation coverage for catastrophic edge cases (lock during dictation + sync conflict + lifecycle interruption, etc.).
- **Hard constraints:**
  - no happy-path-only test plans,
  - must prioritize failure-mode coverage and recovery determinism.

### 13.9 Specialist-agent review matrix (who must approve what)

- **Security-sensitive change:** Agent 6 + Agent 10 required.
- **Performance-sensitive change:** Agent 7 + Agent 10 required.
- **Persistence/schema change:** Agent 8 + Agent 10 required.
- **Product scope/positioning change:** Agent 9 + Roadmap Orchestrator required.
- **UI/interaction polish release:** Agent 11 + HIG/Accessibility Reviewer required.
- **Reliability/race-condition closure:** Agent 12 + Test Automation Agent required.

### 13.10 Additional specialist agents (Agents 13–17)

#### 🎨 Agent 13: Design System Steward
- **Role:** Design Systems Architect
- **Primary mission:**
  - maintain canonical tokens (type scale, spacing, radii, icon sizing, materials, motion timing),
  - enforce component consistency across iOS/iPadOS/macOS,
  - own visual regression baselines and design debt backlog.
- **Hard constraints:**
  - no one-off styling merged without token/component alignment,
  - can block UI merges that bypass design-system primitives.

#### 🧰 Agent 14: Developer Experience & Tooling Agent
- **Role:** Build/Tooling Productivity Engineer
- **Primary mission:**
  - keep local dev setup fast/reproducible,
  - maintain lint/format/test tooling and CI ergonomics,
  - eliminate flaky tests and improve feedback loops.
- **Hard constraints:**
  - no feature ownership,
  - must optimize developer throughput and pipeline reliability.

#### 📊 Agent 15: Telemetry & Product Analytics Agent
- **Role:** Product Data Engineer
- **Primary mission:**
  - define and implement event/KPI instrumentation for editor, sync, and UX funnels,
  - maintain weekly KPI dashboards tied to roadmap decisions,
  - detect regressions via anomaly alerts.
- **Hard constraints:**
  - telemetry must be privacy-safe, minimal, and explicitly documented,
  - can block releases lacking required observability signals.

#### 🧪 Agent 16: Beta Operations & User Research Agent
- **Role:** TestFlight Ops + UX Research Lead
- **Primary mission:**
  - manage beta cohorts and structured feedback cycles,
  - convert user pain points into reproducible specs and prioritized backlog items,
  - track satisfaction/retention impact of each release.
- **Hard constraints:**
  - no direct production feature coding,
  - must require reproducible evidence before escalating issues.

#### ⚖️ Agent 17: Legal/Compliance Agent (Audio/Privacy/AI)
- **Role:** Privacy & Compliance Specialist
- **Primary mission:**
  - validate consent flows, retention policies, and disclosure copy for recording/transcription/AI features,
  - ensure regional compliance constraints are represented in product specs and release checklists,
  - audit diagnostics/log export behavior for policy conformance.
- **Hard constraints:**
  - release-block authority for non-compliant privacy/legal flows,
  - no silent policy deviations without documented sign-off.

### 13.11 Expanded approval matrix (including Agents 13–17)

- **Design-system impacting UI change:** Agent 13 + Agent 11 required.
- **CI/tooling or test infra change:** Agent 14 + Agent 10 required.
- **Telemetry/KPI instrumentation change:** Agent 15 + Agent 6 required.
- **Beta release readiness:** Agent 16 + Release Safety Agent required.
- **Audio/privacy/AI policy-sensitive change:** Agent 17 + Agent 6 required.

### 13.12 Additional critical roles (Agents 18–19)

#### 💳 Agent 18: StoreKit & Monetization Engineer
- **Role:** StoreKit 2 + Entitlements Specialist
- **Primary mission:**
  - implement and maintain StoreKit 2 purchase flows, subscription lifecycle, and entitlement gating,
  - own serverless/device-side verification strategy (including transaction updates and revocation handling),
  - ensure premium features cannot be unlocked by client-side UI bypasses.
- **Hard constraints:**
  - must reject deprecated or legacy StoreKit 1 patterns unless explicitly required for compatibility,
  - must keep `.storekit` configuration, tests, and production product IDs aligned,
  - must provide anti-bypass tests for paywall, entitlement refresh, and offline state transitions.

#### 🌍 Agent 19: Localization & Cultural Adaptation Agent
- **Role:** Internationalization, Typography, and Regional UX Specialist
- **Primary mission:**
  - manage localization quality beyond translation (layout, truncation, tone, locale formatting),
  - validate CJK typography behavior in editor and previews (line height, wrapping, punctuation handling),
  - validate RTL behavior for three-pane shell, inspector, and toolbars.
- **Hard constraints:**
  - no release if key flows fail in top target locales/scripts,
  - must run locale/RTL snapshot and UI tests for critical surfaces,
  - must ensure localized copy remains consistent with HIG tone and accessibility labels.

### 13.13 Final approval matrix extension (StoreKit + Localization)

- **Monetization/paywall/entitlement change:** Agent 18 + Agent 10 + Agent 17 required.
- **Localization/RTL/CJK-sensitive UI change:** Agent 19 + Agent 11 + HIG/Accessibility Reviewer required.
- **Pricing-packaging feature decision:** Agent 9 + Agent 18 required.
