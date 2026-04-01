# Quartz Apple-Native Architecture Audit (2026-04-01)

## Mission Alignment Snapshot
- `README.md` and `CLAUDE.md` are strongly aligned on **editing correctness first**, **native Apple fidelity**, and **accessibility as non-negotiable**.
- The current codebase already contains many right foundations (TextKit 2, NSFileCoordinator wrapper, Reduce Transparency checks, clean package layering), but several critical implementation gaps still break the “trustworthy Apple-native” bar.

---

## Phase 1 — Trust & Correctness Audit

### 1) Editor Integrity (`MarkdownTextView.swift`, `MarkdownTextContentManager.swift`, `MarkdownASTHighlighter.swift`)

#### What is working
- Highlighting is debounced and cancellable (`parseDebounced`, task cancel before reparse).
- IME composition guard exists before and after async parse (`markedTextRange` / `hasMarkedText`).
- Selection and typing attributes are saved/restored around restyling.

#### Critical findings
1. **TextKit 2 contract is bypassed during highlighting and list continuation**
   - In both iOS/macOS `applySpans`, attribute writes go directly through `textStorage.beginEditing/setAttributes/endEditing` and never call `MarkdownTextContentManager.performMarkdownEdit`.
   - `shouldChangeTextIn` for list continuation rewrites `textView.text`/`textView.string` directly instead of surgical `replaceCharacters` path.
   - Impact: increased chance of flicker, layout invalidation churn, and undo stack inconsistencies under heavy edits.

2. **`updateUIView` / `updateNSView` can still create state churn loops with external session updates**
   - Programmatic text diffs are string-based (`uiView.text != text`) and then full text replacement is performed.
   - When external systems mutate text rapidly (AI insertion, cloud merge), this can repeatedly reset selection and retrigger highlights.
   - Impact: cursor jump/flicker during high-frequency update bursts.

3. **Background highlighter base font capture can be stale**
   - highlight task captures `baseFontSize` at task creation, then applies later.
   - During dynamic type or user scale changes, late-arriving task can apply old font metrics momentarily.
   - Impact: visible one-frame “font snap” / caret movement on reflow.

4. **IME protection is partial but not complete for *all* external write paths**
   - Composition is guarded during highlighting, but not explicitly guarded around external full-text assignments in representable updates.
   - Impact: low-frequency but high-severity CJK/emoji composition interruptions when external updates land during marked text sessions.

#### Apple-native target behavior
- Keep native text view as source of truth.
- Only apply surgical attributed/string edits in TextKit transactions.
- Never commit external full replacements while IME composition is active.

---

### 2) List Logic (`MarkdownListContinuation.swift`)

#### Current behavior vs Apple Notes expectation
- ✅ Enter continues bullets (`-`, `*`, `+`).
- ✅ Enter continues numbered lists and increments number.
- ✅ Enter continues checkbox markers and resets next item to unchecked.
- ✅ Enter on empty list marker exits list by removing marker.

#### Gaps / edge mismatches
1. **Continuation is allowed when cursor is mid-line**, splitting content and inserting next marker.
   - Apple Notes behavior generally treats return in middle-of-line as split but list continuation semantics can feel different in numbered/checklist contexts.
2. **Blockquote is treated as list-like continuation (`>`)** which is useful, but should be validated for parity with Apple Notes markdown behavior.
3. **Execution path in editor is non-surgical** (direct full-text replacement), so even correct logic can feel unstable under undo/redo.

---

### 3) Data Integrity (`FileSystemVaultProvider.swift`, `CoordinatedFileWriter.swift`, `SidebarView.swift`)

#### What is working
- `CoordinatedFileWriter` centralizes `NSFileCoordinator` for read/write/move/copy/remove.
- `FileSystemVaultProvider` uses coordinated writes for save/create/rename and fallback coordinated reads.
- iCloud download-on-demand handling exists with timeout.

#### Critical findings
1. **Not all reads are coordinated first**
   - `coordinatedRead` tries direct `Data(contentsOf:)` before coordinated fallback.
   - In iCloud contention windows this can race with coordinated writers.

2. **`handleDrop` in `SidebarView` is not transactional**
   - Returns `true` immediately after scheduling async move tasks.
   - Drop success is reported before filesystem move completion.
   - Impact: UI claims success even when move fails partially or fully.

