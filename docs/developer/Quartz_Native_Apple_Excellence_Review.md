# Quartz Native Apple Excellence Review

## A. Executive verdict

Quartz is **promising but immature**. The ambition is exactly right — native Apple note-taking, markdown-first, filesystem-owned, AI-capable — but the current implementation is still below the trust, calmness, and interaction correctness bar required for a premium daily-use notes app. The repository already contains serious product bets such as file-backed vaults, wiki-links, backlinks, Spotlight, semantic search, multi-window editing, and on-device writing tools, but the core editing and organization flows still look architecturally fragile in ways that directly explain the reported drag-and-drop failures, markdown flicker, and broken bullet-list behavior.

The biggest problem is not lack of features. It is that Quartz is trying to look award-caliber before the writing surface and organizational primitives feel boringly correct.

## B. What Quartz is trying to be

Quartz is clearly trying to be a **native Apple markdown notebook / second-brain app** that combines:

- Apple Notes approachability.
- Obsidian-style file ownership, wiki-links, backlinks, tags, and graph navigation.
- Premium productivity-app aesthetics.
- Optional AI for chat, summarization, semantic search, and writing assistance.
- Native OS integrations such as Spotlight, Handoff, widgets, share extension, PencilKit, and quick note capture.

The product identity inferred from the repo is: **“plain Markdown vaults on disk, but presented through a polished Apple-native shell with optional intelligence.”** That is a strong concept. The problem is that the experience currently feels broader than it is deep.

## C. Top strengths

1. **Strong core product direction:** plain markdown files, vault ownership, and Apple-first positioning are credible differentiators.
2. **Solid platform ambition:** NavigationSplitView, multi-window support on macOS, Spotlight, Handoff, widgets, and share/Quick Look integrations show the right instinct.
3. **Good long-term storage instinct:** filesystem-as-source-of-truth is aligned with markdown portability and avoids premature database lock-in.
4. **Meaningful AI scaffolding already exists:** note chat, vault chat with embeddings, and on-device writing tools are more product-relevant than gimmicky image generation.
5. **There is real test intent:** the repo contains a surprisingly broad set of test targets spanning search, markdown, editor hardening, accessibility, StoreKit, and performance.

## D. Top weaknesses

1. **Editor correctness is not yet trustworthy.** The implementation lacks native editing behaviors users expect, especially list continuation, structured list editing, and stable text/selection/rendering interplay.
2. **The preview/edit split is likely causing visual instability.** Quartz currently swaps entire view trees between a custom TextKit editor and a Textual preview instead of using a calmer incremental rendering model.
3. **Sidebar drag-and-drop feels over-engineered but under-specified.** The UI exposes insertion-state affordances it does not actually honor, and move execution is fire-and-forget rather than transactionally verified.
4. **The app is feature-wide before it is interaction-deep.** Dashboard, graph, AI, audio, OCR, and “Liquid Glass” all exist while the primary write/organize loop is still fragile.
5. **The design language risks cosmetic polish over native confidence.** There are multiple custom shells and material-heavy treatments, but correctness, hierarchy, and trust are not yet at Bear/Things/Apple Notes level.

## E. Native Apple technology audit

| Area | Current approach | Verdict | Risk | Recommendation |
|---|---|---|---|---|
| App shell | SwiftUI app with environment-driven app state and scene-specific windows | Good direction | Medium | Keep SwiftUI shell, but narrow global mutable state and tighten scene ownership. |
| Navigation | NavigationSplitView with adaptive layout and macOS secondary note window | Good foundation | Medium | Keep; validate compact-column behavior, restoration, and multiwindow drag/open flows. |
| State management | `@Observable` objects plus Environment injection | Mostly appropriate | Medium | Reduce duplicated state between `ContentView`, `ContentViewModel`, sidebar VM, and editor VM. |
| Storage model | File-based vault provider with coordinated reads/writes | Strong product fit | Medium | Keep file-backed model; add stronger integrity and move/rename transaction coverage. |
| Search | In-memory search actor + Spotlight indexer | Good baseline | Medium | Keep; add incremental updates and ranking validation for large vaults. |
| Sync assumptions | iCloud-aware file coordination, watcher, conflict UI | Promising | High | Harden conflict + move semantics; verify cross-device/file-provider edge cases before claiming reliability. |
| Editor text system | Custom TextKit 2 wrapper over `UITextView` / `NSTextView` with AST highlighting | Right general direction, incomplete execution | Critical | Keep native text system, but add proper edit interception, incremental styling, selection/IME coverage, and editor-specific tests. |
| Markdown preview | Textual `StructuredText` inside a `ScrollView` | Attractive but costly | High | Constrain preview usage; stop treating full preview as the core editing surface. |
| Drag and drop | SwiftUI `Transferable` + `.dropDestination` on sidebar rows | Native API choice is correct | High | Redesign drop semantics, validate target resolution, and support actual before/after behavior or remove those affordances. |
| Platform bridging | UIKit/AppKit bridges exist where needed | Sensible | Medium | Keep bridging, but use deeper native APIs for editor-specific behavior rather than mostly generic text-view delegation. |
| Accessibility | Some custom accessibility actions and Dynamic Type support | Partial | High | Audit every custom control, graph, dashboard card, and editor affordance with VoiceOver + keyboard-first testing. |
| Concurrency | Actors used in data/search/AI areas | Good intent | Medium | Review detached tasks, cancellation, and fire-and-forget UI tasks around move/index/save flows. |
| AI integration | Provider registry, note/vault chat, embeddings, on-device writing tools | Relevant, not frivolous | Medium | Refocus on note workflow utility and trust; avoid making AI primary UI chrome too early. |
| Dashboard | Custom “morning command center” cards | Weak fit today | Medium | Prove usefulness with daily-note / tasks / recent-work evidence or reduce scope. |
| Knowledge graph | macOS graph with wiki + semantic links | Potentially differentiating, currently secondary | Medium | Keep as an advanced view only if it earns its place through task completion, not spectacle. |
| Design system | Custom Liquid Glass/material styling | Mixed | Medium | Tone it down until core interactions are flawless; native restraint will age better. |
| **Textual** | Read-only markdown preview renderer | **Useful but strategically mispositioned** | **High** | Keep only as a constrained preview/export surface unless it can be proven not to harm editor fidelity, performance, and accessibility. |

