# Quartz

<p align="center">
  <strong>Your notes. Your files. Your way.</strong>
</p>

<p align="center">
  The sweet spot between Apple Notes, Obsidian, and modern AI — built natively for Apple.
</p>

<p align="center">
  <a href="https://github.com/Olli0103/Quartz/releases"><img src="https://img.shields.io/github/v/release/Olli0103/Quartz?style=for-the-badge" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License"></a>
  <a href="https://github.com/sponsors/Olli0103"><img src="https://img.shields.io/github/sponsors/Olli0103?style=for-the-badge&color=ea4aaa" alt="Sponsor"></a>
</p>

---

## Why Quartz?

**Quartz** is a native, open-source note-taking app for **iOS**, **iPadOS**, **macOS**, and **visionOS** that gives you the best of all worlds:

- **Apple Notes simplicity** — Clean, familiar interface. No learning curve.
- **Obsidian power** — Wiki-links, backlinks, tags, knowledge graphs. Your second brain.
- **Modern AI** — Chat with your notes, semantic vault search, writing tools. Bring your own API key.

Your notes live as **plain Markdown files** in any folder you choose. No vendor lock-in. No cloud account required. Full control over your data.

> **100% free and open source.** Funded by community support.

---

## ✨ Highlights

| | |
|---|---|
| **📝 Beautiful Markdown** | Raw markdown editing with syntax highlighting. Textual-powered preview with math, tables, code blocks. Export to PDF. |
| **🧠 Second Brain** | Wiki-links, backlinks, tags, full-text search. Interactive knowledge graph. |
| **🤖 AI-Powered** | Chat with notes or your entire vault. Summarize, rewrite, proofread. 5 providers including Ollama. |
| **🎙️ Audio & Transcription** | Record, transcribe on-device, auto-generate meeting minutes. |
| **✍️ Handwriting (iPad)** | PencilKit drawings with OCR — searchable handwriting. |
| **🔒 Privacy First** | Face ID / Touch ID lock. Optional AES-256 vault encryption. |
| **☁️ iCloud Ready** | Sync across devices. Conflict resolution. Download-on-demand. |
| **🌍 Localized** | English, German, French, Spanish, Italian, Chinese, Japanese. |
| **Apple-native** | Spotlight, Handoff, Quick Look, multi-window notes on Mac, accessibility polish. |

---

## Features

### Markdown Editor
- **Edit mode** — Raw markdown with syntax highlighting. All markers visible (`#`, `**`, `[ ]`, etc.)
- **Preview mode** — Rendered output via [Textual](https://github.com/gonzalezreal/textual). Math expressions (`$...$`), tables, code blocks
- Formatting toolbar: Bold, Italic, Headings, Lists, Checkboxes, Code, Links, Images, Math
- Inline image rendering & drag-and-drop
- YAML frontmatter with tag management
- Focus Mode & Typewriter Mode
- Auto-save, word count, reading time
- Keyboard shortcuts (⌘B, ⌘I, ⌘K, etc.)
- PDF export & system share sheet
- **macOS** — Editor formatting in the window toolbar; open a note in a **new window** from the sidebar

### Organization
- **Vault-based** — Each vault is a folder. Use iCloud, Dropbox, or local storage.
- **Folders** — Create, rename, move, delete. Drag & drop notes and folders. Sort by name, date modified, or date created.
- **Tags** — Inline `#tag` detection, tag overview with badges
- **Wiki-links** — `[[Note Name]]` with alias and anchor support
- **Backlinks** — See all notes linking to the current one
- **Full-text search** — Across titles, content, and tags
- **Favorites** — Star notes for quick access
- **Knowledge Graph** — Interactive force-directed graph (macOS)

### AI Integration
Bring your own API key where required. **Five** providers are supported, **including Ollama** for local models:

| Provider | Models |
|---------|--------|
| **OpenAI** | GPT-4o, GPT-4o Mini |
| **Anthropic** | Claude Opus, Sonnet, Haiku |
| **Google Gemini** | Gemini 2.5 Pro, Flash |
| **OpenRouter** | Claude, GPT-4o, Gemini, Llama, DeepSeek |
| **Ollama** | Local models — no API key needed |

**AI features:** Chat with Note, Chat with Vault (semantic search), Writing Tools (summarize, rewrite, proofread), Link Suggestions, Knowledge Graph.

### Audio & Transcription
- In-app recording with waveform
- On-device transcription (60+ languages)
- Meeting minutes with AI summaries
- Speaker diarization

### Security
- Face ID / Touch ID app lock
- AES-256-GCM vault encryption
- Biometric folder lock

### OS Integration
- **Share Extension** — Send content from any app to your vault
- **Mac Quick Note** — Global hotkey (⌥⌘N) for instant capture
- **Widgets** — Lock Screen, Home Screen, Control Center
- **App Intents** — Siri Shortcuts
- **Spotlight** — Vault notes indexed for system search (title, tags, excerpt, path)
- **Handoff** — Resume the current note session on another device
- **Quick Look** — Preview exported PDFs and files after save (iOS & macOS)
- **Accessibility** — VoiceOver custom actions on sidebar rows; Dynamic Type–friendly tags and chrome

### Design
- **Liquid Glass** — Glassmorphism with native materials on current iOS, iPadOS, and macOS
- **Themes** — Light, Dark, System
- **Accent colors** — Blue, Red, Green, Orange, Purple, Pink, Gray
- **Animations** — Spring transitions, reduce-motion support
- **Dynamic Type** — Respects system font size
- **RTL support** — Right-to-left layouts

---

## Architecture

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

- **Swift 6** — `@Observable`, actors, `Sendable`
- **Clean Architecture** — Data, Domain, Presentation
- **Protocol-first DI** — `ServiceContainer`
- **Filesystem as source of truth** — No database. Each note = `.md` file.

For maintainers, platform integration milestones and validation notes live in [`docs/Quartz_ADA_Final_Mile_Implementation_Plan.md`](docs/Quartz_ADA_Final_Mile_Implementation_Plan.md).

---

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS / iPadOS | 18.0 |
| macOS | 15.0 (Sequoia) |
| visionOS | 2.0 |
| Xcode | 16.0+ |
| Swift | 6.0 |

---

## Installation

### Download
Get the latest release from [GitHub Releases](https://github.com/Olli0103/Quartz/releases).

### Build from Source
```bash
git clone https://github.com/Olli0103/Quartz.git
cd Quartz
open Quartz.xcodeproj
```

`QuartzKit` is a local Swift Package. Key dependencies: [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple), [Textual](https://github.com/gonzalezreal/textual) (markdown preview rendering).

### Use QuartzKit as a Package
```swift
dependencies: [
    .package(url: "https://github.com/Olli0103/Quartz.git", from: "1.0.0"),
]
```

---

## AI Setup

1. Open **Settings** → **AI**
2. Select a provider and enter your API key
3. For Ollama: enter server URL and test connection

API keys are stored in the system Keychain.

---

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a Pull Request

---

## Support the Project

Quartz is free and open source. If it helps you, consider supporting development:

- **[GitHub Sponsors](https://github.com/sponsors/Olli0103)** — Monthly or one-time support
- **Star the repo** — Helps others discover Quartz

---

## License

MIT License — see [LICENSE](LICENSE) for details.
