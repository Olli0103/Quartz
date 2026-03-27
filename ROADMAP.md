# Quartz — Development Roadmap

_Last updated: 2026-03-27_

## Vision

Quartz is a premium native Apple markdown notes app targeting **Apple Design Award** quality.
The hybrid of Apple Notes and Obsidian — simple, elegant, powerful.

---

## Phase A: 3-Pane Workspace Shell — **100% Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| A1 | `WorkspaceStore` + `WorkspaceView` (NavigationSplitView 3-column) | Done |
| A1.5 | ADA polish (native materials, focus mode spring, toolbar stubs) | Done |
| A2 | `AppCoordinator` (centralized sheet/alert routing, replaced 15 @State booleans) | Done |
| A3 | Extracted `KeyboardShortcutCommands` + `StageManagerModifier`, deleted dead `AdaptiveLayoutView` | Done |

---

## Phase B: Preview Engine & Note List — **100% Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| B1 | `NotePreviewIndexer` (8KB bounded read), `NotePreviewRepository` (JSON cache), `SnippetExtractor`, `NoteListItem` model | Done |
| B2 | `NoteListStore`, `NoteListSidebar`, `NoteListRow` (middle column UI with search, sort, time buckets) | Done |
| B2.5 | Wired real `SidebarView` into WorkspaceView left column, bridged `SourceSelection` routing | Done |
| B3 | Incremental updates via NotificationCenter, time-bucketed sections (Today / Previous 7 Days / etc.), targeted single-item refresh | Done |

---

## Phase C: TextKit 2 Editor Hardening — **100% Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| C1 | `EditorSession` (authoritative text buffer, no SwiftUI binding feedback loop), `MarkdownEditorRepresentable` (surgical `replaceCharacters`), `EditorContainerView`, IME composition guards | Done |
| C2 | `MarkdownAnalysisService` (background heading + stats extraction), `InspectorStore`, `InspectorSidebar` (ToC, stats, tags, metadata), scroll-synced active heading via `closestPosition(to:)` | Done |
| C3 | `MarkdownFormatEdit` + `surgicalEdit()` on `MarkdownFormatter`, `FormattingState` detection, platform toolbars with active state awareness, undo/redo buttons | Done |
| C3.5 | Toolbar aesthetics overhaul (native macOS buttons, `.hierarchical` icons, `.plain` button style) | Done |
| C4 | Focus mode: distraction-free writing — **moved to backlog** (macOS NavigationSplitView columnVisibility bug) | Backlog |
| C5 | EditorSession lifecycle fix: session recycled across note switches, `closeNote()`, undo stack cleared per note | Done |

---

## Phase E: Toolbar Harmonization & ADA Polish — **100% Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| E1 | Removed 520 lines of dead code from ContentView (old sidebarColumn, detailColumn, supporting methods) | Done |
| E2 | Icon harmonization (`.symbolRenderingMode(.hierarchical)` on all toolbar/header icons) | Done |
| E3 | New Note button in middle column toolbar | Done |
| E4 | SidebarView empty state → `QuartzEmptyState` | Done |
| E5 | Focus mode wired through EditorContainerView → WorkspaceStore | Done |

---

## Phase F1: Voice Notes & Meeting Minutes — **100% Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| F1 | Removed `#if os(macOS)` from voice/meeting sheet builders — now cross-platform | Done |
| F1 | Added mic button to editor toolbar, voice + meeting options in New Note menu | Done |
| F1 | Existing `AudioRecordingService`, `TranscriptionService`, `MeetingMinutesService` wired into 3-pane workspace | Done |

---

## Phase F2: Inline AI Assistant — **⏸ Paused/WIP**

| Step | Deliverable | Status |
|------|------------|--------|
| F2 | Sparkle ✨ button in formatting toolbar, AI popover with quick actions + custom prompt, surgical text replacement via `applyExternalEdit` | Paused |

> **Note:** Foundation Models disabled due to macOS 26 beta crash. AI provider path (user-supplied API key) works.
> **Note:** Foundation Models disabled due to macOS 26 beta crash. AI provider path (user-supplied API key) works.

---

## Phase F3: Chat on Note (Document Context Q&A) — **✅ Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| F3 | Document-context Q&A — chat grounded on the active note's content, contextual follow-ups, inline citation | Done |

> **Note:** Document-context Q&A with SSE streaming, 30fps token batching, live EditorSession context read.

---

## Phase F4: Chat on Vault (RAG) — **✅ Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| F4 | Global vault Q&A with local retrieval, context injection, streaming responses, and clickable citations | Done |

> **Note:** Global vault Q&A with vector embeddings, streaming citations, source cards, JIT indexing, and visible indexing progress.

---

## Phase G: Cloud Sync & Data Safety — **✅ Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| G1 | iCloud Drive sync with conflict resolution, vault backup/restore engine, sync status UI, and Data & Sync settings panel | Done |

> **Note:** iCloud Drive sync with vault migration, folder-based backup engine, sync status indicator, Data & Sync settings panel.

