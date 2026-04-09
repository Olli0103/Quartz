# EMERGENCY AUDIT REPORT: Phase 1 & Phase 2 Retroactive Gatekeeper

**Date**: 2026-04-03
**Auditor**: Claude (adversarial self-audit)
**Scope**: All Phase 1 (Editor Core) and Phase 2 (Persistence & Sync) code against ROADMAP_V1.md and CODEX_BLUEPRINT.md mandates
**Method**: Direct source code inspection of every relevant .swift file

---

## CHECK 1: TextKit 2 Implementation (Phase 1)

### What ROADMAP_V1.md Requires
- Incremental AST patching (paragraph-scoped re-parse, no full-document mutations)
- Keystroke-to-frame P95 < 8ms
- Syntax pass P95 < 12ms for 20k-char notes

### What Actually Exists

**VERDICT: TextKit 2 IS wired, but incremental patching is DEAD CODE.**

#### The Good

| Component | File | Status |
|-----------|------|--------|
| `NSTextContentStorage` subclass | `MarkdownTextContentManager.swift:18` | Real |
| `NSTextLayoutManager` wired | `MarkdownTextView.swift:75-80` | Real |
| Session-based architecture (no `@Binding var text`) | `MarkdownEditorRepresentable.swift:18` | Real |
| AST parsing via swift-markdown | `MarkdownASTHighlighter.swift:345` (`Document(parsing:)`) | Real |
| List continuation (surgical edits) | `MarkdownListContinuation.swift:48-130` | Real |
| IME composition guard | `EditorSession.swift:913-919` | Real |
| Table navigation (Tab/Shift-Tab) | `MarkdownTableNavigation.swift` | Real |
| Syntax visibility modes (Full/Fade/Hidden) | `EditorSession.swift:1700-1714` | Real |

#### The Bad

| Shortcut | Evidence | Impact |
|----------|----------|--------|
| **Incremental AST parsing is fully coded but NEVER ACTIVATED** | `MarkdownASTHighlighter.swift:236-341` implements `parseIncremental()` with dirty-region expansion, code-fence boundary detection, and span offset-patching. But `MutationTransaction.prefersIncrementalHighlight` is never set to `true` — all paths call `parseDebounced(full text)` | Every keystroke triggers a full AST re-parse. On 20k-char documents this likely exceeds the 12ms P95 budget. The gold-plated incremental engine is dead code. |
| **`MarkdownTextContentManager` is a pass-through stub** | Line 53-57: `performEditingTransaction` just wraps super with zero custom logic. No element generation, no paragraph-level invalidation. | The TextKit 2 content storage adds no value over the default `NSTextContentStorage`. It exists to satisfy the "TextKit 2" checkbox but provides no incremental layout benefit. |
| **Legacy `MarkdownTextViewRepresentable` still exists** | `MarkdownTextView.swift:17` uses `@Binding var text` and destructively writes `uiView.text = text` on every SwiftUI update (line 136). Never calls `parseIncremental`. | If any code path instantiates this instead of `MarkdownEditorRepresentable`, users get the exact cursor-jitter anti-pattern the architecture was designed to prevent. Dead code that should be deleted or gated. |

#### Missing from Phase 1 Requirements

| Requirement | Status |
|-------------|--------|
| Incremental AST range-diff patching (active) | **MISSING** — code exists but disabled |
| P95 keystroke < 8ms measurement | **MISSING** — no performance measurement infrastructure |
| P95 syntax pass < 12ms measurement | **MISSING** — `EditorPerformanceTests` measures wall-clock on ~18KB but doesn't enforce the 12ms budget |
| Writing Tools integration tests | **MISSING** — `OnDeviceWritingToolsService` exists but `WritingToolsIntegrationTests` is absent from the test directory |
| UI Snapshot tests (CursorStability) | **MISSING** — can't run from `swift test`, acknowledged in plan |

---

## CHECK 2: Sync & Persistence (Phase 2)

### What ROADMAP_V1.md Requires
- Deterministic vault restoration handshake
- Security-Scoped Bookmarks
- Conflict branching with content-hash comparison
- 10,000 concurrent edit scenarios with zero byte loss
- SwiftData index as cache

### What Actually Exists

**VERDICT: SOLID IMPLEMENTATION. Two significant gaps.**

#### The Good

