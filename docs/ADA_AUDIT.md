# Quartz ADA Audit — Codebase Map, UX Friction, and Refactor Roadmap

_Date:_ 2026-03-20

## 0. Implemented Since The Initial Audit

- Sidebar navigation was moved onto native outline/list primitives to stabilize disclosure, row hit testing, drag/drop targets, and row-level accessibility affordances.
- macOS vault open/create entry points are being moved toward direct native file panels instead of brittle indirect sheet state.
- Trash behavior is being standardized around a hidden vault-local `.quartzTrash` folder with a 30-day retention window.

## 1. Codebase Exploration: View → ViewModel / Service Map

The current app already has a promising SwiftUI-first architecture: `QuartzApp` owns global state, `ContentView` composes the shell, and `ContentViewModel` coordinates vault loading, indexing, iCloud monitoring, and editor instantiation. The main friction is not a lack of capability; it is that several premium interactions are implemented as custom overlays or imperative bridges instead of first-party-feeling platform primitives.

### App shell and scene routing

| View / Scene | Primary state / VM | Key collaborators | Current ADA assessment |
| --- | --- | --- | --- |
| `QuartzApp` | `AppState`, `AppearanceManager`, `FocusModeManager` | `ServiceContainer`, `KeyboardShortcutCommands`, secondary note windows | Strong scene bootstrap; command routing exists, but command surfaces still feel app-local instead of system-native. |
| `ContentView` | `ContentViewModel?`, local presentation state | `AppState`, `AdaptiveLayoutView`, `SidebarView`, `SearchView`, `ConflictResolverView` | Capable shell, but it owns a lot of modal state and presentation wiring, which makes interactions feel dense and less “effortless.” |
| `AdaptiveLayoutView` | bindings only | `NavigationSplitView`, Stage Manager helpers | Good platform-aware layout foundation. |
| `SearchView` | local search state | `VaultSearchIndex` | Useful, but presented as a modal list rather than a true Spotlight-speed command/search surface. |

### Sidebar and navigation

| View | Primary state / VM | Key collaborators | Current ADA assessment |
| --- | --- | --- | --- |
| `SidebarView` | `SidebarViewModel` | native `OutlineGroup`, `FileNodeRow`, `QuartzFeedback` | Now backed by native sidebar list/outline primitives, which should improve folder expansion reliability and row hit testing. |
| `SidebarOutlineRow` | row-local interaction state only | `openWindow`, `dropDestination`, `FileNodeRow` | Double-click open, row-level drop targets, and accessibility actions now live directly on the native outline rows. |
| `TagOverviewView` | none | `SidebarViewModel`-provided tags | Functionally fine; likely needs accessibility and dynamic type review. |
| `FileNodeRow` | none | `AppearanceManager` | Visually clean, but single-line name/date compression can feel rigid at larger sizes. |

### Editor surface

| View | Primary state / VM | Key collaborators | Current ADA assessment |
| --- | --- | --- | --- |
| `NoteEditorView` | `NoteEditorViewModel` | `MarkdownTextViewRepresentable`, `MarkdownPreviewView`, `CommandPaletteView`, `AIWritingToolsView` | Feature-rich, but crowded toolbar/sheet logic and custom overlays reduce the sense of directness. |
| `MarkdownTextViewRepresentable` | binds to `NoteEditorViewModel.content` and `cursorPosition` | TextKit 2, `MarkdownTextContentManager`, `MarkdownASTHighlighter` | Powerful foundation, but likely source of cursor jumps/flicker because view updates reassign full text and reschedule highlighting aggressively. |
| `FrontmatterEditorView` | parent-owned note/frontmatter state | `QuartzTagBadge` | Needs large-text audit. |
| `BacklinksPanel` | local state | `BacklinkUseCase` | Useful knowledge feature; not currently central to UX friction. |
| `CommandPaletteView` | local query/result state | file tree snapshot and callbacks | Good prototype, but not yet elevated into `SwiftUI.Commands` / true menu-command architecture. |

### AI, knowledge, and system integration

| View / Service | Primary state / actor | Key collaborators | Current ADA assessment |
| --- | --- | --- | --- |
| `AIWritingToolsView` | local processing state | `OnDeviceWritingToolsService`, `VectorEmbeddingService` | Helpful but currently a custom sheet around app-defined actions, not native Writing Tools / Foundation Models UX. |
| `OnDeviceWritingToolsService` | actor | NaturalLanguage, provider registry | Good fallback pipeline, but not Apple Intelligence-native despite the feature naming. |
| `QuartzAppIntents` | App Intents | vault provider, shared defaults | Strong foundation; Siri / widgets path already exists. |
| `QuartzSpotlightIndexer` via `ContentViewModel` | actor/service | Core Spotlight | Already present; this pillar is partially complete. |
| `KnowledgeGraphView` / `GraphViewModel` | `GraphViewModel` | vault provider, graph cache | Rich differentiator, though not the first UX priority. |

