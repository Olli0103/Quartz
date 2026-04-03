# Quartz v1.0 Roadmap

**Goal**: Ship a best-in-class native Apple markdown editor — correct, fast, accessible.

**Positioning**: Bear-class editor smoothness + Obsidian file sovereignty + iA Writer focus purity, built natively for every Apple platform.

**Target**: Apple Design Award contender for Innovation, Interaction, and Inclusivity.

---

## Strategic Principles

1. **Editor correctness before features** — No new capabilities until the editor is rock-solid.
2. **Ship less, ship better** — A great markdown editor beats a mediocre everything-app.
3. **Native over custom** — Use platform APIs, not reinventions.
4. **File sovereignty** — Raw `.md` files are the source of truth, always.
5. **Accessible by default** — Not a follow-up task, a launch requirement.
6. **Test everything, heal autonomously** — Every phase ships tests for ALL app functionality. CI must be able to headlessly identify and resolve every class of issue.

---

## Self-Healing Doctrine

Every phase in this roadmap follows the same loop:

```
1. Reproduce failure (headless CI catches it)
2. Classify failure (self-healing matrix routes it)
3. Localize fault (targeted test pinpoints module)
4. Patch minimally (fix with explicit rationale)
5. Re-run targeted tests
6. Re-run full matrix
7. If still failing → escalate to next matrix strategy
```

**No phase is done until its test suite can headlessly detect every regression in every module it touches — and every module that existed before it.**

---

## Phase 1 — Editor Core Hardening

**Objective**: Eliminate all editor correctness issues. Make typing, highlighting, undo, and IME bulletproof.

### 1.1 Incremental AST Patching

- Replace full-document mutation paths with range-diff patching.
- AST re-parse scoped to edited paragraph ranges only.
- Performance budget: keystroke-to-frame P95 < 8ms (macOS), syntax pass P95 < 12ms for 20k-char notes.

### 1.2 Editor Mutation Transaction Model

Introduce `EditorMutationTransaction` to classify and govern all text mutations:

| Source | Undo Policy | Selection Policy |
|--------|------------|-----------------|
| `userTyping` | Coalesce by pause | Preserve caret |
| `listContinuation` | Group with trigger keystroke | Place after prefix |
| `aiInsert` | Single undo group | Select inserted range |
| `syncMerge` | Non-undoable | Preserve if possible |
| `pasteOrDrop` | Single undo group | Select pasted range |

### 1.3 Syntax Visibility Modes

- **Full** — All markdown syntax visible.
- **Gentle fade** — Syntax characters reduced opacity.
- **Hidden until caret** — Syntax reveals on caret proximity.

### 1.4 AST Feature Completeness

- Interactive markdown tables with Tab/Shift-Tab cell navigation.
- Nested task list toggles.
- LaTeX spans with inline/block token distinction.
- Deterministic undo bundles per semantic action.

### 1.5 Writing Tools Integration (iOS 18.1+)

- Enable system Writing Tools on the editor text view.
- Ensure `textContentType` and `writingToolsBehavior` are configured correctly.
- Test: rewrite, proofread, and summary flows don't corrupt document state.

### Phase 1 Test Matrix — FULL APP COVERAGE

**Goal**: By the end of Phase 1, every existing module has at least baseline test coverage. New editor work gets deep coverage.

#### A. Editor (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `EditorMutationTransactionTests` | Every mutation source, undo policy, selection policy | Unit |
| `IncrementalASTPatchingTests` | Range-diff calculator, paragraph-scoped re-parse, no full-doc mutation | Unit |
| `SyntaxVisibilityModeTests` | Full / Gentle fade / Hidden-until-caret rendering | Unit + Snapshot |
| `TableNavigationTests` | Tab/Shift-Tab cell navigation, column alignment, kerning | Integration |
| `TaskListToggleTests` | Nested checkbox toggling, undo grouping | Integration |
| `LaTeXSpanTests` | Inline/block token distinction, undo | Unit |
| `IMEProtectionTests` | IME composition safety during async highlight | Integration |
| `CursorStabilityTests` | Cursor position preserved across highlight passes | UI Snapshot (iPhone/iPad/Mac) |
| `WritingToolsIntegrationTests` | Rewrite/proofread/summary flows, document integrity | Integration |
| `EditorPerformanceTests` | Keystroke-to-frame P95, syntax pass P95, 20k-char stress | Performance |
| `InlineImageRenderingTests` | U+FFFC attachment, TextKit 2 bounds, isApplyingHighlights guard | Integration |
| `LiveTableRenderingTests` | Mono font kerning, divider drawing, drawBackground correctness | Integration + Snapshot |
| `DragDropEditorTests` | File drop interception, asset import, markdown insertion | Integration |

