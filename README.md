# Quartz

**Der Sweet Spot zwischen Apple Notes, Obsidian und moderner KI.**

Quartz ist eine native Notiz-App fuer iOS, iPadOS und macOS, gebaut mit SwiftUI und Clean Architecture. Notizen werden als Markdown-Dateien gespeichert – kein Vendor-Lock-in, volle Kontrolle ueber deine Daten.

> **OpenCore-Modell:** Der Kern (`QuartzKit`) ist Open Source. Die Pro-Version gibt es als Einmalkauf im App Store.

---

## Features

### Markdown-Editor
- WYSIWYG-Editing mit TextKit 2 – sieht aus wie Apple Notes, speichert reines Markdown
- Formatierungs-Toolbar: Bold, Italic, Headings, Listen, Checkboxen, Code, Links, Bilder
- YAML-Frontmatter-Editor mit Tag-Management
- Fokus-Modus & Typewriter-Modus fuer ablenkungsfreies Schreiben
- Auto-Save mit visueller Speicher-Anzeige
- Wortanzahl-Statistik in der Statusleiste

### Organisation
- **Vault-basiert:** Jeder Vault ist ein Ordner auf dem Dateisystem
- **Ordner-Management:** Erstellen, Umbenennen, Verschieben, Loeschen per Drag & Drop
- **Tags:** Inline `#tag`-Erkennung, Tag-Uebersicht mit Farbcodes und Zaehler-Badges
- **Wiki-Links:** `[[Notiz-Name]]` mit Alias- und Anker-Support
- **Backlinks:** Panel zeigt alle Notizen, die auf die aktuelle Notiz verlinken
- **Volltext-Suche:** Spotlight-aehnliche Suche ueber Titel, Inhalt und Tags

### KI-Integration
5 Provider werden unterstuetzt – du bringst deinen eigenen API-Key mit:

| Provider | Modelle (Built-in) |
|---|---|
| **OpenAI** | GPT-4o, GPT-4o Mini |
| **Anthropic** | Claude Opus 4.6, Claude Sonnet 4.6, Claude Haiku 4.5 |
| **Google Gemini** | Gemini 2.5 Pro, Gemini 2.5 Flash, Gemini 2.0 Flash |
| **OpenRouter** | Claude Sonnet 4, GPT-4o, Gemini 2.5 Pro, Llama 4 Maverick, DeepSeek R1, Mistral Large 2 |
| **Ollama (Lokal)** | Llama 3.1, Mistral, Gemma 2 – kein API-Key noetig |

**Custom Models:** Bei allen Providern koennen eigene Modelle per technischem Namen hinzugefuegt werden. Die benutzerdefinierten Modelle werden persistent gespeichert.

Weitere KI-Features:
- Chat mit einzelner Notiz (Notiz-Inhalt als Kontext)
- Vault-weite semantische Suche mit Vektor-Embeddings
- On-Device AI via Apple Intelligence (Zusammenfassen, Umschreiben)
- API-Keys werden sicher in der Keychain gespeichert

### Audio & Transkription
- In-App Audio-Aufnahme mit Wellenform-Visualisierung
- On-Device Transkription (Speech Framework / Whisper CoreML)
- Automatische Meeting-Protokolle mit Action Items
- Speaker Diarization (Sprechererkennung)

### Handschrift (iPad)
- PencilKit-Integration inline im Markdown-Editor
- Background-OCR: Handschrift wird automatisch zu durchsuchbarem Text
- OCR-Text im Frontmatter gespeichert (durchsuchbar, aber unsichtbar)

### Sicherheit
- FaceID / TouchID App-Lock
- AES-256-GCM Vault-Verschluesselung (CryptoKit)
- Biometrischer Ordner-Lock fuer sensible Bereiche

### Sync & Cloud
- iCloud Drive Sync mit Conflict Resolution
- WebDAV-Support
- Download-on-Demand fuer grosse Vaults

### OS-Integration
- **Share Extension:** Inhalte aus jeder App in den Vault senden
- **Mac Quick Note:** Globaler Hotkey fuer sofortige Notiz-Erfassung (Schwebefenster)
- **Widgets:** Lockscreen, Home Screen und Control Center
- **App Intents:** Siri-Shortcuts fuer schnellen Zugriff

### Design
- **Liquid Glass** Design-System mit Glassmorphismus-Effekten
- Animationen: Staggered Lists, Bounce-In, Shimmer Loading, Spring-Transitions, Parallax
- Themes: Hell, Dunkel, System (folgt Geraete-Einstellung)
- Dynamische Schriftgroesse (Dynamic Type)
- Lokalisierung: Deutsch & Englisch

### Onboarding
- Vault-Erstellung mit optionalen Strukturvorlagen
- Templates: PARA-Methode, Zettelkasten, Daily Notes, Meeting Notes
- Animierter Onboarding-Flow mit Template-Vorschau

---

