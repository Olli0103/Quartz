# Quartz v2.0 Roadmap

**Prerequisite**: v1.0 shipped and stable — `scripts/ci_phase3.sh` passes with zero failures (see `ROADMAP_V1.md`).

**Goal**: Expand Quartz from a great markdown editor into a personal knowledge operating system — with ambient audio intelligence, document scanning, advanced graph features, and ecosystem breadth.

**Test Inheritance**: Every phase in v2 inherits the FULL v1 test suite. No v1 test may regress. Every new module gets the same treatment: unit + integration + accessibility + performance + E2E + self-healing.

---

## Self-Healing Doctrine (Continued from v1)

The autonomous loop from v1 continues and expands:

```
1. Reproduce failure (headless CI catches it)
2. Classify failure (self-healing matrix routes it)
3. Localize fault (targeted test pinpoints module)
4. Patch minimally (fix with explicit rationale)
5. Re-run targeted tests
6. Re-run full matrix (v1 + v2)
7. If still failing → escalate to next matrix strategy
```

**v2 additions**: Audio memory budget enforcement, OCR golden fixture regression, CRDT merge adversarial testing, and cross-device sync verification join the matrix.

---

## Phase 4 — Audio Intelligence & Scan-to-Markdown ✅ COMPLETE

**Status**: Complete, audited, and green at HEAD.
**Completed**: 2026-04-14
**Report**: `reports/phase4_report.json` (`status: pass`)
**CI**: `scripts/ci_phase4.sh`
**Tests**: Focused Phase 4 SwiftPM suites, full QuartzKit regression, macOS UI smoke, iPhone UI matrix, iPad UI matrix, and macOS coverage all passing.

**Objective**: OpenOats-inspired local-first transcript pipeline + native VisionKit scanning.

### 4.1 Audio Intelligence Core

Native Swift 6 audio capture and processing shared across platforms:

- **AVAudioEngine** capture graph with bounded ring-buffer chunking.
- **On-device ASR** via Speech framework (or Apple Intelligence when available).
- **Diarization** with target < 150MB RAM steady-state.
- **Summarization templates**: decision log, action items, Q&A digest, follow-up email draft.
- Session-level autosave with transcript artifacts persisted as plain markdown.

### 4.2 Live Capsule UI

Floating compact recorder interface:

- Recorder state indicator (recording / paused / processing).
- Latency meter.
- Insertion destination picker (which note receives the transcript).
- Minimal chrome — does not obstruct the editor.

### 4.3 VisionKit Document Scanning

- Native `VNDocumentCameraViewController` integration in editor toolbar.
- On-device OCR extraction mapped to generated markdown:
  - Heading detection.
  - Bullet list heuristics.
  - Table inference where confidence threshold passes.
- Hardware capability gating: camera unavailable -> disable scan actions with graceful explanation.

### 4.4 iPadOS Handwriting Pipeline

- PencilKit canvas embeddable inline in notes.
- Real-time handwriting recognition: stroke capture -> OCR extraction -> markdown insertion anchors.
- Scribble-friendly tool affordances and Apple Pencil hover cues.
- Pencil unavailable -> hide drawing insertion, keep OCR import path.

### Phase 4 Test Matrix — FULL APP COVERAGE

**Goal**: v1 full suite still passes. Audio and scan modules get deep coverage. Hardware capability gating verified.