#### B. Sidebar & Navigation (Baseline — existing)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `SidebarSelectionTests` | Selection binding, stable across tree refresh | Integration |
| `SidebarDragDropTests` | Real drag-drop operations, not decorative | Integration |
| `SidebarKeyboardTests` | Arrow keys, Enter, Delete, macOS keyboard nav | Integration |
| `SidebarVoiceOverTests` | Labels, custom actions, focus order | Accessibility |
| `NavigationStateTests` | 3-pane coherence: sidebar + list + editor stay in sync | Integration |
| `StateRestorationTests` | Relaunch restores pane state, selected note, scroll position | Integration |

#### C. Data Layer (Baseline — existing)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `VaultProviderTests` | Open, create, list, delete notes; iCloud timeout handling | Unit |
| `FileWatcherTests` | File change detection, debounce, notification | Unit |
| `FrontmatterParserTests` | YAML parse, round-trip, edge cases | Unit |
| `MarkdownParserTests` | AST correctness for all supported syntax | Unit |
| `SearchIndexTests` | Full-text search, tag extraction, incremental update | Unit |
| `WikiLinkExtractorTests` | `[[link]]` extraction, aliased links | Unit |
| `GraphLinkResolutionTests` | Backlink resolution, rename/move/delete stability | Integration |

#### D. Presentation Layer (Baseline — currently untested)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `DashboardViewTests` | Writing streak, pinned notes, recent notes rendering | Unit + Snapshot |
| `TagBrowserTests` | Tag list, note count, tap-to-filter | Unit |
| `InspectorTests` | Tag editor, metadata display, add/remove tags | Unit |
| `SettingsViewTests` | All preference panels render, values persist | Unit |
| `AppearanceManagerTests` | Font, theme, line spacing, pure dark mode | Unit |
| `DesignSystemTests` | Material tokens, typography scale, color contrast | Snapshot |

#### E. Infrastructure (Baseline — currently untested)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `CircuitBreakerTests` | Open/close state, failure threshold, reset | Unit |
| `LoggingTests` | Log levels, output format, no crash on nil | Unit |
| `RecoveryTests` | Recovery strategies, fallback chains | Unit |
| `SentinelTests` | Health checks, watchdog timer | Unit |

#### F. Self-Healing Matrix (Phase 1)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| Build concurrency | Swift 6 strict warnings/errors | Trace actor isolation; add `@MainActor`, `Sendable`, actor wrappers | Zero concurrency diagnostics |
| Runtime frame budget | `XCTMetric` > 16ms main thread | Profile hot path; move off main actor; batch UI updates | P95 < 16ms |
| Editor cursor jump | `CursorStabilityTests` snapshot diff | Trace highlight pass; check selection preservation | Snapshots match |
| Full-doc mutation | `IncrementalASTPatchingTests` assertion | Find call site; replace with range-diff | Zero full-doc mutations |
| IME corruption | `IMEProtectionTests` failure | Check async highlight overlap; add/fix guard | IME tests green |
| Undo regression | `EditorMutationTransactionTests` | Verify undo grouping policy per source | All transaction tests green |

#### Phase 1 CI Script

```bash
#!/bin/bash
# scripts/ci_phase1.sh — Headless Phase 1 validation
set -euo pipefail

echo "=== Phase 1: Editor Core Hardening ==="

# 1. Build all platforms
xcodebuild build -scheme Quartz -destination 'platform=macOS' | xcpretty
xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro' | xcpretty
xcodebuild build -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' | xcpretty

# 2. Run full test suite (not just Phase 1 — ALL tests)
swift test --package-path QuartzKit --parallel 2>&1 | tee /tmp/quartz_test_output.txt

# 3. Run app-level tests on all platforms
xcodebuild test -scheme Quartz -destination 'platform=macOS' | xcpretty
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro' | xcpretty
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' | xcpretty

# 4. Performance gate
swift test --package-path QuartzKit --filter "Performance" 2>&1 | tee /tmp/quartz_perf.txt

# 5. Emit machine-readable report
python3 scripts/parse_test_results.py /tmp/quartz_test_output.txt > reports/phase1_report.json

echo "=== Phase 1 Complete ==="
```

