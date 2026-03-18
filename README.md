# Quartz

**The sweet spot between Apple Notes, Obsidian, and modern AI.**

Quartz is a native, open-source note-taking app for iOS, iPadOS, and macOS. Built with SwiftUI and Clean Architecture. Notes are stored as plain Markdown files – no vendor lock-in, full control over your data.

> **100% Free & Open Source.** Funded by community donations.

[![GitHub release](https://img.shields.io/github/v/release/Olli0103/Quartz?style=flat-square)](https://github.com/Olli0103/Quartz/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/Olli0103?style=flat-square&color=ea4aaa)](https://github.com/sponsors/Olli0103)

---

## Features

### Markdown Editor
- WYSIWYG editing with TextKit 2 – looks like Apple Notes, stores pure Markdown
- Formatting toolbar: Bold, Italic, Headings, Lists, Checkboxes, Code, Links, Images
- **Inline image rendering** – images displayed directly in the editor
- YAML frontmatter editor with tag management
- Focus Mode & Typewriter Mode for distraction-free writing
- Auto-save with visual indicator
- Word count & reading time in status bar
- Keyboard shortcuts (Cmd+B, Cmd+I, Cmd+K, etc.)
- PDF export and system share sheet

### Organization
- **Vault-based:** Each vault is a folder on the filesystem
- **Folder management:** Create, rename, move, delete via drag & drop
- **Tags:** Inline `#tag` detection, tag overview with color codes and badges
- **Wiki-links:** `[[Note Name]]` with alias and anchor support
- **Backlinks:** Panel showing all notes linking to the current note
- **Full-text search:** Spotlight-style search across titles, content, and tags
- **Favorites:** Star notes for quick access
- **Knowledge Graph:** Interactive force-directed graph visualization of note connections

### AI Integration
5 providers supported – bring your own API key:

| Provider | Built-in Models |
|---|---|
| **OpenAI** | GPT-4o, GPT-4o Mini |
| **Anthropic** | Claude Opus 4.6, Claude Sonnet 4.6, Claude Haiku 4.5 |
| **Google Gemini** | Gemini 2.5 Pro, Gemini 2.5 Flash, Gemini 2.0 Flash |
| **OpenRouter** | Claude Sonnet 4, GPT-4o, Gemini 2.5 Pro, Llama 4, DeepSeek R1 |
| **Ollama (Local)** | Auto-detected models – no API key needed |

AI Features:
- **Chat with Note** – discuss the current note with AI
- **Chat with Vault** – semantic search across all notes using vector embeddings
- **Writing Tools** – Summarize, Rewrite, Proofread, Change Tone (AI-powered with on-device NLP fallback)
- **Link Suggestions** – AI-assisted wiki-link recommendations
- **Knowledge Graph** – visualize connections between notes
- **Ollama auto-detection** with health check and model listing
- Custom models per provider; API keys stored securely in Keychain

### Audio & Transcription
- In-app audio recording with waveform visualization
- On-device transcription (Speech framework)
- Automatic meeting minutes with AI-generated summaries
- Speaker diarization (speaker identification)

### Handwriting (iPad)
- PencilKit integration inline in the Markdown editor
- Background OCR: handwriting automatically converted to searchable text
- OCR text stored in frontmatter (searchable but invisible)

### Security
- FaceID / TouchID App Lock
- AES-256-GCM vault encryption (CryptoKit)
- Biometric folder lock for sensitive areas

### Sync & Cloud
- iCloud Drive sync with real-time status indicator
- Conflict resolution
- Download-on-demand for large vaults

### OS Integration
- **Share Extension:** Send content from any app to your vault
- **Mac Quick Note:** Global hotkey (⌥⌘N) for instant note capture
- **Widgets:** Lock Screen, Home Screen, and Control Center
- **App Intents:** Siri Shortcuts for quick access

### Apple Notes Import
- Import from exported Apple Notes (TXT, HTML, RTF, MD)
- Preserves folder structure recursively
- Automatic frontmatter generation

### Design
- **Liquid Glass** design system with glassmorphism effects
- Amber accent color throughout
- Animations: Staggered Lists, Bounce-In, Shimmer, Spring Transitions
- Themes: Light, Dark, System
- Dynamic Type support
- Localization: German & English

### Auto-Update
- Automatic update checks via GitHub Releases
- One-click download of new versions

---

## Architecture

### Clean Architecture

```
┌─────────────────────────────────────┐
│           Presentation              │
│     (SwiftUI Views, ViewModels)     │
├─────────────────────────────────────┤
│             Domain                  │
│   (Protocols, Models, Use Cases)    │
├─────────────────────────────────────┤
│              Data                   │
│ (FileSystem, Markdown, AI, Sync)    │
└─────────────────────────────────────┘
```

- **MVVM** with `@Observable` ViewModels (Swift Observation Framework)
- **Protocol-first Dependency Injection** via `ServiceContainer`
- **Actor-based Concurrency** for thread-safe file I/O
- **Adapter Pattern** for AI providers
- **Feature Flag System** with `FeatureGating` protocol (all features free)

### Data Model

- **Filesystem as single source of truth** – no database
- Each note = a `.md` file with YAML frontmatter
- In-memory FileIndex for fast navigation
- Vector index in `.quartz/embeddings.idx`

---

## Requirements

| Requirement | Minimum |
|---|---|
| iOS / iPadOS | 18.0 |
| macOS | 15.0 (Sequoia) |
| Xcode | 16.0+ |
| Swift | 6.0 |

---

## Installation

### Download

Download the latest release from [GitHub Releases](https://github.com/Olli0103/Quartz/releases).

### Build from Source

```bash
git clone https://github.com/Olli0103/Quartz.git
cd Quartz
open Quartz.xcodeproj
```

`QuartzKit` is resolved as a local Swift Package. The only external dependency is [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple).

### Use QuartzKit as a Package

```swift
dependencies: [
    .package(url: "https://github.com/Olli0103/Quartz.git", from: "1.0.0"),
]
```

---

## Tests

```bash
xcodebuild test -scheme QuartzKit -destination 'platform=macOS'
```

---

## AI Provider Setup

1. Open **Settings** in the app
2. Navigate to **AI**
3. Select a provider and enter your API key
4. For Ollama: enter the server URL and test the connection

API keys are stored exclusively in the system Keychain.

---

## Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions workflow will automatically build the macOS app, create a DMG, and publish a GitHub Release.

---

## License

MIT License – see [LICENSE](LICENSE) for details.

---

## Support & Donations

Quartz is free and open-source. If you find it useful, consider supporting development:

- [GitHub Sponsors](https://github.com/sponsors/Olli0103)
- Star the repo to help others find it

---

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Create a Pull Request

Please follow the existing code style and architecture patterns.
