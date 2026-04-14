# Editor Bear Gap Plan

Date: 2026-04-14
Status: Planned
Owner: Quartz editor track
Depends on: Phase 4.5 complete
Does not block: Phase 5 start

## Why This Exists

Phase 4.5 made the editor trustworthy.
It did not make the editor feel like Bear.

The remaining gap is not primarily parser correctness anymore. The remaining gap is writer
experience:

- the surface must feel calmer while typing
- toolbar and command flows must feel more intentional
- rich markdown interactions must feel inline and native, not mechanical
- long writing sessions must stay visually stable and low-friction
- editor quality must be proven in real app flows, not only in harness-level tests

## Current Reality

Quartz now has the right foundation:

- semantic editor model
- token-aware `hiddenUntilCaret`
- macOS, iPhone, and iPad editor parity gates
- smart/raw paste policy
- live mutation regressions for formatting, undo/redo, reopen, and concealment

Quartz is still below Bear level in these user-visible areas:

- visual calm and typography
- inline interaction polish for links, tasks, code, and tables
- contextual formatting guidance and keyboard flow
- selection/caret feel during rapid authoring
- app-level UI verification around editor focus, commands, and scene behavior
- confidence from long-session dogfooding on real notes

## Product Standard

The target is not “Markdown editor with green tests.”
The target is:

- a writing surface that stays visually quiet until the user needs syntax
- formatting actions that never feel like string surgery
- predictable cursor and selection behavior in every common writing path
- mobile and desktop parity in editing feel, not only in correctness
- typography and spacing that feel intentional enough to support long-form writing

## Gap Categories

### 1. Visual Calm

Problems to close:

- heading/body rhythm can still feel more utilitarian than editorial
- hidden markdown is correct, but not yet maximally subtle
- toolbar and chrome can still compete with the page
- paragraph density and line-length tuning need writer-first defaults

Target state:

- quieter body typography
- tighter heading scale tuning
- more deliberate spacing between blocks
- editor chrome that fades into the background until needed

### 2. Inline Interaction Quality

Problems to close:

- link, task, and code interactions are reliable but not yet elegant
- table interaction is still too close to raw markdown ergonomics
- syntax reveal rules are technically correct but not fully “invisible”

Target state:

- token-local reveal with cleaner visual transitions
- inline link editing that does not break flow
- task toggles and list transitions that feel immediate
- safer, calmer table editing behavior

### 3. Writer Flow

Problems to close:

- formatting affordances are semantically correct, but still somewhat tool-like
- keyboard-first transitions need to feel faster and more obvious
- contextual guidance is still thin for complex structures

Target state:

- fast heading/list/quote/code transitions from keyboard and toolbar
- better context-sensitive affordances
- fewer “hunt for syntax” moments

### 4. App-Level Confidence

Problems to close:

- the editor harness is strong, but some real app flows still rely on lower coverage
- focus, scene restore, sidebar changes, onboarding entry, and command routing can still regress outside the harness

Target state:

- XCUITests cover the editor inside the real app shell
- keyboard commands, toolbar actions, window/scene restore, and navigation transitions are verified on macOS, iPhone, and iPad where relevant

## Workstreams

### BG-1 Visual Polish

Deliverables:

- rebalance editor typography tokens for body, headings, quotes, code, and lists
- refine paragraph spacing and block rhythm
- reduce visual weight of inactive markdown syntax further without harming accessibility
- tune toolbar/chrome materials and spacing so the page remains dominant

Required tests:

- snapshot baselines for the reality corpus on macOS, iPhone, and iPad
- Dynamic Type snapshots for editor-heavy screens
- Reduce Motion verification where reveal/fade behavior changes

### BG-2 Inline Rich Markdown Behaviors

Deliverables:

- improve inline link interaction model
- polish task-item toggling and continuation
- harden code-span and code-block editing transitions
- introduce safer table editing behavior and regression coverage

Required tests:

- mounted live-editor regressions for link/task/code/table flows
- corpus fixtures for mixed rich-markdown notes
- selection-stability assertions after each interaction