---

## Phase H: Mac Polish Master Plan — **✅ Complete**

| Step | Deliverable | Status |
|------|------------|--------|
| H1 | Command Palette (Omni-Search) — Cmd+K spotlight-style search + commands | ✅ Done |
| H2 | Export Pipeline — PDF, HTML, plain text export | ✅ Done |
| H3 | Multi-Window & Stage Manager — proper macOS windowing | ✅ Done |
| H4 | Visual Aesthetics & Animation Polish — final ADA-quality refinements | ✅ Done |

> **H1 Note:** Spotlight-style Cmd+K palette with fuzzy note search, command registry, keyboard navigation, frosted glass UI.
>
> **H2 Note:** PDF via CTFramesetter, HTML via AST walker, RTF via NSAttributedString, share menu, command palette integration.
>
> **H3 Note:** Secondary WindowGroup with EditorSession, NoteWindowRoot extraction, Cmd+Shift+O command, NSTableView selection highlight fix.
>
> **H4 Note:** Aesthetics & Typography Engine — custom font system, heading scale, paragraph spacing, syntax-theme palette, smooth spring animations, Reduce Motion support.

---

## Phase I: Vault Dashboard — **🚧 In Progress**

| Step | Deliverable | Status |
|------|------------|--------|
| I1 | Dashboard view with vault-level stats (note count, word count, recent activity) | 🚧 In Progress |
| I2 | Quick-access recent notes, pinned notes, and daily writing streak | Planned |
| I3 | Dashboard as optional home screen with user preference toggle | Planned |

> **Note:** Vault Dashboard provides a welcoming home screen with at-a-glance vault statistics, recent activity, and quick actions. User preference to show/hide via Settings.

---

## Architecture Summary

```
Quartz/                          App target (thin shell)
├── QuartzApp.swift              @main entry point
├── ContentView.swift            Sheet/alert routing via AppCoordinator
└── (648 lines total)

QuartzKit/                       Shared Swift Package
├── Domain/
│   ├── Editor/
│   │   ├── EditorSession.swift          Authoritative text buffer (no SwiftUI binding)
│   │   ├── MarkdownASTHighlighter.swift AST-based syntax highlighting
│   │   ├── MarkdownAnalysisService.swift Background heading + stats extraction
│   │   └── MarkdownListContinuation.swift List continuation on Enter
│   ├── Models/
│   │   ├── NoteListItem.swift           Middle column preview model
│   │   ├── NoteAnalysis.swift           Inspector data (headings, stats)
│   │   └── ...
│   └── Audio/
│       ├── AudioRecordingService.swift  AVAudioRecorder wrapper
│       ├── TranscriptionService.swift   SFSpeechRecognizer (on-device)
│       ├── SpeakerDiarizationService.swift K-Means clustering
│       └── MeetingMinutesService.swift  Transcription + AI → Markdown
├── Data/
│   ├── FileSystem/
│   │   ├── NotePreviewIndexer.swift     8KB bounded read + TaskGroup
│   │   ├── NotePreviewRepository.swift  JSON cache (.quartz/preview-cache.json)
│   │   └── ...
│   └── Markdown/
│       ├── SnippetExtractor.swift       Markdown → plain text (string-based, no Regex)
│       └── ...
└── Presentation/
    ├── Workspace/
    │   ├── WorkspaceView.swift          3-column NavigationSplitView shell
    │   └── WorkspaceStore.swift         Selection + column visibility state
    ├── NoteList/
    │   ├── NoteListSidebar.swift        Middle column (sectioned, searchable)
    │   ├── NoteListStore.swift          Filter/sort/search + NotificationCenter reactivity
    │   └── NoteListRow.swift            Title + timestamp + snippet + tags
    ├── Editor/
    │   ├── EditorContainerView.swift    SwiftUI host (toolbar, status bar, inspector)
    │   ├── MarkdownEditorRepresentable.swift Native bridge (updateUIView never writes text)
    │   ├── MacEditorToolbar.swift       macOS formatting toolbar
    │   └── iosFloatingToolbar.swift     iOS floating pill toolbar
    ├── Inspector/
    │   ├── InspectorSidebar.swift       ToC + stats + tags + metadata
    │   └── InspectorStore.swift         Heading tracking + scroll sync
    └── App/
        ├── AppCoordinator.swift         Centralized sheet/alert routing
        ├── ContentViewModel.swift       Vault loading + indexer orchestration
        └── ...
```

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Test suite | 563 tests, 0 regressions |
| ContentView | 648 lines (down from 1168) |
| Dead code removed | 520+ lines |
| Preview cache read | 8KB per file (not full file) |
| Highlight debounce | 80ms (typing), 0ms (formatting actions) |
| Analysis debounce | 300ms (inspector ToC + stats) |
| Scroll sync throttle | 100ms |
| Platforms | iOS 18+, iPadOS 18+, macOS 15+, visionOS 2+ |