## F. Pillar-by-pillar scorecard

| Pillar | Score | Why | Evidence | What would raise the score |
|---|---:|---|---|---|
| Product clarity | 8/10 | Clear Apple-native markdown vault ambition with real differentiation. | README product framing and wide feature set align around files + native UX + intelligence. | Narrow the story to writing quality and trustworthy organization first. |
| Design quality | 7/10 | Ambitious visual layer, but polish exceeds correctness. | Material-heavy dashboard/editor chrome and custom shell treatments. | Simplify hierarchy, reduce ornamental surfaces, increase restraint. |
| Apple platform fidelity | 8/10 | Good framework choices, uneven behavioral fidelity. | NavigationSplitView, Spotlight, Handoff, UIKit/AppKit bridges. | Match native text, sidebar, drag/drop, search, and windowing expectations more closely. |
| Markdown editor quality | 8/15 | Native text system choice is good, but editor behavior is still incomplete. | TextKit 2 wrapper exists; no Enter/list continuation logic; preview swapping is abrupt. | Add list intelligence, incremental rendering, selection stability, and correctness tests. |
| Notes organization | 7/8 | Rich organization model is present. | folders, tags, favorites, backlinks, recent notes, search, graph. | Fix drag/drop, validate graph/dashboard usefulness, improve saved search/smart folder story. |
| Usability | 6/8 | Powerful but still high-friction in common flows. | Multiple sheets/alerts, toolbar density, move flows, preview mode switching. | Reduce mode switching, simplify moving/creating notes, tighten common task flow. |
| Accessibility | 5/8 | Intent exists, but custom surfaces create significant risk. | Sidebar accessibility actions + Dynamic Type hooks, but graph/dashboard/editor are custom-heavy. | Add editor, graph, dashboard, and drag/drop accessibility audits and tests. |
| Performance / stability | 6/8 | Some performance intent, still fragile under scale. | Debounced parsing, actors, but broad styling invalidation and full surface swaps. | Incremental highlighting, larger-note benchmarks, fewer full-tree refreshes. |
| AI strategy | 5/5 | AI direction is product-relevant. | note chat, vault chat, embeddings, on-device writing tools. | Tie AI to note workflow trust and make provider behavior more transparent. |
| Technical architecture | 7/8 | Clean-ish layering exists, but boundaries blur in presentation orchestration. | QuartzKit package split across Data/Domain/Presentation with app shell wrapper. | Reduce view-model duplication and formalize editor/storage contracts. |
| Maintainability | 6/6 | Reasonable naming and structure, but breadth is outrunning depth. | Large feature surface, repeated test suites, many cross-cutting UI states. | Consolidate duplicate tests, shrink view size, isolate risky subsystems. |
| Differentiation | 6/6 | Files + native Apple polish + relevant AI could become special. | markdown vaults, graph, backlinks, Apple integrations, on-device writing tools. | Make the experience emotionally calmer and more trustworthy than current competitors. |

**Total: 79/100.** That is a strong ambition score, not a market-ready excellence score.

## G. Critical issue register

1. **Title:** Sidebar drag-and-drop advertises insertion semantics it does not implement  
   **Severity:** Critical  
   **Category:** Organization / interaction correctness  
   **Evidence:** `DropPosition` supports `.before/.inside/.after`, UI draws insertion indicators, but drop handlers always route to folder-parent moves and never reorder siblings.  
   **User impact:** Users cannot trust where notes/folders will land; moving information architecture feels broken.  
   **Likely root cause:** Visual model and data model are mismatched; filesystem move logic only knows destination folders, not ordered placement semantics.  
   **Recommended fix:** Remove before/after affordances immediately or implement explicit sibling ordering/target-folder resolution rules.  
   **Suggested files / modules / areas to inspect:** `Presentation/Sidebar/SidebarView.swift`, `Domain/UseCases/FolderManagementUseCase.swift`, `Data/FileSystem/FileSystemVaultProvider.swift`.  
   **Effort:** M  
   **Confidence:** High

