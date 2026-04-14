# Phase 4.5 — Editor Rebuild Plan

Date: 2026-04-14
Status: Planned
Blocks: Phase 5

## Why This Phase Exists

Phase 4 shipped feature breadth. It did not deliver a Bear- or Ulysses-class writing surface.
The current editor is good enough for feature demos, but still structurally too fragile in the
places that users feel immediately:

- syntax/render state can drift after edits and reloads
- styling is still applied as a repair pass over text storage instead of as a stable semantic model
- hidden/faded markdown is not truly caret-aware
- complex markdown elements do not yet have calm, editor-native interactions
- tests still over-index on parser output and under-index on editing parity

Phase 5 should not be built on top of that.

## Product Target

Quartz 4.5 must deliver a native inline Markdown editor that feels:

- as calm as Antinote while typing
- as seamless as Bear for inline rich markdown behaviors
- as intentional as Ulysses for writing flow and semantic structure

This phase is not about adding more syntax. It is about making the editor trustworthy.

## Research Takeaways

### Antinote

- Hide complexity only when the user is not actively editing it.
- Visual simplification must preserve original input.
- Text transformations should happen after the cursor leaves the active region, not during token entry.

Reference: <https://antinote.io/user-manual>

### Bear

- Inline editing beats detached editors for selection, undo, copy/paste, accessibility, and mobile ergonomics.
- Hidden markdown only works when concealment is selection-aware.
- Rich blocks can still stay in-flow without becoming separate documents.

References:
- <https://blog.bear.app/2023/07/bear-2-is-here/>
- <https://community.bear.app/t/bear-2-5-beta-update-math-formula/17883>

### Ulysses

- The editing model must be semantic and guided, not visually noisy.
- Writer flow improves when formatting affordances are contextual and keyboard-first.
- WYSIWYM remains a valid model if interactions are fast and predictable.

Reference: <https://help.ulysses.app/en_US/dive-into-editing/markdown-xl>

### FluxMarkdown

- Preview rendering and writing should not be solved with the same engine.
- Web rendering is the right answer for high-fidelity preview compatibility, not for the core writing loop.
- Compatibility work should be driven by a real-world corpus, not one-off bug reports.

References:
- <https://raw.githubusercontent.com/xykong/flux-markdown/master/README.md>
- <https://raw.githubusercontent.com/xykong/flux-markdown/master/docs/dev/ARCHITECTURE.md>
- <https://raw.githubusercontent.com/xykong/flux-markdown/master/docs/dev/renderer/RENDERER_MARKDOWN_IT_PLUGIN_ROADMAP.md>

## Current Quartz Diagnosis

### What We Keep

- Native TextKit 2 stack in [MarkdownTextView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextView.swift)
- Native text view source-of-truth in [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift)
- `EditorSession` as the single mutation coordinator in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift)
- Background AST parsing and incremental parsing work in [MarkdownASTHighlighter.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift)

### What Is Structurally Wrong

