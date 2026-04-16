# Editor Deep Review

Use the prior Phase 1 and Phase 2 findings, then structure the file with these sections and conclusions:

- **Architecture verdict**
  - The editor is a SwiftUI shell with a native AppKit/UIKit bridge, centered on [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift), mounted through [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift), backed by custom native views in [MarkdownTextView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextView.swift), and highlighted through [MarkdownASTHighlighter.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift).
  - TextKit 2 is present, but not fully authoritative. [MarkdownTextContentManager.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownTextContentManager.swift) exists, but current production usage is limited to font configuration through [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift). Live edits still mutate native text storage directly in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift). Proven.

- **Authoritative flows**
  - Toolbar formatting: [EditorContainerView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/EditorContainerView.swift) → `EditorSession.applyToolbarFormatting`. Proven duplicated path, heuristic, fragile.
  - iOS hardware-key formatting: [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift) text-view key commands → `EditorSession.applyFormatting`. Proven duplicated path.
  - macOS command/menu formatting: [QuartzApp.swift](/Users/I533181/Developments/Quartz/Quartz/QuartzApp.swift) → [KeyboardShortcutCommands.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/KeyboardShortcutCommands.swift) → `AppState.pendingCommand` → [ContentView.swift](/Users/I533181/Developments/Quartz/Quartz/ContentView.swift) → [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift) → `EditorSession.applyFormatting`. Proven duplicated path.
  - Selection propagation: native text-view delegates in [MarkdownEditorRepresentable.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownEditorRepresentable.swift) drive `EditorSession.selectionDidChange`. Proven duplicated mirrored state via `cursorPosition` and `lastExpandedSelection`.
  - Note switching: [WorkspaceStore.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Workspace/WorkspaceStore.swift) route state → [ContentView.swift](/Users/I533181/Developments/Quartz/Quartz/ContentView.swift) observer → [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift) → `EditorSession.loadNote`. Proven.
  - Autosave: `textDidChange` in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift) → `scheduleAutosave()` → `save(force:)`. Proven stale-write protection through captured note URL and post-save text guard.
  - External file changes: `NSFilePresenter` through [NoteFilePresenter.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/NoteFilePresenter.swift) plus non-iCloud watcher in [EditorSession.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSession.swift). Proven dual-path ingestion.
  - Parse → highlight → render: [MarkdownASTHighlighter.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift) → [EditorSemanticDocument.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/EditorSemanticDocument.swift) → `EditorSession.applyHighlightSpans*`. Proven hybrid semantic model.

- **Proven semantic divergence**
  - Formatting authority is split across toolbar, iOS hardware keyboard, and macOS menu/command chains. Proven.
  - Selection exists both in the native text view and in `EditorSession.cursorPosition`; concealment and highlighting depend on it. Proven.
  - Markdown semantics are split between AST traversal and regex/global span synthesis in [MarkdownASTHighlighter.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift). Proven.
  - External file ingestion uses full-note reload rather than structural merge when local content is clean. Proven.
  - Startup lifecycle is only partially formalized; [StartupCoordinator.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Vault/StartupCoordinator.swift) defines `restorationApplied`, but the production code only advances through `vaultResolved`, `editorMounted`, and `indexWarm` in [ContentViewModel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/App/ContentViewModel.swift). Proven.

- **Feature matrix snapshot**
  - `production-grade`: autosave stale-write guards, coordinated writes, URL-based note routing, export via [ShareMenuView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/ShareMenuView.swift) and [NoteExportService.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Domain/Export/NoteExportService.swift).
  - `correct but fragile`: headings, bold, italic, links, lists, tasks, tables, code blocks, images, note switching, hardware keyboard support, external reload handling.
  - `partially implemented`: math, generic attachments, backlinks infrastructure, preview surface, typewriter mode state, focus ergonomics, long-note readiness.
  - `visually present but not truly wired`: “Find in Note” command, Typewriter Mode setting, footnote toolbar action, [BacklinksPanel.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/BacklinksPanel.swift), [MarkdownPreviewView.swift](/Users/I533181/Developments/Quartz/QuartzKit/Sources/QuartzKit/Presentation/Editor/MarkdownPreviewView.swift).
  - `missing`: in-note replace, callouts, folding, link previews, fully surfaced backlinks UX.
  - `architecturally wrong and should be replaced`: multi-path formatting authority, hybrid AST/regex range model, selection-as-render-driver, non-authoritative TextKit 2 content manager.

- **Missing / unknown**
  - iOS editor-internal file drag/drop parity is still unknown.
  - Accessibility quality beyond basic existence of tests is still unverified.
  - Cross-window identity correctness beyond current note-window routing is plausible but not fully proven.