2. **Title:** Sidebar moves are fire-and-forget and success feedback is optimistic  
   **Severity:** Critical  
   **Category:** Drag and drop / data integrity  
   **Evidence:** `handleDrop` returns `true` before async moves complete and always increments success count regardless of provider errors.  
   **User impact:** UI can report success when items were not moved, creating trust failures.  
   **Likely root cause:** SwiftUI drop handler is being used as a trigger rather than a transactional operation with validation and error surfacing.  
   **Recommended fix:** Perform validated move operations via a single async coordinator, return success only for verified moves, and surface partial-failure states.  
   **Suggested files / modules / areas to inspect:** `SidebarView.handleDrop`, `SidebarViewModel.move`, `FolderManagementUseCase.move`.  
   **Effort:** M  
   **Confidence:** High

3. **Title:** Markdown preview/edit architecture likely causes flicker  
   **Severity:** Critical  
   **Category:** Editor rendering  
   **Evidence:** editor body fully swaps between `MarkdownPreviewView` and `MarkdownTextViewRepresentable`, both animated on `isPreviewMode`; preview uses separate `ScrollView`/Textual stack.  
   **User impact:** visual discontinuity, scroll reset risk, perceived instability, writing interruption.  
   **Likely root cause:** whole-surface mode replacement, not incremental rendering; separate text/render trees with different layout models.  
   **Recommended fix:** stop animating full editor swaps, preserve scroll/selection explicitly, and consider inline or side-by-side preview rather than mode replacement for primary writing.  
   **Suggested files / modules / areas to inspect:** `NoteEditorView.swift`, `MarkdownPreviewView.swift`, `MarkdownTextView.swift`.  
   **Effort:** M-L  
   **Confidence:** Medium-high

4. **Title:** Syntax highlighting re-applies broad attributes and can churn layout  
   **Severity:** High  
   **Category:** Performance / flicker  
   **Evidence:** AST highlighting debounces parsing, but `applySpans` resets attributes across large `updateRange` regions, often the whole storage.  
   **User impact:** typing jank, flicker-like restyling, selection/IME instability on larger documents.  
   **Likely root cause:** no incremental paragraph-level invalidation despite content manager helpers existing for paragraph bounding.  
   **Recommended fix:** drive highlighting from edited paragraphs only, batch style diffs, and avoid global `setAttributes` in hot paths.  
   **Suggested files / modules / areas to inspect:** `MarkdownTextView.swift`, `MarkdownTextContentManager.swift`, `MarkdownASTHighlighter.swift`.  
   **Effort:** L  
   **Confidence:** High

5. **Title:** Bullet list behavior is structurally incomplete  
   **Severity:** Critical  
   **Category:** Editor correctness  
   **Evidence:** formatting toolbar only inserts `- ` prefixes; editor delegates do not intercept newline insertion or continue list structures; there is no dedicated list editing engine.  
   **User impact:** pressing Return in lists/checklists/numbered lists will not behave like a premium notes app.  
   **Likely root cause:** markdown formatting is treated as string transformation, not editing behavior.  
   **Recommended fix:** implement newline interception in `UITextView`/`NSTextView` delegates for bullets, numbered lists, checklists, nested lists, and empty-item exit behavior.  
   **Suggested files / modules / areas to inspect:** `FormattingToolbar.swift`, `MarkdownTextView.swift`, `NoteEditorView.swift`.  
   **Effort:** M  
   **Confidence:** High

6. **Title:** Editor state restoration is incomplete  
   **Severity:** High  
   **Category:** Usability / resilience  
   **Evidence:** `ContentView` stores cursor and scroll restoration state, but the editor wrapper shown does not restore scroll position or selection from scene storage.  
   **User impact:** reopening a note may not return users to where they were writing.  
   **Likely root cause:** app-shell persistence was added before editor bridge restoration hooks were completed.  
   **Recommended fix:** plumb selection/scroll restoration into both UITextView and NSTextView representables.  
   **Suggested files / modules / areas to inspect:** `Quartz/ContentView.swift`, `MarkdownTextView.swift`, `NoteEditorViewModel.swift`.  
   **Effort:** M  
   **Confidence:** Medium

7. **Title:** Dashboard is visually strong but strategically unproven  
   **Severity:** Medium  
   **Category:** Product focus  
   **Evidence:** custom dashboard surfaces AI briefing, action items, recent notes, graph exploration, and capture shortcuts before the core editor is flawless.  
   **User impact:** app feels busy rather than calm; opens on a command-center concept many users may not need.  
   **Likely root cause:** over-indexing on differentiation before validating default work loops.  
   **Recommended fix:** test whether dashboard increases engagement; otherwise reduce it to a lightweight recent/tasks hub or make it optional.  
   **Suggested files / modules / areas to inspect:** `Presentation/Dashboard/DashboardView.swift`, `Quartz/ContentView.swift`.  
   **Effort:** M  
   **Confidence:** Medium

8. **Title:** Knowledge graph may be more decorative than actionable  
   **Severity:** Medium  
   **Category:** Product differentiation  
   **Evidence:** graph builds connections from wiki links and embeddings with capped node counts, but utility workflow is not obvious.  
   **User impact:** can impress without helping note retrieval or thinking flow.  
   **Likely root cause:** graph exists as a feature pillar rather than as a task-oriented tool.  
   **Recommended fix:** anchor graph to focused tasks: “show orphan notes,” “show related notes to current note,” “show recent cluster.”  
   **Suggested files / modules / areas to inspect:** `Presentation/Graph/KnowledgeGraphView.swift`, `Data/FileSystem/GraphCache.swift`.  
   **Effort:** M  
   **Confidence:** Medium