### Settings, onboarding, utilities

| View | Primary state / VM | Key collaborators | Current ADA assessment |
| --- | --- | --- | --- |
| `VaultPickerView` | local modal state | `VaultConfig`, bookmarks, file importers | Functional, but “Create New Vault” does not yet model iCloud Drive as a first-class app container destination. |
| `SettingsView` and subviews | mostly local state | app storage, services | Broad coverage; needs refinement after core interaction work. |
| `QuickNoteView`, widgets, share extension | lightweight local state | intents / provider | Strong ecosystem reach. |

## 2. ADA Pillar Snapshot

### Pillar: Interaction
- **Current Grade:** B-
- **Target Grade:** A
- **Assessment:** The app already uses `NavigationSplitView`, `List(.sidebar)`, native outline disclosure, secondary windows, swipe actions, and Spotlight indexing. However, the premium interaction layer is still incomplete: insertion-gap drop proposals, command-menu architecture, and system-grade search are not fully native yet.

### Pillar: Delight
- **Current Grade:** B
- **Target Grade:** A+
- **Assessment:** Quartz already has a custom design system, mesh backgrounds, haptics wrapper, and polished gradients. The remaining gap is motion quality and specificity: many effects are static or generic rather than tied to intent, state, and platform conventions.

### Pillar: Innovation
- **Current Grade:** B-
- **Target Grade:** A
- **Assessment:** App Intents, widgets, Spotlight, RAG context, and chat are already notable. The key gap is that “Apple Intelligence” is currently simulated via Natural Language plus optional providers, rather than using Apple-native Writing Tools / Foundation Models / Image Playground APIs where available.

### Pillar: Inclusivity
- **Current Grade:** C+
- **Target Grade:** A
- **Assessment:** There is some Reduce Motion awareness already, but accessibility behavior is inconsistent. Dynamic Type resilience, VoiceOver custom actions, and state restoration for cursor/scroll position need targeted work.

## 3. UX Friction Report — Top 5 Places Quartz Still Feels “Web-like” or Stiff

### 1. Sidebar note interactions are close, but not fully Mac-native
- The sidebar now uses `List` + `.sidebar`, which is the right base.
- Native outline disclosure and direct row hit testing are the right repair for the previously brittle custom tree implementation.
- Double-click-open can and should live directly on note rows, while drag and drop should prioritize reliable folder/root moves before reintroducing richer insertion semantics.
- **Pillar:** Interaction
- **ADA Grade:** B → A
- **Refactor:** Keep the sidebar on native outline/list primitives, then layer in explicit insertion-gap targeting only after the baseline folder expansion and drag/drop behaviors are stable.

### 2. Command discovery is split across hidden shortcuts, sheets, and toolbars
- `⌘K` exists as a hidden button-triggered overlay rather than a real command architecture.
- Search, note creation, and note actions are routed through multiple sheets and toolbar buttons, which adds modal friction.
- The result is “feature-rich but dense,” rather than calm and instant like Spotlight or Things.
- **Pillar:** Interaction
- **ADA Grade:** C+ → A
- **Refactor:** Move command entry into `SwiftUI.Commands`, unify search/new-note/open-note actions around a single palette service, and let `CommandPaletteView` become the visual front-end of a command system rather than a standalone overlay.

### 3. The markdown editor likely causes flicker because it still behaves like a bridged text host
- `MarkdownTextView` updates replace the full underlying text when bindings diverge, then immediately reschedule syntax highlighting.
- Cursor position is bound, but scroll position and selection restoration are not scene-persisted.
- This is exactly the kind of architecture that can produce visible selection jumps, scroll snaps, and “typed text catches up after the fact” sensations.
- **Pillar:** Delight
- **ADA Grade:** C → A
- **Refactor:** Introduce an editor session state object that owns text diffing, selection restoration, and scene persistence (`@SceneStorage` for scroll/cursor anchors); limit text view mutation to true external diffs only.

### 4. Delight systems exist, but haptics and motion are still generic rather than intentional
- `QuartzFeedback` centralizes feedback, but today it is mostly UIKit impact/notification wrappers on iOS and no-op elsewhere.
- `QuartzAnimation` offers reusable constants, yet there is no central “respect Reduce Motion and downgrade the choreography” policy across the app.
- `LiquidGlass` already uses `MeshGradient`, but the ambient depth is static and not yet coupled to note-opening transitions or content state changes.
- **Pillar:** Delight
- **ADA Grade:** B- → A+
- **Refactor:** Convert feedback into semantic event APIs (save/favorite/delete/move/open), adopt `sensoryFeedback` where available, and pair note-opening/editor-mode transitions with `PhaseAnimator` or spring-driven scene choreography that auto-downgrades under Reduce Motion.