### Done When

- Zero full-document mutations during standard editing.
- All editor mutation origins covered by transaction model.
- Writing Tools flows preserve document integrity.
- P95 frame budget < 16ms main thread.
- **ALL test suites in sections A–F pass on all platforms.**
- **Self-healing matrix can identify and classify every editor failure autonomously.**

---

## Phase 2 — Persistence & Sync Reliability

**Objective**: Vault restoration is deterministic. Concurrent offline edits never lose data.

### 2.1 Vault Restoration

- Centralize security-scoped URL acquisition and stale bookmark repair.
- Use `@SceneStorage` for route + viewport restoration tokens.
- Startup handshake states: `vaultResolved` -> `indexWarm` -> `editorMounted` -> `restorationApplied`.
- Eliminate heuristic delays in restoration flow.

### 2.2 Sync Conflict Resolution

Start with a pragmatic approach, not full CRDT:

- **Optimistic last-write-wins** with content-hash comparison.
- **Conflict branching**: When edits diverge, create `Note (conflict YYYY-MM-DD).md` alongside original.
- **Conflict UI**: Banner in editor showing "This note has a conflict version" with diff viewer and merge/pick actions.
- **Revision history**: Append-only local revisions with "restore as new note" and "overwrite current" options.

### 2.3 SwiftData Index as Cache

- Graph links, search shards, embeddings metadata, revision pointers stored in SwiftData.
- Full rebuild command: reconstruct index from filesystem without data loss.
- Identity: file bookmark + canonical relative path + content hash lineage.

### Phase 2 Test Matrix — FULL APP COVERAGE

**Goal**: Everything from Phase 1 still passes. Sync and persistence get deep coverage. Remaining untested modules get baselines.

#### A. Persistence & Sync (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `VaultRestorationTests` | Deterministic handshake: vaultResolved → indexWarm → editorMounted → restorationApplied | Integration |
| `SecurityScopedURLTests` | Bookmark acquisition, stale repair, permission re-grant | Unit |
| `SceneStorageTests` | Route + viewport token persist/restore across relaunch | Integration |
| `ConflictDetectionTests` | Content-hash compare, divergence detection | Unit |
| `ConflictBranchingTests` | Conflict file creation, naming, metadata | Integration |
| `ConflictUITests` | Banner display, diff viewer, merge/pick actions | UI |
| `RevisionHistoryTests` | Append-only revisions, restore-as-new, overwrite-current | Integration |
| `SyncPropertyTests` | 10,000 randomized concurrent edit streams — zero byte loss | Property |
| `iCloudTimeoutTests` | POSIX error 60 handling, 5-second timeout, graceful fallback | Integration |
| `SwiftDataIndexTests` | Graph links, search shards, rebuild from filesystem | Integration |
| `IndexRebuildTests` | Full reconstruction produces identical index | Integration |

#### B. Editor Regression (Full — from Phase 1, must still pass)

All Phase 1 editor tests run unchanged. Any failure triggers self-healing.

#### C. Presentation Layer (Expand coverage)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `ConflictBannerViewTests` | Conflict UI rendering, actions, accessibility | Unit + Snapshot |
| `RevisionHistoryViewTests` | Diff viewer, restore actions, VoiceOver | Unit + Snapshot |
| `OnboardingViewTests` | Welcome screen, vault picker flow | Unit + Snapshot |
| `ChatViewTests` | VaultChatView bubble rendering, citation cards | Unit + Snapshot |
| `CommandPaletteViewTests` | Render, filter, action dispatch | Unit |
| `GraphVisualizationTests` | Node rendering, link lines, zoom, interaction | Unit + Snapshot |
| `QuickNoteViewTests` | Quick capture flow, insertion | Unit |
| `ShareExtensionTests` | Share sheet receives content, creates note | Integration |
| `WidgetTests` | Widget timeline, rendering, deep link | Unit |