9. **Title:** AI surface area is ahead of product discipline  
   **Severity:** Medium  
   **Category:** Strategy / maintainability  
   **Evidence:** note chat, vault chat, writing tools, dashboard briefing, link suggestions, meeting minutes, semantic edges.  
   **User impact:** diluted focus, settings complexity, and maintenance burden.  
   **Likely root cause:** ambitious differentiation without enough sequencing.  
   **Recommended fix:** keep only workflow-enhancing AI in the default experience; hide the rest behind advanced settings or later phases.  
   **Suggested files / modules / areas to inspect:** `Domain/AI/*`, `Presentation/Chat/*`, `Presentation/Settings/AISettingsView.swift`.  
   **Effort:** M  
   **Confidence:** Medium

10. **Title:** Test suite breadth is good, but coverage misses live interaction regressions  
   **Severity:** Medium  
   **Category:** Quality process  
   **Evidence:** many unit/perf tests exist, but there are no convincing UI regression tests for drag/drop, list continuation, editor flicker, or selection stability.  
   **User impact:** the bugs users feel most are exactly the ones least protected.  
   **Likely root cause:** testing has concentrated on parsers/helpers rather than interactive text and navigation behavior.  
   **Recommended fix:** add editor and drag/drop UI automation plus targeted integration harnesses around text input.  
   **Suggested files / modules / areas to inspect:** `QuartzUITests/*`, `QuartzKit/Tests/QuartzKitTests/*`.  
   **Effort:** M  
   **Confidence:** High

## H. Apple HIG and native UX compliance review

### iOS
- Strong: native toolbars, writing tools hooks, image import, share/capture potential.
- Weak: floating/custom chrome and preview mode switching risk interrupting fast capture.
- Soft violations: too much persistent tooling around the editor; a premium iPhone notes app should bias toward immediate writing, light formatting, and predictable keyboard behavior.

### iPadOS
- Strong: split view and keyboard shortcuts are directionally correct.
- Weak: editor/list interactions must become pointer- and keyboard-first, not merely touch-compatible.
- Soft violations: dashboard + graph + sheets + toolbar density can fight Stage Manager and professional iPad workflows unless carefully pruned.

### macOS
- Strong: dedicated note windows, inspector support, toolbar formatting, Finder trash reveal, knowledge graph availability.
- Weak: sidebar DnD correctness and editor maturity will be judged harshly on Mac because users expect AppKit-grade precision.
- Soft violations: if drag/drop, multiwindow opening, focus, and menu/shortcut semantics are not perfect, the app will feel “SwiftUI-custom” rather than Mac-native.

### shared issues
- The app often chooses feature presence over interaction refinement.
- Several custom/material-heavy surfaces do not yet earn their complexity.
- Native patterns that should replace custom ones: calmer note list rows, more standard search presentation, less modal proliferation, deeper native text behavior.
- Custom UI that is justified: graph view, writing tools panel, advanced markdown metadata inspector — but only if accessibility and restraint are strong.

### Where Quartz would fail Apple-native design scrutiny even if it looks polished at first glance
1. The main writing loop is still too modeful.
2. Drag/drop semantics are visually richer than their actual behavior.
3. The app risks feeling “designed” rather than inevitable.
4. Material/chrome choices are ahead of content hierarchy.
5. Accessibility and editing correctness likely degrade where custom surfaces replace native defaults.

## I. Textual decision memo

- **What problem Textual is solving here:** high-quality read-only markdown rendering for preview, including math, tables, and structured rich presentation.
- **Whether it is helping or hurting:** both. It helps Quartz show attractive markdown output quickly. It hurts when the product treats that renderer as central to the editing experience rather than as a secondary surface.
- **Whether it is aligned with a premium Apple-native direction:** only partially. A premium Apple-native notes app must optimize for editing correctness first. A third-party preview renderer is acceptable; a third-party renderer shaping the editor architecture is not.
- **Whether to keep, constrain, wrap, phase out, or replace it:** **constrain and wrap now**.
- **Migration options if replacement is advised:**
  1. Keep Textual for optional read-only preview/export only.
  2. Build a native attributed preview using `AttributedString`/swift-markdown for lightweight inline rendering needs.
  3. If true WYSIWYM editing is desired later, build on TextKit 2 + markdown AST, not on Textual.
- **Risks of staying:** divergence between edit and preview, accessibility mismatches, scroll/selection context loss, performance inconsistencies.
- **Risks of replacing:** losing rich tables/math rendering short-term and spending too much time on a custom preview before editor basics are solid.
- **Final recommendation:** **keep Textual as a non-primary preview technology, stop letting it define editor behavior, and do not expand it deeper into the editing stack.**

## J. AI / Apple Intelligence / Foundation Models strategy memo