3. **Daily Note append path bypasses coordinated I/O**
   - `WorkspaceView.appendToDailyNote` uses `FileHandle` and direct `write(to:)` in detached task.
   - This is outside `CoordinatedFileWriter` and can conflict with iCloud sync/file presenters.
   - Impact: silent clobber/partial write risk.

---

## Phase 2 — ADA Visual & Interaction Polish

### 4) Liquid Glass & Materials (`LiquidGlass.swift`)

#### What is working
- Multiple modifiers use `@Environment(\.accessibilityReduceTransparency)` and fall back to `.background`.
- Pure dark mode uses `Color.black` when enabled in dark scheme (true #000 intent).
- Mesh gradient has reduce-motion fallback.

#### Gaps
1. **`MeshGradient` does not currently fall back for Reduce Transparency**
   - It falls back for Reduce Motion only.
   - Recommendation: if Reduce Transparency is enabled, use flatter opaque gradient tokens and avoid translucent layering.

2. **A few direct `.ultraThinMaterial` usage sites outside centralized modifiers** (e.g., sidebar CTA and FAB overlays) may bypass full accessibility fallback consistency.

---

### 5) Three-Pane Shell (`WorkspaceView.swift`, `WorkspaceStore.swift`)

#### What is working
- `NavigationSplitView` correctly bound to central `WorkspaceStore` visibility and compact column.
- Focus mode transitions visibility through store.

#### High-priority issue
1. **No scene persistence for `columnVisibility` / `preferredCompactColumn`**
   - `WorkspaceStore` comments mention SceneStorage bridging, but `ContentView` currently persists note/cursor/scroll only.
   - On iPad Stage Manager / macOS window reactivation, this can manifest as “disappearing sidebar” or unexpected column state resets.

2. **Potential selection desync**
   - `WorkspaceView` holds `sidebarNoteSelection` state then mirrors into `store.selectedNoteURL`; middle column also binds directly to `store.selectedNoteURL`.
   - This dual-path can cause transient divergence during rapid source/selection switches.

---

### 6) Micro-interactions (`QuartzAnimation.swift`)

#### What is working
- Most interactions use modern calm curves (`.smooth`, `.snappy`, restrained springs).
- Haptics abstraction exists via `QuartzFeedback`.

#### Gaps
1. **Not all key interactions use response+dampingRatio style springs**
   - Several use `.smooth/.bouncy`; acceptable but less precise for ADA-level motion tuning targets.
2. **Requested sensoryFeedback hooks are not explicitly wired for both target actions**
   - Checkbox toggles and folder collapse often call `QuartzFeedback.toggle()`, but explicit `.sensoryFeedback` hooks for state changes are inconsistent.

---

## Phase 3 — Intelligence & AI Strategy Audit

### 7) On-device RAG (`IntelligenceEngineCoordinator.swift`, `VectorEmbeddingService.swift`, `AISettingsView.swift`)

#### What is working
- On-device embedding path uses `NLEmbedding` with per-language cache.
- Stable note IDs and chunk-based index are in place.
- Coordinator batches file changes with debounce.

#### High-priority issues
1. **Inefficient persistence pattern during JIT indexing**
   - `processFile` calls `indexNote` then `saveIndex()` for each file in loop.
   - This causes repeated full index writes and unnecessary IO/thermal pressure spikes.

2. **No thermal-pressure-aware throttling in embedding pipeline**
   - No integration with system thermal state to slow/pause indexing.

3. **Privacy controls not explicit enough in settings UX**
   - `AISettingsView` does not clearly expose a first-class “on-device only”/“allow cloud provider” consent gate before network use.

---

### 8) Writing Tools (`OnDeviceWritingToolsService.swift`)

#### Critical finding
1. **Incorrect Foundation Models availability gates**
   - Uses `#available(iOS 26.0, macOS 26.0, *)` in multiple paths while service otherwise claims iOS 18.1+/macOS 15.1+ support.
   - This effectively prevents expected Apple Intelligence path on currently targeted OS versions.

2. **Editor WritingToolsBehavior policy is fixed to `.complete`**
   - Both iOS and macOS editor wrappers set `.complete` unconditionally when available.
   - Missing dynamic policy to switch `.limited` for states like read-only/trash/conflict or unsupported selection modes.

---

## Phase 4 — Prioritized Fix Backlog

| Priority | Area | Issue | User Impact | Fix Strategy |
|---|---|---|---|---|
| **Critical** | Editor | Highlighting/list writes bypass TextKit transaction APIs | Cursor jump, flicker, undo instability | Route all style + list mutations through `MarkdownTextContentManager.performMarkdownEdit` and `replaceCharacters` surgical ops. |
| **Critical** | Data | `SidebarView.handleDrop` returns success before move completion | False-positive DnD success, trust break | Make drop async-transactional: return success only after all moves commit or report partial failure. |
| **Critical** | Data | Daily note append bypasses coordinated writer | iCloud race / potential data loss | Replace `FileHandle` append/create path with `CoordinatedFileWriter` read-modify-write transaction. |
| **Critical** | AI | Foundation Models gated behind iOS/macOS 26 checks | Apple Intelligence path effectively disabled | Normalize availability checks to actual deployment/API availability; add tested fallback ladder. |
| **High** | Workspace | No persisted `columnVisibility` + compact column | “Disappearing sidebar” on Stage Manager/macOS windows | Add `@SceneStorage` bridge for split view visibility + preferred compact column and restore on launch. |
| **High** | Editor | External update path can overwrite during IME composition | CJK/emoji input interruption | Block or defer programmatic text assignment while marked text exists; queue post-composition sync. |
| **High** | RAG | Save index per-file in loop | Thermal spikes, battery hit | Batch all changed notes then single `saveIndex()` per debounce window; optional coalesced background task. |
| **High** | Privacy | AI settings lacks explicit cloud-consent gate | Ambiguous data egress model | Add explicit “Allow Cloud AI” toggle default-off; gate provider calls behind it. |
| **Polish** | Visual | Mesh transparency not tied to Reduce Transparency | Accessibility mismatch | Add reduce-transparency opaque gradient mode for mesh backgrounds. |
| **Polish** | Motion | Mixed motion semantics for critical interactions | Inconsistent “Apple-calm” feel | Standardize key transitions on tuned springs (response + damping ratio targets per interaction class). |
| **Polish** | Haptics | Inconsistent sensory feedback wiring | Reduced tactile affordance | Add explicit feedback on checkbox state changes + folder disclosure toggles in the owning views. |

---

## Phase 5 — Visionary Roadmap (Apple-native only)

### A) Spatial Quartz (visionOS 2)
1. **Ornamented formatting system**
   - Move formatting toolbar into `.ornament(attachmentAnchor:)` with state-aware compact/full variants.
   - Use gaze/hand target sizing and low-amplitude spring transitions.
2. **Depth-based Knowledge Graph windows**
   - Primary note at comfortable reading depth; graph panel as secondary depth layer.
   - Use explicit focus handoff and recenter action; avoid continuously animated depth shifts.
3. **Shared editor session architecture**
   - Keep one authoritative editor model; project specialized visual containers per volume/window.

### B) Semantic Backlinks (embedding-first)
1. **Dual channel backlink model**
   - Channel 1: explicit wiki-links (existing).
   - Channel 2: conceptual matches from `VectorEmbeddingService.findSimilarNoteIDs`.
2. **Confidence-tier UI in `BacklinksPanel`**
   - Group: “Linked” vs “Conceptually Related”.
   - Show short extracted rationale snippet and similarity confidence bucket.
3. **Incremental update strategy**
   - Recompute semantic backlinks only for dirty note + top-k affected neighbors.

### C) PencilKit Fusion (Handwriting → Markdown)
1. **Capture + OCR staging**
   - Keep `PKDrawing` as source artifact; run OCR in actor background queue.
2. **Structure inference pass**
   - Heuristics: checkbox lines (`[ ]`), heading candidates, bullet detection, numbered patterns.
3. **User-confirmed transform sheet**
   - Side-by-side “Recognized Text” and “Markdown Preview”; one-tap insert at cursor via surgical replace.

### D) Audio Intelligence (meeting minutes with diarization)
1. **Pipeline orchestration**
   - Record stream → chunk transcription → speaker diarization alignment → markdown emitter.
2. **Timestamp-linked markdown blocks**
   - Format as heading + per-speaker bullets with tappable time links.
3. **Reliability controls**
   - Confidence scoring, unknown-speaker fallback labels, and editable post-pass before final save.

---

## Recommended Execution Order (2-week stabilization sprint)
1. Editor transactional write-path + IME-safe external sync.
2. Drag/drop transactional semantics + coordinated daily-note writes.
3. Foundation Models availability fix + explicit cloud consent gate.
4. Split-view state persistence for Stage Manager/macOS window reliability.
5. Batch-save embedding index + thermal-aware throttling.
6. Liquid Glass accessibility harmonization + haptics consistency.