## Architektur

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
│ (FileSystem, Markdown, AI, Sync)   │
└─────────────────────────────────────┘
```

- **MVVM** mit `@Observable` ViewModels (Swift Observation Framework)
- **Protocol-First Dependency Injection** ueber `ServiceContainer`
- **Actor-basierte Concurrency** fuer thread-sichere File-I/O
- **Adapter Pattern** fuer AI-Provider
- **Feature Flag System** mit `FeatureGating`-Protokoll (Features flexibel zwischen Free/Pro verschiebbar)

### Projektstruktur

```
Quartz/
├── QuartzApp/              # App Entry Point (iOS, iPadOS, macOS)
│   ├── QuartzApp.swift
│   ├── ContentView.swift
│   └── VaultPickerView.swift
│
├── QuartzKit/              # Open-Source Swift Package (MIT)
│   ├── Sources/QuartzKit/
│   │   ├── Domain/
│   │   │   ├── Models/         # FileNode, NoteDocument, Frontmatter, VaultConfig
│   │   │   ├── Protocols/      # VaultProviding, FrontmatterParsing, FeatureGating
│   │   │   ├── UseCases/       # CreateNote, DeleteNote, FolderManagement, Backlinks
│   │   │   ├── AI/             # AIProvider, NoteChatService, VaultChatService, Embeddings
│   │   │   ├── Audio/          # Recording, Transcription, MeetingMinutes, Diarization
│   │   │   ├── Security/       # BiometricAuth, VaultEncryption
│   │   │   └── OCR/            # HandwritingOCR, OCRFrontmatter
│   │   ├── Data/
│   │   │   ├── FileSystem/     # VaultProvider, FileWatcher, AssetManager, SearchIndex
│   │   │   ├── Markdown/       # Parser, Renderer, TagExtractor, WikiLinkExtractor
│   │   │   └── FeatureConfig/  # DefaultFeatureGate
│   │   └── Presentation/
│   │       ├── App/            # AppState, AppearanceManager, ServiceContainer, SearchView
│   │       ├── DesignSystem/   # LiquidGlass (Farben, Animationen, Komponenten)
│   │       ├── Sidebar/        # SidebarView, FileNodeRow, TagOverview
│   │       ├── Editor/         # NoteEditor, FormattingToolbar, Frontmatter, Backlinks
│   │       ├── Onboarding/     # OnboardingView mit Template-Auswahl
│   │       ├── Settings/       # SettingsView, AppearanceSettings
│   │       ├── Widgets/        # Home, Lockscreen, Control Center
│   │       ├── QuickNote/      # Mac Schwebefenster
│   │       └── ShareExtension/
│   └── Tests/QuartzKitTests/   # Unit Tests (96+ Tests)
│
└── QuartzPro/              # Closed Source – Pro Features
    └── ProFeatureGate.swift
```

### Datenmodell

- **Dateisystem als Single Source of Truth** – keine Datenbank
- Jede Notiz = eine `.md`-Datei mit YAML-Frontmatter
- In-Memory FileIndex fuer schnelle Navigation
- Vektor-Index in `.quartz/embeddings.idx`

---

## Voraussetzungen

| Anforderung | Minimum |
|---|---|
| iOS / iPadOS | 18.0 |
| macOS | 15.0 (Sequoia) |
| Xcode | 16.0+ |
| Swift | 6.0 |

---

## Installation & Setup

### Entwicklung

```bash
# Repository klonen
git clone https://github.com/Olli0103/Cortex.git
cd Cortex

# Xcode-Projekt oeffnen
open QuartzApp.xcodeproj
```

`QuartzKit` wird als lokales Swift Package automatisch aufgeloest. Die einzige externe Abhaengigkeit ist [swift-markdown](https://github.com/apple/swift-markdown) (Apple).

### QuartzKit als Package nutzen

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Olli0103/quartz-kit.git", from: "0.1.0"),
]
```

---

## Tests

```bash
# Tests ausfuehren (Xcode CLI)
xcodebuild test -scheme QuartzKit -destination 'platform=macOS'

# Oder in Xcode: Cmd+U
```

Abgedeckte Bereiche:
- Domain-Modelle (FileNode, NoteDocument, VaultConfig, Frontmatter, Feature)
- Tag-Extraktion (Inline-Tags, Code-Block-Ausschluss, Unicode)
- Wiki-Link-Extraktion (Aliase, Anker, Nested Brackets)
- Feature Gate (Free/Pro-Gating, Runtime-Aenderungen)
- Markdown-Formatierung (Bold, Italic, Headings, Listen, Code, Links)
- Volltext-Suche (Titel/Body/Tag-Match, Scoring, AND-Logik)
- ViewModels (SidebarVM, EditorVM, AppState)
- Frontmatter-Parser & Markdown-Renderer

---

## KI-Provider konfigurieren

1. Oeffne **Einstellungen** in der App
2. Navigiere zu **KI-Provider**
3. Waehle einen Provider und gib deinen API-Key ein
4. Optional: Fuege eigene Modelle per technischem Namen hinzu

Die API-Keys werden ausschliesslich in der System-Keychain gespeichert und nie im Klartext abgelegt.

---

## Lizenz

- **QuartzKit** (Open-Source-Kern): MIT License
- **QuartzApp** & **QuartzPro**: Proprietaer

---

## Mitwirken

Beitraege zum Open-Source-Kern (`QuartzKit`) sind willkommen! Bitte stelle PRs gegen das `quartz-kit` Repository.

1. Fork das Repository
2. Erstelle einen Feature-Branch (`git checkout -b feature/mein-feature`)
3. Committe deine Aenderungen
4. Erstelle einen Pull Request