- **Current-state assessment:** Quartz has more AI groundwork than most note apps this early, and much of it is directionally smart.
- **What is missing:** prioritization, trust UX, cost/latency transparency, and stronger on-device-first defaults.
- **What should not be added:** gimmicky brainstorming agents, auto-writing for the sake of demoability, graph “AI magic” without clear user value.
- **What Apple-native AI opportunities exist:**
  - on-device summarization for selected text or note sections,
  - title suggestions,
  - semantic related-note suggestions,
  - action-item extraction,
  - note clustering and smart resurfacing,
  - privacy-preserving “ask this note” flows.
- **Roadmap:**
  - **Now:** keep note chat, vault chat, and writing tools; clarify provider state and privacy; make on-device path preferred when available.
  - **Next:** semantic related notes, action extraction, title suggestions, optional smart organization.
  - **Later:** vault-level clustering, study/review aids, Apple Intelligence integrations that feel systemic rather than bolted on.

## K. Award-worthiness gap analysis

### What is preventing Quartz from being award-worthy today?
- The editor is not yet calm, correct, and trustworthy enough.
- Organizational interactions do not yet feel completely native.
- Too much product surface competes with the core writing experience.
- Accessibility and fidelity risks are too high in custom areas.

### What would make Quartz feel exceptional?
- Bear-level writing calm with Apple Notes-level approachability.
- Obsidian-grade file ownership without Obsidian-grade complexity leakage.
- AI that helps recall and structure without ever undermining trust.
- Mac/iPad/iPhone behavior that feels purpose-built, not merely shared.

### Top 10 changes with highest award impact
1. Fix list editing correctness.
2. Eliminate preview/editor flicker and preserve context during mode changes.
3. Make drag/drop rock-solid across notes, folders, and windows.
4. Simplify default chrome and reduce ornamental surfaces.
5. Improve selection, undo/redo, and large-note performance.
6. Make search and note-opening feel instant and trustworthy.
7. Reduce dashboard to proven value or make it optional.
8. Reframe graph as a focused tool, not a trophy feature.
9. Complete accessibility for editor/sidebar/custom views.
10. Clarify AI as optional assistive intelligence, not app identity clutter.

## L. Exact step-by-step remediation plan for Claude Code to execute

### Phase 1 — Launch blockers and trust restoration

### Step 1: Create an editor correctness specification
- Goal: define canonical behaviors for Enter, Backspace, paste, undo, formatting, selection, and preview toggles.
- Why it matters: without a contract, patches to the editor will keep regressing.
- Exact implementation tasks: write behavior spec; enumerate list/checklist/numbered-list cases; define expected selection transitions and empty-item escape behavior.
- Files / modules / systems likely involved: new docs/test fixtures; `MarkdownTextView.swift`; `FormattingToolbar.swift`; editor tests.
- Platform considerations: iOS hardware/software keyboard, iPad keyboard/pointer, macOS AppKit semantics.
- Test cases to add: list continuation matrix, selection preservation, undo/redo after formatting.
- Manual QA checklist: create nested lists, press Return repeatedly, delete markers, switch input methods.
- Acceptance criteria: spec approved and every launch-blocker bug mapped to tests.
- Risk notes: none.
- Whether Claude Code should execute immediately or after prerequisite steps: immediately.

### Step 2: Fix bullet, numbered-list, and checklist continuation in the native editor
- Goal: make Return produce premium notes-app behavior.
- Why it matters: this is a daily-use trust feature.
- Exact implementation tasks: intercept newline insertion in `UITextViewDelegate`/`NSTextViewDelegate`; inspect current line; continue markers; increment numbered lists; preserve indentation; exit list on empty marker line.
- Files / modules / systems likely involved: `MarkdownTextView.swift`, possibly a new `MarkdownListEditingController.swift`, editor tests.
- Platform considerations: IME-safe handling, hardware keyboard Return, software keyboard Return, macOS newline semantics.
- Test cases to add: single-level bullets, nested bullets, numbered continuation, checklist continuation, empty-item exit, mixed indentation.
- Manual QA checklist: rapid typing in long notes, undo after continuation, paste list blocks, external keyboard on iPad.
- Acceptance criteria: list editing matches Bear/Notes expectations in all core cases.
- Risk notes: high-risk area; isolate in editor bridge and guard with tests.
- Whether Claude Code should execute immediately or after prerequisite steps: after Step 1.

### Step 3: Remove false drag/drop affordances or implement them fully
- Goal: stop misleading users about before/after insertion.
- Why it matters: misleading DnD is worse than limited DnD.
- Exact implementation tasks: either remove `.before/.after` visuals and collapse to folder-target semantics, or implement explicit sibling insertion rules and persistent ordering strategy; choose one.
- Files / modules / systems likely involved: `SidebarView.swift`, file tree model, folder management use case.
- Platform considerations: macOS precision DnD expectations are highest; iPad pointer behavior also matters.
- Test cases to add: drag note to folder, drag folder to root, invalid self/descendant moves, cancel drag, cross-window drag if supported.
- Manual QA checklist: repeated moves, drop on note row vs folder row, root drop zone, rename then move.
- Acceptance criteria: every visible drop target maps to deterministic final placement.
- Risk notes: if ordering is not strategically needed, do not invent it now.
- Whether Claude Code should execute immediately or after prerequisite steps: immediately after Step 2 or in parallel if isolated.