#### A. Audio Intelligence (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `AudioCaptureGraphTests` | AVAudioEngine setup, buffer routing, start/stop lifecycle | Unit |
| `RingBufferTests` | Bounded capacity, backpressure, chunk extraction | Unit |
| `ASRPipelineTests` | Speech recognition accuracy, language handling, error recovery | Integration (mocked input) |
| `DiarizationTests` | Speaker separation, timestamp accuracy, model loading | Integration (mocked input) |
| `SummarizationTemplateTests` | Decision log, action items, Q&A, email — template correctness | Unit |
| `TranscriptPersistenceTests` | Auto-save to markdown, round-trip, metadata | Integration |
| `AudioMemoryBudgetTests` | Steady-state <= 150MB, no leaks over 60-min simulated session | Performance |
| `AudioMainThreadTests` | Zero main-thread stalls during capture + processing | Performance |
| `AudioSessionInterruptionTests` | Phone call, Siri, other app — graceful pause/resume | Integration |
| `LiveCapsuleUITests` | State indicator, latency meter, insertion picker render | Unit + Snapshot |
| `LiveCapsuleVoiceOverTests` | Recorder state announced, controls labeled | Accessibility |
| `LiveCapsuleDynamicTypeTests` | Capsule scales correctly at all type sizes | Snapshot |

#### B. VisionKit & OCR (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `DocumentScanFlowTests` | Camera launch, capture, dismiss, error handling | Integration |
| `OCRExtractionTests` | Text extraction accuracy from golden scan fixtures | Unit |
| `OCRMarkdownMappingTests` | Heading detection, bullet heuristics, table inference | Unit |
| `OCRGoldenFixtureTests` | 20+ document types: receipts, handwritten, typed, mixed | Regression |
| `ScanToEditorInsertionTests` | OCR result inserted at cursor, editor remains interactive | Integration |
| `ScanAccessibilityTests` | Camera UI accessible, result preview announced | Accessibility |

#### C. Handwriting Pipeline (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `PencilKitEmbedTests` | Canvas embeds inline, scrolls correctly, saves strokes | Integration |
| `HandwritingRecognitionTests` | Stroke → OCR → markdown insertion accuracy | Integration (mocked strokes) |
| `PencilHoverTests` | Hover cues appear, tool affordances visible | UI |
| `HardwareCapabilityGatingTests` | Camera absent → scan disabled; Pencil absent → drawing hidden; Low memory → reduced parallelism | Unit |

#### D. v1 Regression (Full — must all still pass)

All Phase 1–3 test suites run unchanged. Zero regressions allowed.

#### E. E2E Flows (New)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `E2E_AudioCaptureFlow` | Tap record → speak → stop → transcript appears in note | Integration |
| `E2E_AudioTemplateFlow` | Record meeting → select "Action Items" template → formatted insertion | Integration |
| `E2E_ScanToNoteFlow` | Tap scan → capture document → OCR → markdown inserted in editor | Integration |
| `E2E_HandwritingFlow` | Draw with Pencil → recognize → markdown inserted | Integration |
| `E2E_AudioWhileEditingFlow` | Recording active → user types in editor → both work simultaneously | Integration |

#### F. Self-Healing Matrix (Phase 4)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| Memory budget breach | `AudioMemoryBudgetTests` > 150MB | Reduce buffer retention, chunk size, model residency; tighten ring buffer backpressure | <= 150MB steady-state |
| Audio main-thread stall | `AudioMainThreadTests` > 16ms | Move processing off main actor; batch UI updates | P95 < 16ms |
| OCR regression | `OCRGoldenFixtureTests` diff | Adjust normalization heuristics and markdown block reconstruction | Golden fixtures pass |
| Diarization drift | `DiarizationTests` accuracy drop | Retune speaker boundary thresholds; check model version | Accuracy within threshold |
| Hardware gate leak | `HardwareCapabilityGatingTests` feature visible when unavailable | Trace capability check; fix conditional | Gating tests green |
| *All v1 failures* | *Same triggers* | *Same actions* | *Same conditions* |

#### Phase 4 CI Script