#### D. Self-Healing Matrix (Phase 2 — extends Phase 1)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| State desync | `NavigationStateTests` mismatch | Trace `@Observable` propagation; restore single source of truth | 3-pane coherence tests green |
| Vault amnesia | `VaultRestorationTests` timeout | Check handshake state machine; eliminate heuristic delays | Restoration deterministic |
| Sync data loss | `SyncPropertyTests` byte mismatch | Rewrite hash compare; add adversarial regression fixture | Zero-byte-loss invariant |
| Bookmark stale | `SecurityScopedURLTests` failure | Re-acquire permission; repair bookmark | Bookmark tests green |
| Index drift | `IndexRebuildTests` diff | Trace rebuild path; ensure idempotent | Rebuild = original |
| *All Phase 1 failures* | *Same triggers* | *Same actions* | *Same conditions* |

#### Phase 2 CI Script

```bash
#!/bin/bash
# scripts/ci_phase2.sh — Headless Phase 2 validation
set -euo pipefail

echo "=== Phase 2: Persistence & Sync ==="

# 1. ALL Phase 1 tests still pass (regression gate)
bash scripts/ci_phase1.sh

# 2. Sync property tests (extended run)
swift test --package-path QuartzKit --filter "SyncProperty|ConflictDetection|ConflictBranching|RevisionHistory" --parallel

# 3. Vault restoration integration
swift test --package-path QuartzKit --filter "VaultRestoration|SecurityScoped|SceneStorage|IndexRebuild"

# 4. Full presentation layer baseline
swift test --package-path QuartzKit --filter "View|UI|Snapshot"

# 5. Report
python3 scripts/parse_test_results.py /tmp/quartz_test_output.txt > reports/phase2_report.json

echo "=== Phase 2 Complete ==="
```

### Done When

- Vault restoration is deterministic with no timing heuristics.
- 10,000 randomized concurrent edit scenarios pass with zero data loss.
- Conflict UI is functional and accessible.
- **ALL Phase 1 tests still green (zero regressions).**
- **Every presentation view has at least a baseline render + snapshot test.**
- **Self-healing matrix covers persistence and sync failure classes.**

---

## Phase 3 — Cross-Platform UX & Accessibility

**Objective**: Quartz feels native on every Apple platform. Accessible to everyone.

### 3.1 Platform-Adaptive Navigation

| Platform | Pattern | Details |
|----------|---------|---------|
| **iOS** | Stack-based | 44pt touch targets, bottom actions, swipe gestures |
| **iPadOS** | NavigationSplitView | Persistent column widths, Stage Manager support, keyboard shortcuts |
| **macOS** | Sidebar + detail | Multi-window, menu bar commands, Command Palette (`Cmd+K`) |
| **visionOS** | Windowed | Spatial design basics, ornaments for actions |

### 3.2 Focus Mode

- `FocusSurfaceModifier`: hide nonessential panes, center text column, suppress badges.
- Matched geometry transitions with spring curves.
- Respect Reduce Motion: instant transitions when enabled.

### 3.3 Visual Design System

- Standardize materials via design tokens: `.ultraThinMaterial` primary glass, solid fallbacks for Reduce Transparency.
- Consistent typography scale across platforms.
- Content first, chrome second, effects last.

### 3.4 Accessibility (Non-Negotiable)

Every control and view must pass:

- **VoiceOver**: All elements labeled, logical focus order, custom actions on sidebar items.
- **Voice Control**: All actions speakable.
- **Full Keyboard Access**: Tab navigation, shortcuts, Command Palette.
- **Dynamic Type**: All text scales through AX5, layout adapts.
- **Reduce Motion**: Animations respect preference.
- **Reduce Transparency**: Materials adapt to solid backgrounds.
- **Increase Contrast**: Sufficient color contrast on all surfaces.

### 3.5 State Restoration

- Cross-scene restoration keeps pane state and selected note in sync.
- Granular `@Observable` stores to avoid broad invalidation cascades.

### Phase 3 Test Matrix — FULL APP COVERAGE (100% TARGET)

**Goal**: By the end of Phase 3, every module, every view, every flow, every platform has test coverage. The CI pipeline can headlessly verify the entire app.