### Step 4: Make drag/drop transactional and error-aware
- Goal: only report success after real verified moves.
- Why it matters: trust and data integrity.
- Exact implementation tasks: replace optimistic `Task` loop with coordinated async move pipeline; aggregate results; refresh tree once; surface partial failures; maintain current selection when moved note URL changes.
- Files / modules / systems likely involved: `SidebarView.swift`, `SidebarViewModel.swift`, `FolderManagementUseCase.swift`, Spotlight relocation hooks.
- Platform considerations: file-provider latency and iCloud coordination on all platforms.
- Test cases to add: move conflicts, duplicate names, protected folder failures, provider error propagation.
- Manual QA checklist: simulate move into existing name, iCloud-backed vault, rapid repeated drags.
- Acceptance criteria: no false success haptics, no silent move failures, moved notes remain selectable/openable.
- Risk notes: preserve data integrity by avoiding broad refactors to file coordination first.
- Whether Claude Code should execute immediately or after prerequisite steps: after Step 3.

### Step 5: Stop animating full editor surface swaps
- Goal: eliminate preview flicker caused by whole-view transitions.
- Why it matters: calmness and perceived quality.
- Exact implementation tasks: disable or reduce animation on edit/preview transition; persist scroll context; avoid replacing entire scroll hierarchy when possible; test side-by-side or non-animated preview mode.
- Files / modules / systems likely involved: `NoteEditorView.swift`, `MarkdownPreviewView.swift`, `MarkdownTextView.swift`.
- Platform considerations: iPhone may prefer segmented toggle; iPad/macOS may support split preview.
- Test cases to add: repeated toggle stress test, rapid edits followed by preview switch, large document preview transition.
- Manual QA checklist: toggle preview during active typing, with Reduce Motion on/off, on large notes.
- Acceptance criteria: no visible flash, minimal scroll jump, no selection loss.
- Risk notes: avoid redesigning preview architecture and editor highlighting in one patch.
- Whether Claude Code should execute immediately or after prerequisite steps: after Steps 1-4.

### Step 6: Make syntax highlighting incremental
- Goal: reduce restyling churn and typing instability.
- Why it matters: this is likely a hidden cause of flicker/jank.
- Exact implementation tasks: use paragraph-bounded ranges from `MarkdownTextContentManager`; diff spans instead of resetting wide ranges; skip restyling unchanged runs; add large-document heuristics.
- Files / modules / systems likely involved: `MarkdownTextView.swift`, `MarkdownTextContentManager.swift`, `MarkdownASTHighlighter.swift`.
- Platform considerations: test both UITextView and NSTextView behavior, especially IME and dictation.
- Test cases to add: perf tests at 10k/50k/100k chars, selection stability while highlighting, non-Latin input.
- Manual QA checklist: hold key repeat, paste large markdown, use Japanese/Chinese IME, dictate text.
- Acceptance criteria: no obvious typing flicker and acceptable latency on large notes.
- Risk notes: high-risk editor code; checkpoint before patching.
- Whether Claude Code should execute immediately or after prerequisite steps: after Step 5.

### Phase 2 — Product-quality improvements

### Step 7: Add editor integration harnesses
- Goal: make interactive editor behavior testable without relying only on UI tests.
- Why it matters: editor regressions are expensive.
- Exact implementation tasks: extract pure helpers for list continuation, selection mapping, and formatting transitions; add representable test seams.
- Files / modules / systems likely involved: editor subsystem + test target.
- Platform considerations: keep shared logic platform-neutral where possible.
- Test cases to add: newline handler matrix, formatting/selection round trips, external modification merge cases.
- Manual QA checklist: confirm helper-driven behavior matches real views.
- Acceptance criteria: critical editor behaviors have deterministic tests.
- Risk notes: keep abstractions narrow.
- Whether Claude Code should execute immediately or after prerequisite steps: after Step 6.

### Step 8: Validate sidebar behavior end-to-end
- Goal: ensure organization feels native and scalable.
- Why it matters: note apps fail when moving/filing notes feels risky.
- Exact implementation tasks: add UI tests for create/move/delete/favorite/tag filters; profile large tree refreshes; preserve selection after rename/move.
- Files / modules / systems likely involved: `SidebarView*`, `ContentViewModel`, UI tests.
- Platform considerations: test compact navigation on iPhone and multi-column on iPad/macOS.
- Test cases to add: deep hierarchy, duplicate folder names, filter persistence, root moves.
- Manual QA checklist: 1k-note vault navigation, trackpad/pointer interactions, keyboard movement.
- Acceptance criteria: no broken selection, no inconsistent tree refresh, no surprise collapse behavior.
- Risk notes: large file trees may expose need for lazy loading later.
- Whether Claude Code should execute immediately or after prerequisite steps: after Phase 1.

### Step 9: Assess dashboard usefulness with evidence and either simplify or reposition it
- Goal: ensure dashboard is productively useful, not decorative.
- Why it matters: award-worthy products are opinionated.
- Exact implementation tasks: review launch/default empty state flow; measure whether dashboard should be default or optional; reduce card count; prioritize recent notes, pinned notes, and tasks over AI flourish.
- Files / modules / systems likely involved: `DashboardView.swift`, `ContentView.swift`.
- Platform considerations: iPhone should likely not lead with a heavy dashboard; macOS/iPad may tolerate richer overview.
- Test cases to add: snapshot tests for empty/populated states, accessibility labels for cards, default-route tests.
- Manual QA checklist: first-run, returning-user, power-user, small-screen cases.
- Acceptance criteria: dashboard either proves clear utility or is demoted/optional.
- Risk notes: do not redesign visuals before deciding product role.
- Whether Claude Code should execute immediately or after prerequisite steps: after Phase 1.