### BG-3 Keyboard And Command Flow

Deliverables:

- tighten keyboard-first heading/list/quote/code workflows
- ensure toolbar, menu, and shortcut actions are semantically identical
- add contextual command affordances for common block conversions

Required tests:

- command parity tests across toolbar and keyboard paths
- macOS command-menu UI tests
- iPad hardware-keyboard UI tests for supported shortcuts

### BG-4 Mobile Feel Pass

Deliverables:

- reduce any remaining iPhone/iPad friction in selection handles, toolbar presentation, and focus retention
- verify formatting actions in compact and regular width
- ensure editor state survives app foreground/background and scene changes

Required tests:

- mobile editor snapshots for portrait and landscape where meaningful
- mobile live-mutation tests for selection retention and toolbar actions
- XCUITests for open note -> edit -> background -> foreground -> continue editing

### BG-5 Real App UI Coverage

Deliverables:

- add editor-focused XCUITests in the actual app shell
- cover sidebar/note switching, scene restoration, onboarding entry, and command routing
- verify no focus loss or stale formatting state after app-level transitions

Required tests:

- macOS UI tests for:
  - open note -> edit -> switch note -> return
  - command-based formatting from menu/toolbar
  - window restore with the same note and selection context
- iPhone UI tests for:
  - open note -> edit -> return from background
  - inline toolbar actions on compact width
- iPad UI tests for:
  - split view / multi-column editor stability
  - hardware-keyboard command flows where supported

### BG-6 Dogfood And Corpus Expansion

Deliverables:

- expand `EditorRealityCorpus` with real long-form notes
- add “writer session” scenarios:
  - note started from scratch
  - note heavily restructured
  - note with links/tasks/code/tables mixed together
- keep a rolling list of qualitative editor papercuts found during real writing sessions

Required tests:

- every new papercut must add:
  - a corpus fixture
  - a regression test
  - a UI test when the failure requires real app context

## UI Test Requirements

The existing editor excellence harness remains mandatory, but it is not enough by itself.

For Bear-gap closure, Quartz must also carry editor-focused UI tests in the app layer:

- harness tests prove editing correctness
- UI tests prove real-world flow correctness

Both are required.

Minimum app-level UI matrix:

- macOS:
  - menu command formatting
  - toolbar formatting
  - note switching while preserving editor state
  - reopen/restore with same note context
- iPhone:
  - compact toolbar editing flow
  - background/foreground continuity
  - keyboard focus recovery after navigation
- iPad:
  - split view editor continuity
  - hardware-keyboard shortcut flow
  - focus stability across layout changes

## Suggested Execution Order

1. BG-5 Real App UI Coverage
2. BG-1 Visual Polish
3. BG-2 Inline Rich Markdown Behaviors
4. BG-3 Keyboard And Command Flow
5. BG-4 Mobile Feel Pass
6. BG-6 Dogfood And Corpus Expansion

Reason:

- UI coverage should land first so the next polish passes do not regress the real app shell.
- Visual polish should happen before richer interaction tuning, because spacing and typographic rhythm affect every later decision.
- Dogfooding should stay active for the entire track, but formal corpus expansion is most useful once the UI and interaction layers stabilize.

## Done When

The Bear gap is only closed when all of the following are true:

- the editor still passes:
  - `bash scripts/test_editor_excellence.sh`
  - `bash scripts/ci_phase4_5_editor.sh`
- editor-focused UI tests are green on the supported macOS, iPhone, and iPad flows
- the default writing view feels calm enough that syntax rarely competes with prose
- toolbar, keyboard, and menu formatting flows feel equivalent
- links, tasks, code, and tables behave inline without obvious friction
- no open editor papercut remains unclassified
- real-note dogfooding no longer produces obvious “this is not Bear-level” failures

## Constraints

- Do not re-open Phase 4.5 architecture work unless a real defect demands it.
- Do not pull preview/export concerns back into the live editor.
- Do not call the Bear gap closed from snapshots alone; UI flow proof is mandatory.
- Do not start deleting editor gates in the name of speed.