| Component | File | Status |
|-----------|------|--------|
| Security-Scoped Bookmarks (create + restore + stale refresh) | `VaultAccessManager.swift:52-128` | Real |
| `@SceneStorage` for note path, cursor, scroll | `ContentView.swift:36-39` | Real |
| NSFileCoordinator on all vault I/O | `CoordinatedFileWriter.swift` (all methods) | Real |
| NSFilePresenter with full callback suite | `NoteFilePresenter.swift:116-200` | Real |
| iCloud eviction detection + download polling | `FileSystemVaultProvider.swift:175-241` | Real |
| Conflict detection via `NSFileVersion` | `CloudSyncService.swift:170-172` | Real |
| Conflict branching ("Keep Both" → sibling note) | `CloudSyncService.swift:257-295` | Real |
| Revision history (append-only snapshots, AES-256-GCM) | `VersionHistoryService.swift` | Real |
| Vault restoration handshake (readiness state) | `EditorSession.swift:519-549` (F8 fix) | Real |
| Content-hash echo suppression (SHA-256) | `EditorSession.swift` (just implemented in iCloud audit) | Real |

#### The Bad

| Shortcut | Evidence | Impact |
|----------|----------|--------|
| **No UIDocument / NSDocument** | Zero subclasses anywhere in the codebase. Custom `FileSystemVaultProvider` + `CoordinatedFileWriter` used instead. | Deliberate architectural choice (documented in ICLOUD_AUDIT_REPORT.md). The custom implementation is adequate but doesn't get the free iCloud conflict resolution UI that `UIDocument` provides. Acceptable if tested. |
| **SwiftData index NOT implemented** | ROADMAP requires "SwiftData index as cache (graph links, search shards, embeddings metadata)." The actual implementation uses in-memory `SearchIndex` with file-based persistence (`SearchIndexPersistenceService`), not SwiftData. | The search index works but doesn't benefit from SwiftData's migration, Spotlight integration, or CloudKit sync. This is a deviation from the blueprint. |
| **10,000 concurrent edit property test is NOT what it claims** | `SyncPropertyTests` exists but does NOT run 10,000 actual concurrent file writes. It runs randomized operations on mock vaults, not real iCloud coordination. | The "zero byte loss" guarantee is tested against mocks, not real file coordination. A real iCloud stress test requires `xcodebuild test` with device-level coordination. |
| **`@SceneStorage` does NOT persist sidebar source selection** | Only `selectedNotePath`, `cursorLocation`, `cursorLength`, `scrollOffset` are stored. The sidebar source (All Notes / Favorites / folder) is lost on relaunch. | User opens a note from Favorites, closes app, relaunches → sees note in "All Notes" context instead. Minor UX regression. |

#### Missing from Phase 2 Requirements

| Requirement | Status |
|-------------|--------|
| SwiftData index as cache | **MISSING** — uses file-based `SearchIndex` instead |
| 10,000 concurrent edit property test (real) | **WEAK** — mock-only, not real I/O |
| ConflictUITests (banner, diff viewer) | **MISSING** — requires UI test host |
| IndexRebuildTests (reconstruction idempotence) | **PARTIAL** — `SearchIndexPersistence` tests exist but don't test full rebuild |

---

## CHECK 3: Fake Test Detection

### Methodology
Audited all 120 test files (1,147 `@Test` annotations, 32,676 lines).

### VERDICT: 96% REAL, 4% TAUTOLOGICAL/TRIVIAL

#### Confirmed Fake Tests

| File | Test | Line | Issue |
|------|------|------|-------|
| `Phase7LiquidGlassHIGTests.swift` | `selectionFeedback()` | 36 | `#expect(true)` — no assertion on feedback behavior |
| `Phase7LiquidGlassHIGTests.swift` | `primaryActionFeedback()` | 44 | `#expect(true)` only |
| `Phase7LiquidGlassHIGTests.swift` | `successFeedback()` | 52 | `#expect(true)` only |
| `Phase7LiquidGlassHIGTests.swift` | `warningFeedback()` | 60 | `#expect(true)` only |
| `Phase7LiquidGlassHIGTests.swift` | `destructiveFeedback()` | 68 | `#expect(true)` only |
| `Phase7LiquidGlassHIGTests.swift` | `toggleFeedback()` | 76 | `#expect(true)` only |
| `Phase1OnboardingSecurityTests.swift` | (accessibility check) | 61 | `#expect(true, "OnboardingView correctly checks...")` |
| `Phase1OnboardingSecurityTests.swift` | (actor isolation) | 148 | `#expect(true, "BiometricAuthService correctly uses...")` |
| `Phase6SystemIntegrationTests.swift` | `textCapture()` | 178 | `#expect(sharedText == sharedText)` — tautological |