### Step 10: Reframe knowledge graph around concrete jobs-to-be-done
- Goal: keep graph only if it helps thought and retrieval.
- Why it matters: decorative complexity is expensive.
- Exact implementation tasks: define graph modes like current-note context, orphan notes, recent cluster, semantic neighbors; improve tap targets and accessibility summaries; consider removing default global graph entry from primary nav if weak.
- Files / modules / systems likely involved: `KnowledgeGraphView.swift`, graph cache, sidebar integration.
- Platform considerations: macOS primary home, optional on iPad later, likely not core on iPhone.
- Test cases to add: graph build caps, current-note preservation, semantic-edge toggles, accessibility descriptions.
- Manual QA checklist: usefulness for finding related notes, performance on large vaults.
- Acceptance criteria: graph serves at least one repeated daily workflow.
- Risk notes: if not demonstrably useful, reduce scope instead of polishing endlessly.
- Whether Claude Code should execute immediately or after prerequisite steps: after dashboard decision.

### Step 11: Run a Textual keep-or-replace spike
- Goal: make an explicit long-term preview/editor decision.
- Why it matters: Quartz should not drift into a split architecture accidentally.
- Exact implementation tasks: benchmark Textual preview latency on large docs; audit accessibility and scroll stability; prototype native lightweight preview alternative for headings/lists/basic formatting.
- Files / modules / systems likely involved: `MarkdownPreviewView.swift`, preview benchmarks, potential native preview prototype.
- Platform considerations: macOS/iPad can sustain richer preview; iPhone should prioritize simplicity.
- Test cases to add: preview perf benchmarks, VoiceOver on preview content, image/table/math rendering coverage.
- Manual QA checklist: compare Textual preview with native prototype on representative notes.
- Acceptance criteria: written decision memo with keep/constrain/replace outcome.
- Risk notes: treat as a spike; do not rewrite the preview blindly.
- Whether Claude Code should execute immediately or after prerequisite steps: after Phase 1 stabilization.

### Step 12: Improve Apple-native fidelity pass
- Goal: reduce “custom in a bad way” feel.
- Why it matters: premium Apple apps win through inevitability and restraint.
- Exact implementation tasks: audit toolbar density, remove redundant chrome, tighten spacing/typography hierarchy, use more native search/list/inspector defaults, simplify materials.
- Files / modules / systems likely involved: editor, sidebar, dashboard, settings, design system.
- Platform considerations: different levels of density per platform; do not force macOS chrome onto iOS.
- Test cases to add: visual snapshots across light/dark/dynamic type.
- Manual QA checklist: compare with Apple Notes, Bear, Things on each platform.
- Acceptance criteria: less chrome, more content, more obvious native behaviors.
- Risk notes: polish only after correctness improvements ship.
- Whether Claude Code should execute immediately or after prerequisite steps: after Steps 8-11.

### Phase 3 — Award-level enhancements

### Step 13: Accessibility hardening sweep
- Goal: make Quartz genuinely inclusive and robust.
- Why it matters: accessibility quality is part of Apple-native excellence.
- Exact implementation tasks: audit VoiceOver labels/actions, focus order, keyboard navigation, reduced motion/transparency, hit sizes, graph alternatives, drag/drop alternatives, editor announcements.
- Files / modules / systems likely involved: sidebar, editor, dashboard, graph, settings, app shell.
- Platform considerations: macOS keyboard access and VoiceOver rotor quality are crucial; iOS needs touch target and rotor behavior.
- Test cases to add: accessibility UI tests, trait/label assertions, reduced motion snapshots.
- Manual QA checklist: full app run with VoiceOver, Switch Control sampling, hardware keyboard only.
- Acceptance criteria: no unlabeled primary controls; core workflows fully operable without vision or drag gesture precision.
- Risk notes: graph may need an alternate list-based representation.
- Whether Claude Code should execute immediately or after prerequisite steps: after UI stabilization.

### Step 14: Performance and state correctness audit
- Goal: ensure Quartz remains calm at scale.
- Why it matters: premium note apps are often judged on large personal archives.
- Exact implementation tasks: instrument launch, vault load, tree refresh, search latency, indexing, editor typing on large docs, graph build time; reduce unnecessary full refreshes.
- Files / modules / systems likely involved: content VM, sidebar VM, editor, search index, graph, embedding service.
- Platform considerations: battery and thermal budgets matter more on iPhone/iPad.
- Test cases to add: performance baselines, memory growth checks, large-vault smoke tests.
- Manual QA checklist: 5k notes, 100k-character note, repeated open/close, background/foreground loops.
- Acceptance criteria: defined budgets and no regressions beyond agreed thresholds.
- Risk notes: avoid premature micro-optimization until profiler confirms bottlenecks.
- Whether Claude Code should execute immediately or after prerequisite steps: after Phase 2.