#### A. Accessibility (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `VoiceOverEditorTests` | Editor labels, rotor actions, focus order, typing feedback | Accessibility |
| `VoiceOverSidebarTests` | File tree labels, custom actions (rename, delete, move) | Accessibility |
| `VoiceOverNavigationTests` | Full app traversal: sidebar → list → editor → inspector | Accessibility |
| `VoiceOverChatTests` | Chat bubbles, citations, send action | Accessibility |
| `VoiceOverDashboardTests` | Streak, pinned notes, recent notes | Accessibility |
| `VoiceOverSettingsTests` | Every preference control labeled, grouped | Accessibility |
| `DynamicTypeTests` | Every view at all 12 Dynamic Type sizes | Snapshot (per size) |
| `DynamicTypeEditorTests` | Editor text + toolbar + inspector scale correctly | Snapshot |
| `KeyboardNavigationTests` | Tab through all controls, Cmd+K, Escape, Enter | Integration |
| `ReduceMotionTests` | All animations disabled/replaced with crossfade | Integration |
| `ReduceTransparencyTests` | All materials fall back to solid backgrounds | Snapshot |
| `IncreaseContrastTests` | All text/icon pairs meet WCAG AA | Unit |
| `VoiceControlTests` | All buttons/actions speakable and invocable | Integration |

#### B. Platform-Specific (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `iPhoneCompactTests` | Stack navigation, 44pt targets, bottom actions, swipe | UI Snapshot |
| `iPadSplitViewTests` | NavigationSplitView columns, persistent widths | UI Snapshot |
| `iPadStageManagerTests` | Multi-window, resize, column collapse | Integration |
| `MacWindowTests` | Multi-window, menu bar commands, Command Palette | Integration |
| `MacKeyboardTests` | Full keyboard shortcut suite, Cmd+K, Cmd+S, etc. | Integration |
| `visionOSBasicTests` | Window placement, ornament rendering | UI Snapshot |
| `FocusModeTests` | Pane hide/show, centered column, reduced chrome | Integration + Snapshot |
| `FocusModeReduceMotionTests` | Instant transitions when Reduce Motion enabled | Integration |
| `MaterialTokenTests` | Correct material per context, platform adaptation | Snapshot |

#### C. End-to-End Flows (Deep — new work)

| Test Suite | What It Covers | Type |
|-----------|---------------|------|
| `E2E_CreateNoteFlow` | Tap new → type title → type body → auto-save → appears in sidebar | Integration |
| `E2E_EditExistingNote` | Select note → edit → undo → redo → save | Integration |
| `E2E_DeleteNoteFlow` | Select → delete → confirmation → removed from sidebar + filesystem | Integration |
| `E2E_SearchFlow` | Cmd+F → type query → results appear → select result → editor opens | Integration |
| `E2E_TagFlow` | Add tag in inspector → tag appears in browser → filter by tag | Integration |
| `E2E_WikiLinkFlow` | Type `[[` → autocomplete → select → navigate → backlink visible | Integration |
| `E2E_DragDropFlow` | Drag file into editor → asset imported → markdown inserted | Integration |
| `E2E_ConflictFlow` | Simulate conflict → banner appears → diff viewer → resolve | Integration |
| `E2E_VaultSwitchFlow` | Switch vault → sidebar updates → state restored | Integration |
| `E2E_AppearanceFlow` | Change font/theme/spacing → editor updates → persists across relaunch | Integration |
| `E2E_DashboardFlow` | Launch → dashboard → pinned notes → tap → editor opens | Integration |
| `E2E_ChatFlow` | Open chat → ask question → streaming response → citation tap → note opens | Integration |
| `E2E_FocusModeFlow` | Enter focus → chrome hidden → exit focus → chrome restored | Integration |
| `E2E_ExportFlow` | Select note → export → format selection → output correct | Integration |

#### D. Self-Healing Matrix (Phase 3 — COMPLETE)