- The editor still relies on attribute repair passes in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift#L1101) instead of rendering from stable semantic state.
- Text changes trigger highlight scheduling directly in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift#L409), which keeps parser and presentation too tightly coupled.
- Syntax concealment is color-based only in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift#L1840), not token- and caret-aware.
- The representable owns too much editor runtime wiring in [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift#L78), which makes behavior hard to validate independently.
- Existing reopen/edit tests still validate text persistence better than render persistence.

## Target Architecture

Quartz 4.5 will separate the editor into five layers.

### 1. Text Engine

- TextKit 2 remains the native editing substrate.
- `NSTextView` and `UITextView` stay the editing controls.
- The native view remains the source of truth for live text and selection.

### 2. Semantic Document Model

- Introduce a persistent editor semantic model built from markdown parse output:
  - stable block IDs
  - stable inline token IDs
  - line-to-token index
  - token kind metadata
  - active edit region metadata
- The highlighter stops being the effective document model.
- The parse result becomes render input, not just a span list.

### 3. Render Plan

- Replace “segment rewrite” logic with a render plan composed of:
  - base body attributes
  - block decorations
  - inline decorations
  - overlay/concealment rules
  - attachment/widget placements
- Only dirty blocks and intersecting inline runs are re-rendered.
- Full-storage rewrites become a fallback, not the default.

### 4. Interaction Layer

- Caret-aware syntax concealment.
- Token-local interaction rules for links, footnotes, code, tables, tasks, and math.
- Typing attributes derived from semantic context, never from stale text storage alone.
- Selection, IME composition, undo grouping, and paste policies treated as first-class editor behavior.

### 5. Preview / Export Path

- Keep the native editor for writing.
- Build or adopt a separate high-fidelity preview path for HTML/export parity and richer rendered blocks.
- Do not push web-renderer concerns into the live text engine.

## Workstreams

### 4.5.1 Corpus And Failure Harness

Deliverables:

- `EditorRealityCorpus/` fixtures from real notes:
  - headings and paragraph transitions
  - nested emphasis
  - lists and task items
  - tables
  - wiki-links
  - code fences
  - math
  - attachments
  - mixed-language notes
- Reproduction tests for:
  - open -> edit -> close -> reopen parity
  - caret-at-token-boundary behavior
  - paste normalization
  - IME composition
  - hidden markdown around selection

Rule:

- Every editor bug must add a corpus sample and a parity test before the fix lands.

### 4.5.2 Semantic Model Extraction

Deliverables:

- `EditorSemanticDocument`
- `EditorBlockNode`
- `EditorInlineToken`
- `EditorRenderPlan`
- stable mapping from AST/source range -> semantic IDs

Rules:

- IDs must survive reparses when content outside a node changes.
- Dirty tracking must operate on blocks and tokens, not just raw character ranges.

### 4.5.3 Rendering Engine Rewrite

Deliverables:

- Replace broad `NSTextStorage` segment repair with block-local render application.
- Separate:
  - body styling
  - semantic styling
  - concealment styling
  - widget/attachment injection
- Maintain selection and typing context without replaying stale attributes.

Delete or deprecate:

- any logic that infers correctness from the first character of a run
- blind restore of pre-highlight typing attributes
- concealment that does not inspect caret or selection overlap

### 4.5.4 Editing Behavior Hardening

Deliverables:

- caret-aware markdown hiding
- stable heading/list continuation behavior
- table navigation that does not corrupt neighboring attributes
- paste pipeline with explicit normalization policy
- undo coalescing rules by mutation class
- selection preservation for all editor-originated mutations

This is the point where Quartz should start to feel calm rather than merely correct.

### 4.5.5 Complex Element Strategy

Deliverables:

- define in-flow interaction model for:
  - links
  - footnotes
  - tasks
  - tables
  - inline images
  - math
- every complex element gets one of three modes:
  - pure inline
  - inline with local affordance
  - inline placeholder + focused popover sheet only when unavoidable

Rule:

- default to inline.
- detached editing UI is an exception that must justify itself on accessibility or input constraints.

### 4.5.6 Preview And Compatibility Track

Deliverables:

- explicit preview architecture decision for rich rendering beyond the editor
- compatibility corpus for imported/exported markdown dialects
- decision memo for which syntax belongs to:
  - editor-native support
  - preview-only support
  - export-only support

Rule:

- Quartz editor should not become a mini browser.
- Quartz preview should not dictate the live typing model.

## Test Matrix

### A. Editor Parity

| Test Suite | What It Covers | Type |
|---|---|---|
| `EditorRenderingParityTests` | open, edit, close, reopen visual parity | Integration |
| `EditorSelectionParityTests` | selection/cursor unchanged after semantic rerender | Integration |
| `TypingContextTests` | paragraph, heading, list, code, quote typing attributes | Unit + Integration |
| `SyntaxConcealmentTests` | hidden markdown only outside active caret/selection | Integration |

### B. Interaction Safety

| Test Suite | What It Covers | Type |
|---|---|---|
| `IMECompositionEditorTests` | no corruption during marked text composition | Integration |
| `PasteNormalizationTests` | paste policies and escape behavior | Integration |
| `UndoCoalescingTests` | undo boundaries by mutation type | Integration |
| `TableEditingStabilityTests` | tab nav, row insertion, attribute safety | Integration |

### C. Visual Regressions

| Test Suite | What It Covers | Type |
|---|---|---|
| `EditorSnapshot_macOS` | macOS editor visual parity corpus | Snapshot |
| `EditorSnapshot_iPhone` | iPhone editor visual parity corpus | Snapshot |
| `EditorSnapshot_iPad` | iPad editor visual parity corpus | Snapshot |
| `EditorFocusedTokenSnapshots` | token selected vs unselected concealment states | Snapshot |

### D. Performance

| Test Suite | What It Covers | Type |
|---|---|---|
| `EditorKeystrokeLatencyTests` | keystroke-to-painted-frame P95 | Performance |
| `EditorLargeDocumentTests` | 20k, 50k, 100k char documents | Performance |
| `EditorMemorySteadyStateTests` | no attribute churn or runaway attachment memory | Performance |
| `EditorScrollStabilityTests` | fast scrolling while background parse updates | Performance |

### E. Accessibility

| Test Suite | What It Covers | Type |
|---|---|---|
| `EditorVoiceOverInteractionTests` | token announcements, selection context, controls | Accessibility |
| `EditorDynamicTypeParityTests` | editor layout and overlays scale correctly | Snapshot |
| `EditorReduceMotionTests` | no distracting transitions in conceal/reveal states | Accessibility |

## Delivery Sequence

1. Lock a failure corpus from current editor bugs.
2. Build the semantic document model and render plan side-by-side with the current span path.
3. Migrate simple blocks first: paragraph, heading, blockquote, list.
4. Migrate inline tokens next: emphasis, strong, code, link, wiki-link.
5. Add caret-aware concealment.
6. Migrate complex blocks: tables, tasks, inline attachments, math.
7. Turn on visual parity gates for macOS, iPhone, and iPad.
8. Remove obsolete segment-rewrite paths once parity is proven.
9. Only then resume Phase 5.

## Explicit Non-Goals

- No CRDT work in this phase.
- No graph work in this phase.
- No command palette expansion in this phase.
- No new “nice to have” markdown syntax unless required by the corpus.
- No shipping Phase 5 on top of the pre-4.5 editor core.

## Done When

- typing in normal markdown notes feels stable under rapid edits, undo, reopen, and long sessions
- heading/list/code/paragraph transitions never drift visually
- syntax hiding is caret-aware and selection-safe
- complex markdown elements feel editor-native, not bolted on
- reopen parity is proven by tests, not assumed
- macOS, iPhone, and iPad editor snapshot suites are green
- performance budgets stay within Phase 1 and Phase 4 limits
- Phase 5 work can begin without carrying editor debt forward