### Step 15: Define sensible AI / Apple Intelligence productization
- Goal: make AI supportive, private, and optional.
- Why it matters: AI can elevate Quartz only if it increases trust and recall.
- Exact implementation tasks: prioritize on-device summarization/rewriting where available; expose privacy/cost states; add related-note suggestions; simplify provider setup messaging.
- Files / modules / systems likely involved: `OnDeviceWritingToolsService.swift`, chat views, AI settings, embeddings/search integration.
- Platform considerations: on-device defaults where supported; cloud AI clearly opt-in.
- Test cases to add: provider fallback tests, unavailable-model messaging, privacy copy checks.
- Manual QA checklist: no-provider path, on-device-only path, failed-provider path, hallucination containment UX.
- Acceptance criteria: AI feels assistive and skippable, never required.
- Risk notes: do not broaden AI features until editor quality is already excellent.
- Whether Claude Code should execute immediately or after prerequisite steps: after core interaction quality is stable.

## M. Test plan

- **Unit tests:** markdown formatting, list continuation engine, heading extraction, search ranking, frontmatter parsing, move validation, AI prompt building.
- **Integration tests:** file-provider rename/move/delete flows, conflict detection, Spotlight update hooks, editor save/reload/merge path.
- **UI tests:** onboarding, note creation, note opening, sidebar selection, drag/drop, search, preview toggling, favorite toggling, keyboard shortcuts where possible.
- **Snapshot / visual regression tests:** dashboard states, sidebar in light/dark/dynamic type, editor header/toolbar, graph empty/loading state.
- **Performance tests:** typing latency at 10k/50k/100k chars, vault load with 1k/5k notes, search query latency, graph build time, preview toggle latency.
- **Accessibility tests:** labels, traits, focus order, reduced motion, Dynamic Type, keyboard-only navigation, VoiceOver custom actions.
- **Editor behavior tests:** bullet/numbered/checklist continuation, nested list indentation, selection preservation after formatting, undo/redo, paste markdown blocks, IME input, image drop insertion.
- **Drag-and-drop tests:** note to folder, folder to folder, invalid descendant move, root move, duplicate-name collision, cancelled drag, move across windows if supported.
- **Markdown parsing / rendering tests:** malformed markdown, huge code blocks, tables, math, mixed frontmatter, wiki-link edge cases.
- **State restoration tests:** reopen last note, restore selection, interrupted write recovery, relaunch after crash/background.
- **Undo / redo tests:** formatting, list continuation, task toggling, image insertion, note rename.

Edge cases to include explicitly:
- large notes,
- nested bullet lists,
- drag and drop across folders,
- drag and drop between windows,
- rapid editing while preview updates,
- app relaunch after interrupted writes,
- malformed markdown,
- duplicate folder names,
- deep hierarchy movement,
- offline / unavailable provider conditions for AI and sync-related surfaces.

## N. Self-healing execution loop

1. Inspect the target subsystem and identify the smallest correct patch.
2. Create a checkpoint (git commit or stashable local snapshot) before high-risk editor/storage work.
3. Add or update a failing test that reproduces the issue.
4. Patch the narrowest layer that owns the behavior.
5. Run targeted tests first.
6. If they pass, run the broader relevant suite.
7. Manually verify the affected workflow if the subsystem is UI/editor related.
8. If failures appear, inspect logs/diffs and patch again without broad rewrites.
9. Stop when acceptance criteria are met and broader regression suite is green.
10. Ask for human confirmation when a change would alter file format semantics, replace a core dependency, redesign dashboard/graph information architecture, or rewrite the editor bridge.

Guardrails:
- Do not combine editor architecture changes with dashboard/design polish in one iteration.
- Isolate high-risk editor changes behind helper types and dedicated tests.
- Never rewrite persistence paths without backup and migration analysis.
- Prefer deleting misleading UI over shipping half-working advanced interaction.

## O. Final prioritized roadmap

### Immediate must-fix items
1. Bullet/numbered/checklist editing correctness.
2. Sidebar drag/drop correctness and transactional behavior.
3. Preview flicker/state churn reduction.
4. Selection/scroll/state restoration reliability.
5. Editor performance on medium/large notes.

### Short-term roadmap
1. Sidebar behavior hardening.
2. Accessibility audit of editor/sidebar/dashboard.
3. Search and note-opening flow refinement.
4. Dashboard usefulness validation.
5. Textual decision spike.

### Medium-term roadmap
1. Graph repositioning around concrete workflows.
2. Visual simplification and Apple-native fidelity pass.
3. Large-vault performance work.
4. AI provider UX and on-device-first polish.

### Longer-term award-level roadmap
1. Exceptional writing environment with calm live markdown affordances.
2. Smart, privacy-respecting related-note intelligence.
3. Deep platform polish for iPad keyboard/pointer and macOS multiwindow workflows.
4. Highly refined accessibility and system integration worthy of editorial attention.

## P. If I were the acting principal engineer, what would I do first?

I would **freeze feature expansion for two to four weeks and treat Quartz as an editor-and-organization recovery project**.

Specifically:
1. Fix list behavior.
2. Fix drag/drop semantics.
3. Remove preview flicker.
4. Add interaction tests that make those bugs hard to reintroduce.
5. Only then decide whether dashboard, graph, and Textual deserve more investment.

That sequence is the difference between a flashy demo and a serious notes app people entrust with years of thinking.