```bash
#!/bin/bash
# scripts/ci_phase4.sh — Headless Phase 4 validation
set -euo pipefail

echo "=== Phase 4: Audio Intelligence & Scan ==="

# 1. Full v1 regression gate
bash scripts/ci_phase3.sh

# 2. Audio intelligence suite
swift test --package-path QuartzKit --filter "Audio|RingBuffer|ASR|Diarization|Summarization|Transcript|LiveCapsule"

# 3. VisionKit / OCR suite
swift test --package-path QuartzKit --filter "Scan|OCR|PencilKit|Handwriting|HardwareCapability"

# 4. Memory budget (extended 60-min simulation)
swift test --package-path QuartzKit --filter "AudioMemoryBudget|AudioMainThread" --timeout 3600

# 5. New E2E flows
swift test --package-path QuartzKit --filter "E2E_Audio|E2E_Scan|E2E_Handwriting"

# 6. Report
python3 scripts/parse_test_results.py /tmp/quartz_test_output.txt > reports/phase4_report.json

echo "=== Phase 4 Complete ==="
```

### Done When ✅ ALL VERIFIED

- ✅ 60-minute recording session meets memory ceiling and frame budget.
- ✅ OCR structural mapping passes across headings, bullets, numbered lists, and tables.
- ✅ Audio and scan features fully accessible (VoiceOver, Dynamic Type, Reduce Motion).
- ✅ Hardware capability gating correct on all device classes.
- ✅ **ALL v1 tests still green.** (1,508 total @Test, 0 failures)
- ✅ **Self-healing matrix catches audio/scan regressions autonomously.**
- ✅ Revalidated on 2026-04-14 after the test-runner split with fresh iPhone and iPad UI slice passes.

---

## Phase 4.5 — Editor Rebuild

**Status**: In Progress
**Blocks**: Phase 5
**Plan**: `PHASE_4_5_EDITOR_REBUILD.md`

**Objective**: Rebuild Quartz's Markdown editor into a calm, native, semantically-driven writing surface before layering graph, CRDT, and onboarding features on top.

### Why This Exists

Phase 4 completed the feature roadmap, but the editor still shows structural weaknesses:

- attribute drift after edit and reopen
- syntax concealment that is not truly caret-aware
- styling still applied as a repair pass over text storage
- insufficient parity coverage for open -> edit -> close -> reopen flows

Phase 5 is explicitly blocked until these are fixed at the architecture level.

### 4.5 Core Principles

- **Inline editing first**: No detached mini-editors unless accessibility or input constraints force one.
- **Semantic model over paint pass**: Parse output must become stable editor state, not just transient style spans.
- **Caret-aware markdown hiding**: Hidden or faded syntax must respect the active selection and editing context.
- **Native writing, separate preview**: The writing surface stays native TextKit. High-fidelity preview/export can use a separate renderer.
- **Corpus-driven quality**: Real-world markdown fixtures and reopen-parity tests gate every fix.

### 4.5 Workstreams

1. **Reality corpus + parity harness**
   - Build a fixture corpus from real notes and current editor failures.
   - Add reopen, selection, IME, paste, and concealment parity tests.
2. **Semantic document model**
   - Introduce stable block IDs, inline token IDs, dirty-block tracking, and render plans.
3. **Rendering engine rewrite**
   - Replace broad storage repair with block-local semantic re-rendering.
4. **Editing behavior hardening**
   - Fix typing context, undo coalescing, paste normalization, table safety, and selection stability.
5. **Complex block strategy**
   - Define native editor behaviors for links, tasks, tables, math, images, and footnotes.
6. **Preview split**
   - Keep the editor native; isolate richer preview compatibility to a separate path.

### 4.5 Test Matrix — EDITOR SHIP GATE

| Test Suite | What It Covers | Type |
|---|---|---|
| `EditorRenderingParityTests` | open/edit/close/reopen attributed parity | Integration |
| `EditorSelectionParityTests` | selection and cursor stability under rerender | Integration |
| `SyntaxConcealmentTests` | caret-aware hide/fade rules | Integration |
| `TypingContextTests` | heading/list/code/paragraph typing behavior | Integration |
| `EditorSnapshot_macOS` | macOS visual editor corpus | Snapshot |
| `EditorSnapshot_iPhone` | iPhone visual editor corpus | Snapshot |
| `EditorSnapshot_iPad` | iPad visual editor corpus | Snapshot |
| `EditorKeystrokeLatencyTests` | keystroke-to-frame budget | Performance |
| `EditorVoiceOverInteractionTests` | editor accessibility and token announcements | Accessibility |