**Total confirmed fake: 9 tests (0.8%)**

#### Compile-Time Existence Tests (Technically Pass but Test Nothing Behavioral)

| File | Count | Pattern |
|------|-------|---------|
| `LiquidGlassHIGTests.swift` | ~12 | Animation constants assigned to `let _` |
| `Phase7LiquidGlassHIGTests.swift` | 6 | Feedback type existence checks |
| `Phase2FileSystemTests.swift` | 3 | Error enum case construction only |
| Various | ~24 | Type existence / initializer checks |

**Total compile-time-only: ~45 tests (3.9%)**

#### Misleading "Stress" Tests

| File | Claim | Reality |
|------|-------|---------|
| `IntelligenceEngineStressTests.swift` | "1000 file changes" | Posts 1000 notifications to mock, doesn't process 1000 real files |
| `Phase7PerformanceSecurityTests.swift` | "10,000 concurrent edits" | Single-threaded loop, no actual concurrency |
| `SyncPropertyTests` | "Zero byte loss" | Mock vault only, no real file I/O coordination |

#### Test Quality Summary

| Category | Count | % |
|----------|-------|---|
| Real behavioral tests | ~1,093 | 95.3% |
| Compile-time existence only | ~45 | 3.9% |
| Confirmed `#expect(true)` fakes | 9 | 0.8% |
| **Total @Test** | **1,147** | **100%** |

---

## CHECK 4: State Desync & @Observable Audit

### VERDICT: 8 ANTI-PATTERNS FOUND

#### Critical Issues

**1. Duplicated State: indexingProgress & cloudSyncStatus**
- `ContentViewModel.swift:26-29` AND `SidebarViewModel.swift:67-69` both hold `cloudSyncStatus` and `indexingProgress`
- Manually synced at `ContentViewModel.swift:719,734,748,774,791`
- **Risk**: Silent desync if sync assignment is missed

**2. Selection State Fragmented Across 3 Layers**
- `WorkspaceStore.route` → `ContentView` bridge property → `SidebarView @Binding`
- Three-level binding chain violates Apple's recommended 1-2 levels
- `WorkspaceStore.selectedNoteURL` is a computed property with implicit setter creating dual mutation paths

**3. NotificationCenter Mixed with @Observable**
- `SidebarViewModel.swift:149-167` uses NotificationCenter for `.quartzFavoritesDidChange` and `.quartzNoteRenamed`
- Should be direct method calls from the parent ViewModel

**4. Massive View Bodies**
- `ContentView.swift`: logical body 150+ lines (body → bodyWithSheets → bodyWithTask)
- `SidebarView.swift`: body 175 lines
- `EditorContainerView.swift`: body 274 lines
- All exceed the 80-line red flag threshold

**5. FocusModeManager Independent of WorkspaceStore**
- `FocusModeManager` and `WorkspaceStore` both own layout state
- Manual coordination required between them
- **Risk**: Focus mode state inconsistency

**6. Sidebar Source Selection NOT Persisted**
- `@SceneStorage` stores note URL but NOT the sidebar source (All Notes / Favorites / folder)
- User loses context on relaunch

#### Minor Issues

**7. View/ViewModel Coupling**: SidebarView calls business logic directly in `handleDrop()` (line 425-453). EditorContainerView mutates EditorSession directly (line 349-360).

**8. Legacy MarkdownTextViewRepresentable**: Still exists with the destructive `@Binding` pattern. Should be deleted or clearly deprecated.

---

## DEVIATION MATRIX: Blueprint vs Reality

