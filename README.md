# Quartz Notes

**The hybrid of Apple Notes and Obsidian -- simple, elegant, powerful.**

A premium native Apple markdown notes app built for daily writing, designed to feel like Apple made it.

![iOS 18+](https://img.shields.io/badge/iOS-18%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![iPadOS 18+](https://img.shields.io/badge/iPadOS-18%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![visionOS 2+](https://img.shields.io/badge/visionOS-2%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## Overview

Quartz Notes is a markdown-first notes app that combines the simplicity and native feel of Apple Notes with the power and flexibility of Obsidian. Every feature is built to meet **Apple Design Award** criteria -- innovation, delight, interaction quality, visual polish, and inclusivity.

Your notes live as **plain Markdown files** in any folder you choose. No proprietary database, no vendor lock-in, no cloud account required. Full control over your data.

**Key differentiators:**

- **Truly native** across all four Apple platforms -- not a web view, not a cross-platform wrapper. SwiftUI and TextKit 2 from the ground up.
- **Folder-based vaults** stored as plain `.md` files on disk. Works with iCloud Drive, Dropbox, or local storage.
- **Privacy-first AI** with a tiered approach: system Writing Tools for free, on-device Foundation Models for summarization, and user-supplied API keys for cloud AI. No data leaves your device without explicit consent.
- **Accessible by default** -- VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency, and Full Keyboard Access are core requirements, not afterthoughts.

> **100% free and open source.** Funded by [community support](https://github.com/sponsors/Olli0103).

---

## Screenshots

<!-- screenshots -->
<!-- Add screenshots here: light/dark mode, editor, dashboard, sidebar, graph view -->
<!-- Recommended layout: one hero shot + a 2x3 grid of feature highlights -->
<!-- screenshots -->

---

## Features

### Editor

- **TextKit 2 engine** -- Flicker-free AST-based syntax highlighting with stable cursor position, preserved selection, and proper typing attributes.
- **Live Markdown rendering** -- Headings, bold, italic, code, links, blockquotes, and math expressions styled in real time as you type.
- **Intelligent list continuation** -- Press Enter in a list and the next item is created automatically. Empty items remove the marker.
- **Formatting toolbar** -- Platform-native toolbars (macOS menu bar + toolbar buttons, iOS floating pill) with active state indicators for bold, italic, heading level, and more.
- **Surgical editing** -- External mutations (AI insertion, iCloud merge, list continuation) go through `NSTextStorage.replaceCharacters` for proper undo registration and minimal layout invalidation. SwiftUI never writes back to the text view.
- **Inspector sidebar** -- Table of contents, word/character/reading time stats, heading outline with scroll sync, tags, and frontmatter metadata.
- **Focus mode** -- Distraction-free writing that hides chrome and centers your text.
- **Multi-window support** -- Open notes in separate windows on macOS with independent editor sessions.
- **Keyboard shortcuts** -- Full shortcut support including bold, italic, link, headings, and more.

### Dashboard

- **Vault statistics** -- Note count, folder count, and open task count at a glance.
- **Quick capture** -- Type a thought and press Enter to append it to your Daily Note instantly.
- **AI briefing** -- A generated summary of your recent writing activity, surfacing themes and patterns across your vault.
- **Serendipity** -- Resurfaces a random note from your vault, with "On This Day" priority for notes modified exactly a year ago.
- **Action items** -- Aggregates open `- [ ]` tasks from recent notes with one-tap completion that writes back to the source file.
- **Activity heatmap** -- A 26-week contribution-style heatmap showing your editing momentum over time.
- **Recent notes** -- Quick access to your eight most recently modified notes.

### Vault Management

- **Folder-based vaults** -- Plain Markdown files on the filesystem. Open any folder as a vault.
- **iCloud Drive sync** -- Automatic sync with conflict resolution, vault migration, and download-on-demand support.
- **Backup and restore** -- Full vault backup engine for data safety.
- **Security-scoped bookmarks** -- Persistent access to user-selected folders across app launches (macOS sandboxing).
- **File watching** -- Real-time detection of external changes to vault contents.
- **Drag and drop** -- Move notes and folders with native drag-and-drop in the sidebar.

### AI Integration

Five providers are supported, **including Ollama for fully local models**:

| Provider | Models |
|----------|--------|
| **OpenAI** | GPT-4o, GPT-4o Mini |
| **Anthropic** | Claude Opus, Sonnet, Haiku |
| **Google Gemini** | Gemini 2.5 Pro, Flash |
| **OpenRouter** | Claude, GPT-4o, Gemini, Llama, DeepSeek |
| **Ollama** | Local models -- no API key needed |

**Capabilities:**

- **Document chat** -- Ask questions about the active note with SSE streaming responses, 30fps token batching, and inline citations.
- **Vault RAG** -- Query your entire vault using vector embeddings with NLEmbedding, JIT indexing, streaming citations, and clickable source cards.
- **Writing Tools** -- Native iOS 18.1+ Writing Tools integration (system-provided, free).
- **Inline AI assistant** -- Quick AI actions and custom prompts with surgical text replacement.
- **Privacy-first** -- On-device processing preferred. Cloud AI requires user-supplied API keys stored in the system Keychain. No data retention.

### Design

- **Liquid Glass materials** -- Frosted glass panes using `regularMaterial` that respect Reduce Transparency preferences, falling back to solid backgrounds for accessibility.
- **Pure dark mode** -- True black background option for OLED displays.
- **Vibrant transparency** -- Configurable glass effects on sidebar and title bar.
- **Custom typography** -- Four font families (System/SF Pro, Serif/New York, Monospaced/SF Mono, Rounded/SF Rounded), adjustable size (12--24pt), line spacing (1.0--2.5x), and column width (400--1200pt).
- **Accent color** -- User-configurable tint across the entire interface.
- **Spring animations** -- Physics-based motion with Reduce Motion support throughout.
- **Command palette** -- Cmd+K spotlight-style fuzzy search with command registry, keyboard navigation, and frosted glass UI.

### Export

- **PDF** -- High-fidelity export via `CTFramesetter` with precise typographic control.
- **HTML** -- Clean semantic export via AST walker.
- **RTF** -- Rich text export via `NSAttributedString`.
- **Markdown** -- Plain text share for interoperability.
- **Share menu integration** -- Export from the system share sheet or the command palette.

### Accessibility

- **VoiceOver** -- All elements labeled with logical focus order and custom actions on sidebar rows.
- **Voice Control** -- All actions are speakable.
- **Full Keyboard Access** -- Complete tab navigation and keyboard shortcuts.
- **Dynamic Type** -- All text scales with layout adaptation at every size.
- **Reduce Motion** -- All animations respect the system preference.
- **Reduce Transparency** -- Glass materials gracefully degrade to solid backgrounds with visible borders.
- **Increase Contrast** -- Sufficient color contrast ratios with adaptive stroke widths.

---

## Architecture

Quartz follows a **clean architecture** pattern with three layers, packaged as a Swift Package (`QuartzKit`) consumed by a thin app shell:

```
┌─────────────────────────────────────────────────────┐
│                   Presentation                       │
│   SwiftUI Views, @Observable ViewModels,             │
│   Platform Representables (UIKit / AppKit)            │
├─────────────────────────────────────────────────────┤
│                      Domain                          │
│   Models, Use Cases, Editor Logic,                   │
│   AI Services, Export Pipelines, Audio               │
├─────────────────────────────────────────────────────┤
│                       Data                           │
│   File System (VaultProvider, FileWatcher),           │
│   Markdown (Parser, Renderer, Frontmatter),          │
│   AI Providers, Security                             │
└─────────────────────────────────────────────────────┘
```

**Key types:**

| Type | Role |
|------|------|
| `EditorSession` | Authoritative text buffer per open note. The native text view is source of truth -- SwiftUI never writes back. |
| `WorkspaceStore` | Manages 3-column `NavigationSplitView` state, selection, and column visibility. |
| `AppCoordinator` | Centralized sheet/alert routing, replacing scattered `@State` booleans. |
| `MarkdownASTHighlighter` | AST-based syntax highlighting via swift-markdown with 80ms debounced re-parsing. |
| `NotePreviewIndexer` | Bounded 8KB reads with `TaskGroup` for fast vault indexing. |
| `AppearanceManager` | Persisted appearance settings (theme, font, spacing, accent color) via `@Observable` and `UserDefaults`. |

---

## Tech Stack

| Technology | Purpose |
|------------|---------|
| **Swift 6** | Strict concurrency with `@Sendable`, `@MainActor`, actors, and structured concurrency. |
| **SwiftUI** | All UI with `@Observable` ViewModels, `NavigationSplitView`, and platform-adaptive layouts. |
| **TextKit 2** | Editor engine -- `NSTextContentStorage`, `NSTextLayoutManager`, `UITextView` / `NSTextView`. |
| **swift-markdown** | AST parsing for syntax highlighting, heading extraction, and export pipelines. |
| **Textual** | Markdown preview rendering. |
| **NLEmbedding** | On-device vector embeddings for vault-level semantic search (RAG). |
| **CoreText** | `CTFramesetter`-based PDF export with precise typographic control. |
| **AVFoundation** | Audio recording for voice notes with waveform visualization. |
| **Speech** | On-device transcription via `SFSpeechRecognizer` with speaker diarization. |

---

## Getting Started

### Prerequisites

- **Xcode 16+** (Swift 6 toolchain)
- **macOS 15 Sequoia** or later (build host)
- An Apple Developer account (for on-device testing)

### Build from Source

```bash
git clone https://github.com/Olli0103/Quartz.git
cd Quartz
open Quartz.xcodeproj
```

Select a target scheme and run:

| Scheme | Platform |
|--------|----------|
| Quartz (iOS) | iPhone / iPad Simulator or device |
| Quartz (macOS) | Mac (native) |
| Quartz (visionOS) | Apple Vision Pro Simulator or device |

The `QuartzKit` Swift Package is resolved automatically by Xcode -- no manual dependency installation required.

### AI Setup

1. Open **Settings** > **AI**
2. Select a provider and enter your API key
3. For Ollama: enter the server URL and test the connection

API keys are stored in the system Keychain.

---

## Project Structure

```
Quartz/                                     App target (thin shell)
├── QuartzApp.swift                         @main entry point
├── ContentView.swift                       NavigationSplitView + AppCoordinator routing
├── VaultPickerView.swift                   Vault selection UI
├── NoteWindowRoot.swift                    Multi-window note editor (macOS)
├── Assets.xcassets                         App icons and color assets
└── Localizable.xcstrings                   Localization strings

QuartzKit/                                  Shared Swift Package
└── Sources/QuartzKit/
    ├── Data/
    │   ├── AI/                             AI provider adapters and API clients
    │   ├── FeatureConfig/                  Feature flags and runtime configuration
    │   ├── FileSystem/                     VaultProvider, FileWatcher, preview indexer/cache
    │   ├── Markdown/                       Parser, renderer, snippet extractor, frontmatter
    │   └── Security/                       Security-scoped bookmarks, Keychain access
    ├── Domain/
    │   ├── AI/                             Chat, embeddings, RAG pipeline, Writing Tools
    │   ├── Audio/                          Recording, transcription, speaker diarization
    │   ├── CommandPalette/                 Command registry and fuzzy search engine
    │   ├── Dashboard/                      Briefing service, task aggregation, heatmap data
    │   ├── Editor/                         EditorSession, AST highlighter, list continuation
    │   ├── Export/                         PDF, HTML, RTF export pipelines
    │   ├── Models/                         FileNode, NoteDocument, NoteListItem, NoteAnalysis
    │   ├── OCR/                            Image text extraction
    │   ├── Protocols/                      Shared protocol definitions
    │   ├── Security/                       Vault security policies
    │   └── UseCases/                       Create, delete, move, rename, backlinks
    ├── Presentation/
    │   ├── App/                            AppCoordinator, ContentViewModel, AppearanceManager
    │   ├── Audio/                          Voice note and meeting recording UI
    │   ├── Chat/                           Document and vault chat views
    │   ├── CommandPalette/                 Cmd+K overlay with frosted glass
    │   ├── Conflict/                       iCloud conflict resolution UI
    │   ├── Dashboard/                      Vault dashboard with stats, heatmap, quick capture
    │   ├── DesignSystem/                   Liquid Glass, QuartzColors, animations, typography
    │   ├── Editor/                         MarkdownTextView, toolbars, representables
    │   ├── Graph/                          Knowledge graph visualization
    │   ├── Inspector/                      ToC, stats, tags, metadata sidebar
    │   ├── NoteList/                       Middle column (sectioned, searchable, time-bucketed)
    │   ├── Onboarding/                     First-launch experience
    │   ├── QuickLook/                      File previews
    │   ├── QuickNote/                      Rapid capture (global hotkey on macOS)
    │   ├── Settings/                       Preferences panels (Appearance, AI, Data & Sync)
    │   ├── ShareExtension/                 System share sheet integration
    │   ├── Sidebar/                        File tree with drag-drop and VoiceOver actions
    │   ├── Widgets/                        Home Screen, Lock Screen, Control Center widgets
    │   └── Workspace/                      3-column NavigationSplitView shell
    └── Resources/                          Localizations and bundled assets
```

---

## Contributing

Contributions are welcome. Please follow these guidelines:

1. **Research first** -- Verify Apple documentation before implementing platform-specific behavior. Do not guess at TextKit 2, SwiftUI List selection, or drag-and-drop semantics.
2. **Accessibility is non-negotiable** -- Every feature must work with VoiceOver, Dynamic Type, and Full Keyboard Access before it ships.
3. **Platform fidelity** -- Test on iOS, iPadOS, macOS, and visionOS. Respect each platform's interaction patterns.
4. **Correctness over flash** -- If there is tension between a visually impressive approach and a correct one, choose correct.

Open an issue to discuss significant changes before submitting a pull request.

---

## Support the Project

Quartz is free and open source. If it helps you, consider supporting development:

- **[GitHub Sponsors](https://github.com/sponsors/Olli0103)** -- Monthly or one-time support
- **Star the repo** -- Helps others discover Quartz

---

## License

MIT License -- see [LICENSE](LICENSE) for details.