**Current implementation note (2026-04-14)**:
- macOS editor parity is materially ahead.
- iPhone and iPad editor parity remain blocking work, not backlog.
- current command entry points:
  - `bash scripts/test_editor_excellence.sh`
  - `bash scripts/ci_phase4_5_editor.sh`

### Done When ✅ ALL VERIFIED

- open -> edit -> close -> reopen editor parity is green
- syntax concealment is caret-aware and selection-safe
- complex markdown blocks behave natively in-flow
- typing context never drifts across headings, lists, code, or paragraph boundaries
- editor snapshot suites are green on macOS, iPhone, and iPad
- mobile live-edit parity exists for the critical mutation paths already covered on macOS
- Phase 5 can start without unresolved editor debt

---

## Phase 5 — Knowledge Graph & Onboarding

**Prerequisite**: Phase 4.5 complete.

**Objective**: Lightning-fast graph queries grounded in filesystem truth. Interactive onboarding that builds feature mastery.

### 5.1 Advanced Graph Features

- **CRDT-based sync** (upgrade from v1's optimistic last-write-wins):
  - Vector clock per note lineage.
  - Semantic merge for markdown blocks when line-level merge conflicts occur.
  - Last-writer metadata only as tiebreaker, never sole authority.
- **Graph identity resolution**: backlinks resolved by stable note IDs, not titles.
- **Graph visualization**: Interactive link map with zoom, filter, and cluster detection.
- **Time Machine history**: Diff viewer with "restore as new note" and "overwrite current."

### 5.2 Command Palette

- `Cmd+K` global action palette (macOS, iPadOS with keyboard).
- Scoped note actions + global vault actions.
- `Learn: <Feature>` discovery actions.
- Commandable export presets ("Meeting Minutes PDF", "Research HTML bundle").

### 5.3 Export Pipeline

- Markdown -> AST -> format adapters (PDF / HTML / RTF).
- Typography snapshot tests across macOS / iPadOS / iOS.
- Deterministic templates for consistent output.

### 5.4 Interactive Onboarding (FTUE)

On first launch, a seeded welcome note guides the user through:

1. Create an internal `[[link]]`.
2. Toggle focus mode.
3. Open the graph and follow a backlink.
4. (Optional) Record a short audio note — not required to proceed.
5. (Optional) Scan a document — not required to proceed.

Completion creates a personalized cheatsheet note. Onboarding is re-runnable from Settings.

### 5.5 In-Product Learning

- Inline coach marks for first three uses of complex features only.
- Feature discovery via Command Palette.
- No persistent tooltips or nag screens.

### Phase 5 Test Matrix — FULL APP COVERAGE

#### A. CRDT & Graph (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `VectorClockTests` | Compare, merge, increment, concurrent detection | Unit |
| `CRDTMergeTests` | Line-level merge, block-level semantic merge, tie-break | Unit |
| `CRDTAdversarialTests` | 10,000 randomized concurrent edit streams — zero byte loss | Property |
| `CRDTUpgradeTests` | Migrate from v1 last-write-wins to CRDT without data loss | Integration |
| `GraphIdentityTests` | Stable note IDs across rename, move, delete | Integration |
| `GraphVisualizationTests` | Node layout, link rendering, zoom, filter, cluster detection | Unit + Snapshot |
| `GraphPerformanceTests` | 10,000-node graph renders < 100ms, query < 50ms | Performance |
| `TimeMachineTests` | Revision diff viewer, restore-as-new, overwrite-current | Integration |
| `GraphVoiceOverTests` | Graph nodes and links announced, navigable | Accessibility |

#### B. Command Palette (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `CommandPaletteSearchTests` | Fuzzy match, scoped actions, global actions | Unit |
| `CommandPaletteDispatchTests` | Every registered action dispatches correctly | Integration |
| `CommandPaletteLearnTests` | `Learn:` actions open correct help content | Integration |
| `CommandPaletteVoiceOverTests` | Results announced, navigable, dismissable | Accessibility |
| `CommandPaletteKeyboardTests` | Cmd+K open, arrow nav, Enter select, Escape dismiss | Integration |

#### C. Export Pipeline (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `ExportPDFTests` | Markdown → PDF, typography, layout, images | Snapshot |
| `ExportHTMLTests` | Markdown → HTML, semantic tags, CSS, images | Snapshot |
| `ExportRTFTests` | Markdown → RTF, formatting, lists, tables | Snapshot |
| `ExportPresetTests` | "Meeting Minutes PDF", "Research HTML bundle" presets | Integration |
| `ExportCrossPlatformTests` | Output consistent across macOS / iPadOS / iOS | Snapshot |

#### D. Onboarding (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `FTUEFlowTests` | Complete tutorial path: link → focus → graph → optional audio/scan | Integration |
| `FTUESkipTests` | User can skip any step, app remains fully functional | Integration |
| `FTUERerunTests` | Re-run from Settings works, doesn't duplicate content | Integration |
| `FTUEVoiceOverTests` | Every tutorial step accessible | Accessibility |
| `CheatsheetGenerationTests` | Personalized cheatsheet reflects completed actions | Unit |
| `CoachMarkTests` | Show first 3 uses, dismiss, never return | Unit |

#### E. v1 + Phase 4 Regression (Full)

All Phase 1–4 test suites run unchanged. Zero regressions allowed.

#### F. Self-Healing Matrix (Phase 5)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| CRDT data loss | `CRDTAdversarialTests` byte mismatch | Rewrite vector clock compare and merge strategy; add regression fixture | Zero-byte-loss invariant |
| Graph identity break | `GraphIdentityTests` ID mismatch after rename/move | Trace identity resolution; fix stable ID persistence | Identity stable across operations |
| Export drift | `ExportPDFTests` / `ExportHTMLTests` snapshot diff | Tune AST → format adapter; check template determinism | Export snapshots green |
| Command palette gap | `CommandPaletteDispatchTests` action fails | Trace action registration; fix dispatch | All actions dispatch |
| FTUE deadlock | `FTUEFlowTests` step unreachable | Trace navigation; fix step transition | Tutorial completable |
| *All v1 + Phase 4 failures* | *Same triggers* | *Same actions* | *Same conditions* |

#### Phase 5 CI Script

```bash
#!/bin/bash
# scripts/ci_phase5.sh — Headless Phase 5 validation
set -euo pipefail

echo "=== Phase 5: Knowledge Graph & Onboarding ==="

# 1. Full v1 + Phase 4 regression gate
bash scripts/ci_phase4.sh

# 2. CRDT + Graph
swift test --package-path QuartzKit --filter "VectorClock|CRDTMerge|CRDTAdversarial|CRDTUpgrade|GraphIdentity|GraphVisualization|GraphPerformance|TimeMachine"

# 3. Command Palette
swift test --package-path QuartzKit --filter "CommandPalette"

# 4. Export pipeline
swift test --package-path QuartzKit --filter "Export"

# 5. FTUE / Onboarding
swift test --package-path QuartzKit --filter "FTUE|CoachMark|Cheatsheet"

# 6. CRDT adversarial (extended)
swift test --package-path QuartzKit --filter "CRDTAdversarial" --timeout 1800

# 7. Report
python3 scripts/parse_test_results.py /tmp/quartz_test_output.txt > reports/phase5_report.json

echo "=== Phase 5 Complete ==="
```

### Done When

- CRDT merge passes 10,000 adversarial scenarios with zero byte loss.
- Graph visualization renders correctly with 10,000+ nodes.
- Export produces deterministic, typographically correct output on all platforms.
- FTUE is completable, skippable, and re-runnable.
- **ALL v1 + Phase 4 tests still green.**
- **Self-healing matrix covers graph, export, and onboarding failures.**

---

## Phase 6 — Apple Ecosystem Expansion

### 6.1 visionOS Spatial Workspace

- Spatial knowledge workspace with linked note canvases.
- Gaze + gesture graph traversal.
- "Context Bubbles": pin live transcript, source notes, and decisions in 3D space.

### 6.2 watchOS Quick Capture

- One-tap voice memo capture complication.
- Background sync to iPhone/macOS.
- Quick action intents: "Capture thought", "Append to Daily Note", "Mark action item."

### 6.3 tvOS Read-Only Dashboard

- Presentation mode: project graph, session recaps, decision timeline.
- No editing — display only.

### 6.4 On-Device AI (Foundation Models)

- Summarization, entity extraction, smart tagging via Apple's Foundation Models framework.
- Privacy-first: all processing on-device.
- Graceful degradation on devices without Apple Intelligence.

### 6.5 Cloud AI (User API Key)

- Vault-wide chat with RAG pipeline (already prototyped in v1 codebase).
- User provides their own API key — no Quartz backend required.
- No data retention, explicit consent for every cloud operation.

### Phase 6 Test Matrix

#### A. visionOS (Deep)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `SpatialWorkspaceTests` | Canvas layout, note placement, linking | Integration + Snapshot |
| `GazeNavigationTests` | Gaze targeting, selection, graph traversal | Integration |
| `ContextBubbleTests` | Pin/unpin, content display, spatial positioning | Unit + Snapshot |
| `visionOSAccessibilityTests` | VoiceOver in spatial, switch control, pointer | Accessibility |

#### B. watchOS (Deep)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `VoiceMemoComplicationTests` | Complication renders, tap launches capture | Unit |
| `WatchSyncTests` | Memo syncs to iPhone/macOS vault | Integration |
| `WatchIntentTests` | "Capture thought", "Append to Daily Note", "Mark action item" | Unit |
| `WatchAccessibilityTests` | VoiceOver, haptics, crown navigation | Accessibility |

#### C. AI Features (Deep)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `FoundationModelTests` | Summarization, entity extraction, smart tagging | Integration (mocked model) |
| `AIGracefulDegradationTests` | No Apple Intelligence → features disabled, no crash | Unit |
| `CloudAIConsentTests` | Explicit consent required, no silent cloud calls | Integration |
| `RAGPipelineTests` | Vector search → context → LLM stream → citation | Integration |
| `AIPrivacyTests` | No data retained, API key user-provided, no telemetry | Unit |

#### D. Self-Healing Matrix (Phase 6)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| Spatial layout break | `SpatialWorkspaceTests` snapshot diff | Trace layout constraints; fix spatial positioning | Snapshots green |
| Watch sync loss | `WatchSyncTests` data mismatch | Trace sync pipeline; fix handoff | Sync tests green |
| AI model unavailable | `AIGracefulDegradationTests` crash | Add/fix availability check and fallback | Degradation graceful |
| Privacy leak | `AIPrivacyTests` unauthorized call | Trace consent flow; block unauthorized path | Privacy tests green |
| *All previous failures* | *Same triggers* | *Same actions* | *Same conditions* |

---

## Phase 7 — Monetization (Without Lock-In)

### Principles

- Core app remains fully useful, local-first, free.
- Never monetize user data.
- No forced cloud dependency.

### Pro Tier (Optional)

- Advanced automation templates.
- Team knowledge overlays.
- Premium visual themes and export packs.
- Priority support.

### Phase 7 Test Matrix

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `StoreKitPurchaseTests` | Purchase flow, restore, receipt validation | Integration |
| `ProFeatureGatingTests` | Pro features locked/unlocked correctly | Unit |
| `FreeFeatureIntegrityTests` | Core features NEVER degraded by Pro tier presence | Integration |
| `StoreKitAccessibilityTests` | Purchase UI accessible, price announced, confirmation clear | Accessibility |
| `RefundFlowTests` | Refund revokes Pro, no data loss, graceful downgrade | Integration |

---

## Master CI Pipeline

### Full Self-Healing CI (`scripts/ci_full.sh`)

```bash
#!/bin/bash
# scripts/ci_full.sh — Headless FULL Quartz validation (v1 + v2)
set -euo pipefail

echo "=== Quartz Full Validation Suite ==="
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Build Gate ----
echo "--- Build: All Platforms ---"
xcodebuild build -scheme Quartz -destination 'platform=macOS' | xcpretty
xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro' | xcpretty
xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' | xcpretty

# ---- Unit + Integration Tests ----
echo "--- Tests: QuartzKit (all modules) ---"
swift test --package-path QuartzKit --parallel 2>&1 | tee /tmp/quartz_unit.txt

# ---- Platform Tests ----
echo "--- Tests: macOS ---"
xcodebuild test -scheme Quartz -destination 'platform=macOS' 2>&1 | tee /tmp/quartz_macos.txt
echo "--- Tests: iPhone ---"
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tee /tmp/quartz_iphone.txt
echo "--- Tests: iPad ---"
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tee /tmp/quartz_ipad.txt

# ---- Performance Gate ----
echo "--- Performance Budget ---"
swift test --package-path QuartzKit --filter "Performance|MemoryBudget|MainThread" 2>&1 | tee /tmp/quartz_perf.txt

# ---- Accessibility Gate ----
echo "--- Accessibility Audit ---"
swift test --package-path QuartzKit --filter "VoiceOver|DynamicType|ReduceMotion|ReduceTransparency|IncreaseContrast|VoiceControl|Keyboard|Accessibility" 2>&1 | tee /tmp/quartz_a11y.txt

# ---- E2E Flows ----
echo "--- End-to-End Flows ---"
swift test --package-path QuartzKit --filter "E2E_" 2>&1 | tee /tmp/quartz_e2e.txt

# ---- Self-Healing Report ----
echo "--- Self-Healing Report ---"
python3 scripts/self_heal.py \
  --unit /tmp/quartz_unit.txt \
  --macos /tmp/quartz_macos.txt \
  --iphone /tmp/quartz_iphone.txt \
  --ipad /tmp/quartz_ipad.txt \
  --perf /tmp/quartz_perf.txt \
  --a11y /tmp/quartz_a11y.txt \
  --e2e /tmp/quartz_e2e.txt \
  --output reports/full_report.json \
  --matrix config/self_healing_matrix.json

echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== Report: reports/full_report.json ==="
```

### Self-Healing Matrix Configuration (`config/self_healing_matrix.json`)

The matrix maps failure signals to diagnostic actions and resolution strategies:

```json
{
  "failure_classes": [
    {
      "id": "build_concurrency",
      "signal": "Swift 6 strict concurrency warning|error",
      "action": "Trace actor isolation boundaries",
      "resolution": ["@MainActor annotation", "actor wrapper", "Sendable conformance"],
      "stop": "Zero concurrency diagnostics"
    },
    {
      "id": "frame_budget",
      "signal": "XCTMetric main_thread > 16ms P95",
      "action": "Profile hot path with Instruments template",
      "resolution": ["Move off main actor", "Batch UI updates", "Reduce redraw scope"],
      "stop": "P95 < 16ms"
    },
    {
      "id": "memory_budget",
      "signal": "Audio steady-state > 150MB",
      "action": "Profile allocations with leaks instrument",
      "resolution": ["Reduce buffer retention", "Shrink chunk size", "Tighten backpressure"],
      "stop": "<= 150MB steady-state"
    },
    {
      "id": "snapshot_mismatch",
      "signal": "Pixel-diff fail in snapshot suite",
      "action": "Parse diff region and affected view",
      "resolution": ["Tune padding/frame/material", "Regenerate if intentional"],
      "stop": "Snapshots green all form factors"
    },
    {
      "id": "state_desync",
      "signal": "3-pane integration test mismatch",
      "action": "Trace @Observable propagation graph",
      "resolution": ["Restore single source of truth", "Remove mirrored state"],
      "stop": "Sidebar/list/editor coherent"
    },
    {
      "id": "sync_data_loss",
      "signal": "CRDT/sync property test byte mismatch",
      "action": "Dump merge trace log",
      "resolution": ["Fix hash compare", "Fix merge strategy", "Add adversarial fixture"],
      "stop": "Zero-byte-loss invariant"
    },
    {
      "id": "ocr_regression",
      "signal": "Golden OCR fixture diff",
      "action": "Compare extraction output vs golden",
      "resolution": ["Adjust normalization heuristics", "Fix markdown block reconstruction"],
      "stop": "Golden fixtures pass"
    },
    {
      "id": "accessibility_regression",
      "signal": "AX audit/snapshot failure",
      "action": "Identify unlabeled/misordered elements",
      "resolution": ["Patch labels", "Fix traits", "Fix focus order", "Fix Dynamic Type"],
      "stop": "AX suite fully green"
    },
    {
      "id": "platform_divergence",
      "signal": "Platform-specific test failure on one OS",
      "action": "Trace #if os() branch",
      "resolution": ["Fix conditional compilation", "Add platform-specific path"],
      "stop": "All platforms green"
    },
    {
      "id": "editor_cursor_jump",
      "signal": "CursorStabilityTests snapshot diff",
      "action": "Trace highlight pass and selection preservation",
      "resolution": ["Fix selection save/restore in applyHighlightSpans"],
      "stop": "Cursor snapshots match"
    },
    {
      "id": "keyboard_gap",
      "signal": "KeyboardNavigationTests unreachable control",
      "action": "Identify unreachable element",
      "resolution": ["Add .focusable()", "Add .keyboardShortcut()", "Add tab stop"],
      "stop": "All controls keyboard-reachable"
    }
  ]
}
```

### Self-Healing Script (`scripts/self_heal.py`)

Parses test results, classifies failures against the matrix, emits structured report:

```
{
  "timestamp": "2026-04-02T10:00:00Z",
  "total_tests": 847,
  "passed": 845,
  "failed": 2,
  "failures": [
    {
      "test": "AudioMemoryBudgetTests.test60MinSession",
      "failure_class": "memory_budget",
      "signal": "Steady-state 162MB > 150MB threshold",
      "recommended_action": "Profile allocations with leaks instrument",
      "resolution_strategies": [
        "Reduce buffer retention",
        "Shrink chunk size",
        "Tighten backpressure"
      ],
      "module": "QuartzKit/Domain/Audio",
      "severity": "blocking"
    }
  ],
  "self_healing_status": "2 failures classified, 0 unclassified"
}
```

**Every failure must be classifiable.** An unclassified failure means the matrix needs a new entry — that itself is a blocking issue.

---

## Strategic Moat

By combining:
- Native Apple interaction fidelity (v1).
- Sovereign markdown filesystem ownership (v1).
- Private on-device audio/scan ingestion (v2).
- High-performance graph intelligence (v2).
- Ecosystem breadth across every Apple device (v2).
- **Autonomous self-healing CI that catches every regression headlessly.**

Quartz owns the "personal knowledge cockpit" category on Apple platforms.

The bar remains: Apple Design Award quality — fluid, humane, accessible, technically uncompromising.