### 5. Storage and intelligence features are powerful, but not yet system-first
- iCloud Drive support currently detects ubiquitous folders and monitors sync, but vault creation still feels like “pick any folder” instead of “use Quartz’s app folder in iCloud Drive.”
- AI writing tools are useful, yet they are not actually using the newest Apple-native Writing Tools / Foundation Models path.
- Spotlight indexing is already a strength, but Image Playground and richer Siri affordances are still missing.
- **Pillar:** Innovation
- **ADA Grade:** B- → A
- **Refactor:** Add a first-class “Quartz in iCloud Drive” vault destination using the ubiquity container documents folder, then layer in native Apple Intelligence APIs and attachment generation flows where OS support exists.

## 4. Recommended Implementation Roadmap

This roadmap follows the requested priority: **haptics first, sidebar second**, then editor stabilization and deeper system integration.

### Phase 1 — Tactile foundation (highest ROI, low-to-medium risk)
1. Build a semantic feedback map in `QuartzFeedback`:
   - save success
   - favorite toggle on/off
   - destructive delete
   - move/reorder
   - command invocation
2. Replace scattered direct calls with semantically named events.
3. Add availability-based `sensoryFeedback` adapters for modern OS targets.
4. Audit all custom animations against Reduce Motion and define reduced-motion equivalents centrally.

**Pillar:** Delight  
**ADA Grade:** B- → A

### Phase 2 — Sidebar native-feel refactor
1. Keep `List(.sidebar)` as the foundation.
2. Add macOS row double-click to open selected notes in `WindowGroup(for: URL.self)`.
3. Refactor drag/drop into a dedicated insertion-target model with before/inside/after semantics.
4. Add `AccessibilityCustomActions` for favorite and delete on rows.
5. Persist sidebar expansion and scroll restoration where practical.

**Pillar:** Interaction / Inclusivity  
**ADA Grade:** B- / C+ → A

### Phase 3 — Markdown editor stabilization
1. Introduce editor scene state (`@SceneStorage`) for selection/cursor/scroll anchor.
2. Prevent full-string replacement during ordinary typing.
3. Diff external content updates before mutating the platform text view.
4. Separate highlighting scheduling from every SwiftUI update cycle.
5. Add instrumentation for cursor-jump and save-latency regressions.

**Pillar:** Delight / Inclusivity  
**ADA Grade:** C → A

### Phase 4 — Command architecture and app-wide velocity
1. Add `SwiftUI.Commands` command groups for note/file/search actions.
2. Rebuild `⌘K` around a shared command registry.
3. Let palette results include commands, notes, folders, and recent actions.
4. Ensure parity between toolbar actions, menu commands, Siri intents, and widgets.

**Pillar:** Interaction / Innovation  
**ADA Grade:** C+ → A

### Phase 5 — Apple Intelligence and iCloud-first system integration
1. Add native Writing Tools / Foundation Models adoption where available.
2. Add Image Playground note attachment generation.
3. Expand App Intents for note creation/opening/focus workflows.
4. Make iCloud Drive creation default to the app’s ubiquity container documents folder when the user chooses iCloud Drive.
5. Keep Spotlight indexing incremental and tie it into attachment metadata where relevant.

**Pillar:** Innovation  
**ADA Grade:** B- → A

## 5. Immediate Recommendations for the Next Refactor Pass

1. **Start with `QuartzFeedback` + `QuartzAnimation`** so every subsequent interaction refactor has a shared tactile language.
2. **Then refactor `SidebarView` / `SidebarTreeNode`** for double-click, insertion semantics, and accessibility custom actions.
3. **Then harden `MarkdownTextView`** because editor trust is the core product experience.
4. **Then elevate command/search architecture** to make the whole app feel faster.
5. **Then finish Apple Intelligence + iCloud container work** once the interaction baseline is world-class.

## 6. Notes on Already-Strong Foundations

Quartz is not starting from zero. These pieces are already genuinely good and worth preserving:
- secondary note windows already exist at the app-scene level,
- Core Spotlight indexing already exists,
- App Intents and widgets already exist,
- the design system already contains a strong material/mesh foundation,
- the editor already uses a serious TextKit 2 stack instead of `TextEditor`.

The path to ADA quality is therefore **refinement, native-feel tuning, and system-deep integration**—not a rewrite.