| ROADMAP Requirement | Status | Severity |
|---------------------|--------|----------|
| Incremental AST patching (active, not just coded) | DISABLED | **HIGH** |
| P95 keystroke < 8ms enforcement | NOT MEASURED | **HIGH** |
| P95 syntax pass < 12ms enforcement | NOT MEASURED | **HIGH** |
| SwiftData index as cache | NOT IMPLEMENTED (file-based) | **MEDIUM** |
| 10,000 concurrent edit property test (real I/O) | MOCK ONLY | **MEDIUM** |
| Writing Tools integration tests | MISSING | **MEDIUM** |
| ConflictUI tests (banner, diff viewer) | MISSING (requires UI host) | **LOW** |
| CursorStability UI snapshot tests | MISSING (requires xcodebuild) | **LOW** |
| Sidebar source `@SceneStorage` | MISSING | **LOW** |
| Delete legacy `MarkdownTextViewRepresentable` | NOT DONE | **LOW** |
| 9 tautological `#expect(true)` tests | PRESENT | **LOW** |
| Single source of truth for indexing/sync state | DUPLICATED | **MEDIUM** |

---

## PRIORITIZED FIX CHECKLIST

Must execute these before resuming Phase 3 feature work:

### P0 — Blocking (Correctness/Performance)

- [ ] **ACTIVATE incremental AST patching**: Set `MutationTransaction.prefersIncrementalHighlight = true` for `.userTyping` origin. Verify the `parseIncremental()` path works end-to-end. This is the single biggest performance gap — every keystroke does a full re-parse today.
- [ ] **Add P95 performance budget tests**: Create `EditorPerformanceBudgetTests` that measure syntax pass time on 20k-char documents and FAIL if > 12ms. Measure keystroke-to-highlight-apply and FAIL if > 8ms.
- [ ] **Fix `filePresenterShouldSave` deadlock** (already done in iCloud audit — verify commit is clean)

### P1 — High Priority (Architecture)

- [ ] **Consolidate duplicated state**: Remove `indexingProgress` and `cloudSyncStatus` from `SidebarViewModel`. Read from `ContentViewModel` via environment.
- [ ] **Persist sidebar source selection**: Add `@SceneStorage("quartz.sidebarSource")` to preserve All Notes / Favorites / folder context across relaunches.
- [ ] **Delete or deprecate `MarkdownTextViewRepresentable`**: The legacy editor wrapper with `@Binding var text` is a liability. If any code path can reach it, users get cursor jitter.
- [ ] **Replace tautological tests**: Fix the 9 `#expect(true)` tests in `Phase7LiquidGlassHIGTests.swift`, `Phase1OnboardingSecurityTests.swift`, and `Phase6SystemIntegrationTests.swift` with real assertions or delete them.

### P2 — Medium Priority (Test Coverage)

- [ ] **Make "10,000 concurrent edit" test use real file I/O**: Replace mock vault with temp directory + `CoordinatedFileWriter` for at least a subset (e.g., 100 real coordinated writes).
- [ ] **Add `WritingToolsIntegrationTests`**: Test the `OnDeviceWritingToolsService` → `EditorSession.applyExternalEdit` path.
- [ ] **Add `IndexRebuildTests`**: Test full index reconstruction from filesystem scan.
- [ ] **Flesh out `MarkdownTextContentManager`**: Either add real paragraph-level invalidation or document why it's a deliberate pass-through.

### P3 — Low Priority (Polish)

- [ ] **Break up massive View bodies**: Extract ContentView (150+ lines), SidebarView (175 lines), EditorContainerView (274 lines) into composed sub-views.
- [ ] **Replace NotificationCenter in SidebarViewModel**: Use direct method calls from ContentViewModel for favorites/rename events.
- [ ] **Unify FocusModeManager into WorkspaceStore**: Single source of truth for layout state.
- [ ] **SwiftData migration**: Replace file-based `SearchIndex` with SwiftData (non-trivial, defer to dedicated sprint).

---

## CONCLUSION

The codebase is **fundamentally sound** — the core architecture (session-based editor, actor-isolated vault provider, NSFileCoordinator/NSFilePresenter, security-scoped bookmarks) is correctly implemented and production-quality.

The critical gap is that the **most important performance optimization (incremental AST patching) is fully coded but never activated**. This means Quartz does full-document re-parses on every keystroke, which will fail the P95 < 12ms budget on large documents.

The test suite is **95.3% legitimate** with 9 confirmed fakes and ~45 compile-time-only tests. The "10,000 concurrent edit" claim is misleading (mock-only).

State management has real issues (duplicated state, fragmented selection, massive view bodies) but nothing that causes data loss — just unnecessary complexity and minor UX regressions.

**Recommended action**: Fix P0 items (activate incremental parsing, add performance budget tests), then P1 items, before resuming any new feature work.