| Failure Class | Trigger Signal | Autonomous Action | Stop Condition |
|---|---|---|---|
| Snapshot mismatch | Pixel-diff fail in snapshot suite | Parse diff; tune padding, frame, material layering; regenerate when intentional | Snapshots green all form factors |
| Accessibility regression | AX audit failure | Patch labels, traits, focus order, Dynamic Type constraints | AX suite fully green |
| Platform divergence | Platform-specific test failure | Trace `#if os()` branch; verify API availability; fix conditional | All platforms green |
| Material mismatch | `MaterialTokenTests` diff | Check Reduce Transparency path; verify token mapping | Token tests green |
| Keyboard gap | `KeyboardNavigationTests` unreachable control | Add `.focusable()`, `.keyboardShortcut()`, or tab stop | All controls keyboard-reachable |
| Motion violation | `ReduceMotionTests` animation detected | Wrap in `withAnimation` conditional or `.transaction` modifier | No animation when Reduce Motion on |
| Dynamic Type overflow | `DynamicTypeTests` layout break | Fix with `@ScaledMetric`, `.minimumScaleFactor`, or adaptive layout | All sizes render correctly |
| *All Phase 1 + 2 failures* | *Same triggers* | *Same actions* | *Same conditions* |

#### Phase 3 CI Script — THE COMPLETE GATE

```bash
#!/bin/bash
# scripts/ci_phase3.sh — Headless FULL APP validation
set -euo pipefail

echo "=== Phase 3: Complete App Validation ==="

# 1. ALL previous phase tests (regression gate)
bash scripts/ci_phase2.sh

# 2. Accessibility audit — every view
swift test --package-path QuartzKit --filter "VoiceOver|DynamicType|ReduceMotion|ReduceTransparency|IncreaseContrast|VoiceControl|Keyboard"

# 3. Platform-specific snapshots
xcodebuild test -scheme Quartz -destination 'platform=macOS' -only-testing "QuartzTests/PlatformTests"
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing "QuartzTests/PlatformTests"
xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing "QuartzTests/PlatformTests"

# 4. End-to-end flows
swift test --package-path QuartzKit --filter "E2E_"

# 5. Performance gate (all modules)
swift test --package-path QuartzKit --filter "Performance"

# 6. Full report — every module, every platform
python3 scripts/parse_test_results.py /tmp/quartz_test_output.txt > reports/phase3_report.json
python3 scripts/coverage_check.py reports/phase3_report.json --require-all-modules

echo "=== Phase 3 Complete: SHIP GATE ==="
```

### Done When

- Snapshot diff suite green across macOS/iPhone/iPad.
- Full VoiceOver navigation works on every screen.
- Dynamic Type renders correctly at all sizes.
- Focus mode works with Reduce Motion.
- **EVERY module in the app has test coverage.**
- **EVERY end-to-end user flow has an integration test.**
- **EVERY accessibility requirement has a test.**
- **Self-healing matrix covers ALL failure classes — CI can headlessly identify and classify any regression in the entire app.**
- **The CI script (`ci_phase3.sh`) is the ship gate: if it passes, v1.0 is releasable.**

---

## Quality Gates (All Phases)

A change cannot merge unless:

- [ ] Full test suite passes (not just changed modules — ALL modules).
- [ ] Accessibility audit passes for ALL views (not just touched views).
- [ ] Performance budget met (< 16ms main thread P95).
- [ ] Zero Swift 6 concurrency diagnostics.
- [ ] Cross-platform CI green:
  - `xcodebuild test -scheme Quartz -destination 'platform=macOS'`
  - `xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
  - `xcodebuild test -scheme Quartz -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'`
- [ ] Self-healing matrix reports zero unresolved failures.

---

## What v1.0 Does NOT Include

These are deferred to v2.0 (see `ROADMAP_V2.md`):

- Audio intelligence (transcription, diarization, voice capture)
- VisionKit document scanning / OCR
- CRDT-based merge (v1 uses optimistic last-write-wins + conflict branching)
- Knowledge graph supremacy features
- Interactive FTUE onboarding tutorial
- visionOS spatial workspaces
- watchOS / tvOS targets
- PencilKit handwriting recognition pipeline
- Monetization / Pro tier

---

## Success Criteria

Quartz v1.0 ships when:

1. A user can open a vault and trust their files won't be corrupted.
2. Writing and editing has zero flicker, zero cursor jumps, and reliable undo.
3. The app feels native on iPhone, iPad, and Mac.
4. A user can navigate entirely with VoiceOver, keyboard, or voice.
5. System Writing Tools work without corrupting documents.
6. Offline editing syncs without data loss.
7. **`scripts/ci_phase3.sh` passes with zero failures on all platforms.**
8. **The self-healing matrix reports zero unresolved issues.**

That's the bar. Everything else is v2.
