# Quartz – Master Architektur & Entwicklungs-Plan

> **Version:** 0.2 · **Datum:** 2026-03-13
> **Ziel:** Der Sweet Spot zwischen Apple Notes, Obsidian und moderner KI.
> **Modell:** OpenCore – Open-Source-Kern auf GitHub, polierte Pro-Version als Einmalkauf im App Store.
> **Projektname:** Quartz (alle Xcode-Targets, Namespaces und Bundle-IDs verwenden diesen Namen)

---

## Inhaltsverzeichnis

1. [Architektur-Entscheidungen](#1-architektur-entscheidungen)
2. [OpenCore-Strategie im Repository](#2-opencore-strategie-im-repository)
3. [Framework-Mapping](#3-framework-mapping)
4. [Datenstrukturen & Modelle](#4-datenstrukturen--modelle)
5. [Dateiformat-Spezifikation](#5-dateiformat-spezifikation)
6. [Entwicklungs-Phasen (Sprints)](#6-entwicklungs-phasen-sprints)
7. [Risiken & offene Entscheidungen](#7-risiken--offene-entscheidungen)

---

## 1. Architektur-Entscheidungen

### 1.1 Schichtenmodell (Clean Architecture)

```
┌─────────────────────────────────────────────────┐
│                 Presentation                     │
│          (SwiftUI Views, ViewModels)             │
├─────────────────────────────────────────────────┤
│                   Domain                         │
│     (Protocols, Models, Use Cases, keine         │
│      Framework-Abhängigkeiten)                   │
├─────────────────────────────────────────────────┤
│                    Data                          │
│   (FileSystem-Service, iCloud-Adapter,           │
│    Markdown-Parser, AI-Provider)                 │
└─────────────────────────────────────────────────┘
```

| Schicht | Verantwortung | Beispiel |
|---|---|---|
| **Presentation** | UI, User-Interaktion, State Binding | `NoteEditorView`, `SidebarView` |
| **Domain** | Geschäftslogik, Modelle, Protokolle | `NoteDocument`, `VaultService`-Protocol |
| **Data** | Konkrete Implementierungen, I/O | `FileSystemVaultProvider`, `ICloudSyncAdapter` |

### 1.2 State Management

- **`@Observable` (Observation-Framework, Swift 5.9+/6)** als primärer Mechanismus.
- ViewModels sind `@Observable class`-Instanzen – kein `ObservableObject`/`@Published` Legacy.
- App-weiter State über einen `AppState`-Singleton, der per Environment injiziert wird.

### 1.3 Dependency Injection

- **Protocol-First**: Jeder Service wird über ein Protocol definiert (z.B. `VaultProviding`).
- Konkrete Implementierungen werden über einen leichtgewichtigen `ServiceContainer` registriert.
- Kein Third-Party-DI-Framework – reines Swift.

### 1.4 Concurrency

- **Swift Structured Concurrency** durchgängig (`async/await`, `TaskGroup`, `AsyncSequence`).
- File-I/O wird in dedizierten `Actor`-Isolations-Kontexten ausgeführt.
- `@MainActor` nur auf Presentation-Schicht.

### 1.5 Appearance & Lokalisierung

- **Theme**: Nutzer wählt zwischen Hell, Dunkel und System (folgt `colorScheme`). Gespeichert in `UserDefaults` via `AppearanceManager`.
- **Sprache**: Vollständige Lokalisierung via **String Catalogs** (`.xcstrings`, Xcode 15+). Startsprachen: Deutsch, Englisch. Weitere Sprachen einfach erweiterbar.
- **Schriftgröße**: Respektiert Dynamic Type von iOS/macOS. Optionaler Custom-Slider für Editor-Schriftgröße.
- **App-Icon**: Alternatives App-Icon wählbar in den Einstellungen.
- Alle Appearance-Einstellungen gebündelt in `AppearanceSettingsView` unter Settings.

### 1.6 Dateisystem als Single Source of Truth

- **Keine SQLite/CoreData-Datenbank** für Notiz-Inhalte.
- Jede Notiz = eine `.md` Datei auf der Festplatte.
- Metadaten (Tags, Erstelldatum, Links) leben im YAML-Frontmatter der Datei.
- Ein In-Memory-Index (`FileIndex`) wird beim Öffnen des Vaults aufgebaut und bei Änderungen inkrementell aktualisiert.

---

## 2. OpenCore-Strategie im Repository

### 2.1 Xcode-Projekt-Struktur

```
Quartz/
├── QuartzApp/                      # App Entry Point (Universal: iOS, iPadOS, macOS)
│   ├── QuartzApp.swift
│   ├── Assets.xcassets
│   └── Info.plist
│
├── QuartzKit/                      # 🔓 OPEN SOURCE – Swift Package (Core)
│   ├── Sources/
│   │   ├── Domain/
│   │   │   ├── Models/
│   │   │   │   ├── NoteDocument.swift
│   │   │   │   ├── FileNode.swift
│   │   │   │   ├── VaultConfig.swift
│   │   │   │   └── Frontmatter.swift
│   │   │   ├── Protocols/
│   │   │   │   ├── VaultProviding.swift
│   │   │   │   ├── MarkdownParsing.swift
│   │   │   │   └── AIProviding.swift
│   │   │   └── UseCases/
│   │   │       ├── CreateNoteUseCase.swift
│   │   │       ├── SearchVaultUseCase.swift
│   │   │       └── ...
│   │   │
│   │   ├── Data/
│   │   │   ├── FileSystem/
│   │   │   │   ├── FileSystemVaultProvider.swift
│   │   │   │   ├── ICloudSyncAdapter.swift
│   │   │   │   ├── FileWatcher.swift
│   │   │   │   └── FileCoordinator.swift
│   │   │   ├── Markdown/
│   │   │   │   ├── MarkdownParser.swift
│   │   │   │   ├── FrontmatterParser.swift
│   │   │   │   └── MarkdownRenderer.swift
│   │   │   ├── AI/
│   │   │   │   ├── OnDeviceAIProvider.swift
│   │   │   │   ├── BYOKProvider.swift
│   │   │   │   └── EmbeddingService.swift
│   │   │   └── Security/
│   │   │       ├── BiometricService.swift
│   │   │       └── VaultEncryption.swift
│   │   │
│   │   └── Presentation/
│   │       ├── App/
│   │       │   ├── AppState.swift
│   │       │   ├── AppearanceManager.swift  # Dark/Light/System Theme
│   │       │   └── ServiceContainer.swift
│   │       ├── Sidebar/
│   │       │   ├── SidebarView.swift
│   │       │   └── SidebarViewModel.swift
│   │       ├── Editor/
│   │       │   ├── NoteEditorView.swift
│   │       │   ├── NoteEditorViewModel.swift
│   │       │   ├── MarkdownTextView.swift   # TextKit 2 basiert
│   │       │   └── FormattingToolbar.swift
│   │       ├── Onboarding/
│   │       │   └── OnboardingFlow.swift
│   │       └── Settings/
│   │           ├── SettingsView.swift
│   │           └── AppearanceSettingsView.swift
│   │
│   └── Tests/
│       ├── DomainTests/
│       ├── DataTests/
│       └── PresentationTests/
│
├── QuartzPro/                      # 🔒 CLOSED SOURCE – Pro Features (separates Target)
│   ├── ProFeatureGate.swift         # Feature-Flag-Logik
│   ├── AdvancedAI/
│   ├── MeetingMinutes/
│   └── AdvancedTemplates/
│
├── Extensions/                     # App Extensions
│   ├── ShareExtension/
│   ├── WidgetExtension/
│   └── QuickNoteExtension/         # macOS Schwebefenster
│
└── Resources/
    ├── Templates/                  # Onboarding-Vorlagen (PARA, Zettelkasten)
    └── Localization/               # String Catalogs (.xcstrings) für Mehrsprachigkeit
```

### 2.2 Target-Aufteilung

| Target | Lizenz | Inhalt |
|---|---|---|
| `QuartzKit` | MIT / Apache 2.0 | Domain-Modelle, FileSystem-Services, Markdown-Parser, Basis-UI |
| `QuartzPro` | Proprietär | Erweiterte KI, Meeting Minutes, Premium-Templates |
| `QuartzApp` | Proprietär | App-Shell, verbindet Core + Pro, App Store Build |
| `Extensions` | Proprietär | Share Extension, Widgets, Quick Note |

**QuartzKit** ist ein **Swift Package** innerhalb des Monorepos. Es kann unabhängig gebaut, getestet und als Open-Source-Paket veröffentlicht werden.

---

## 3. Framework-Mapping

### 3.1 Übersicht

| Feature | Primäres Framework | Sekundär / Hilfs-API | Notizen |
|---|---|---|---|
| **Universal App UI** | `SwiftUI` | `AppKit` (Mac-spezifisch), `UIKit` (Representables) | Liquid Glass ab iOS 26 / macOS 26 |
| **Markdown Rendering** | `TextKit 2` (`NSTextContentManager`) | `NSAttributedString`, `UITextView`/`NSTextView` via Representable | Eigener WYSIWYG-Renderer |
| **Markdown Parsing** | Eigener Parser auf Basis von `swift-markdown` (Apple) | `RegularExpression` (Swift 6) | Apple's `swift-markdown` ist Open Source und native |
| **Dateisystem (lokal)** | `FileManager` | `DispatchSource` / `FS Events` (Watcher) | Wrapped in einem async Actor |
| **iCloud Sync** | `NSMetadataQuery` | `NSFileCoordinator`, `UIDocument` | Conflict Resolution nötig |
| **WebDAV / Netzwerk** | `URLSession` | `Network.framework` (Connectivity) | WebDAV-Client als eigener Adapter |
| **Biometrie / Lock** | `LocalAuthentication` | `Keychain Services` | FaceID, TouchID, Passwort-Fallback |
| **Vault-Verschlüsselung** | `CryptoKit` | `Security.framework` | AES-256-GCM für Datei-Verschlüsselung |
| **Handschrift (Zeichnen)** | `PencilKit` | – | `PKCanvasView` als SwiftUI-Representable |
| **OCR (Handschrift → Text)** | `Vision` (`VNRecognizeTextRequest`) | – | Live-Text on-device |
| **Audio-Aufnahme** | `AVFoundation` (`AVAudioRecorder`) | `AVAudioSession` | System-Audio via `AVAudioEngine` |
| **Transkription** | `Speech` (`SFSpeechRecognizer`) | Optional: Whisper via CoreML | On-device, 60+ Sprachen |
| **Speaker Diarization** | `SoundAnalysis` + Custom CoreML | `CreateML` für Training | Komplexestes Feature |
| **On-Device AI** | Apple Intelligence APIs | `NaturalLanguage`, `CoreML` | Zusammenfassen, Umschreiben |
| **BYOK AI** | `URLSession` (REST) | `Foundation.JSONEncoder` | OpenAI/Anthropic/Gemini/Ollama APIs |
| **Vektor-Embeddings** | Native Apple Vector Search (iOS 18+ / macOS 15+) | `NaturalLanguage` (`NLEmbedding`), `CoreML` | Apple's native Vektor-Suche nutzen – keine externe DB |
| **Semantic Search** | Native Apple Vector Search APIs | `Accelerate` (Fallback Cosine Similarity) | Primär native APIs, eigene Implementierung nur als Fallback |
| **Share Extension** | `NSExtensionContext` | `SwiftUI` (Extension UI) | Speichert in Vault-Inbox |
| **Widgets** | `WidgetKit` | `AppIntents` | Lockscreen + Home Screen |
| **Mac Quick Note** | `AppKit` (`NSPanel`) | `NSEvent.addGlobalMonitorForEvents` | Globaler Hotkey → Schwebefenster |
| **Control Center** | `ControlWidget` (iOS 18+) | `AppIntents` | Schnellzugriff |
| **Appearance (Theme)** | `SwiftUI` (`colorScheme`, `preferredColorScheme`) | `UserDefaults` | Hell / Dunkel / System |
| **Lokalisierung** | String Catalogs (`.xcstrings`) | `Bundle`, `LocalizedStringKey` | Deutsch + Englisch als Start |
| **Onboarding Templates** | `FileManager` (Dateien kopieren) | `Bundle` (Template-Ressourcen) | PARA, Zettelkasten etc. |

### 3.2 Bewusste Nicht-Nutzung

| Nicht verwendet | Grund |
|---|---|
| CoreData / SwiftData | Notizen sind Markdown-Dateien, keine DB-Objekte |
| CloudKit | Wir nutzen iCloud Drive (Dateisystem), nicht CloudKit-Datenbanken |
| WebKit / WKWebView | Kein Web-basierter Markdown-Renderer – alles nativ via TextKit 2 |
| Third-Party Markdown-Libs | Apple's `swift-markdown` ist ausreichend und nativ |

---

## 4. Datenstrukturen & Modelle

### 4.1 `FileNode` – Vault-Baumstruktur

```
FileNode
├── id: UUID
├── name: String                    // Datei-/Ordnername
├── path: URL                       // Relativer Pfad im Vault
├── nodeType: NodeType              // .folder | .note | .asset | .canvas
├── children: [FileNode]?           // nil bei Dateien, [] bei leeren Ordnern
├── metadata: FileMetadata
│   ├── createdAt: Date
│   ├── modifiedAt: Date
│   ├── fileSize: Int64
│   └── isEncrypted: Bool
└── frontmatter: Frontmatter?       // Nur bei .note, lazy geladen
```

### 4.2 `NoteDocument` – Einzelne Notiz

```
NoteDocument
├── id: UUID
├── fileURL: URL                    // Absoluter Pfad
├── frontmatter: Frontmatter
├── body: String                    // Raw Markdown (ohne Frontmatter)
├── canvasData: Data?               // PencilKit-Zeichnung (serialisiert)
├── isDirty: Bool                   // Ungespeicherte Änderungen
└── lastSyncedAt: Date?
```

### 4.3 `Frontmatter` – YAML-Metadaten

```
Frontmatter
├── title: String?
├── tags: [String]                  // ["projekt", "meeting"]
├── aliases: [String]               // Alternative Namen für [[Links]]
├── createdAt: Date
├── modifiedAt: Date
├── template: String?               // "daily", "zettelkasten", "meeting"
├── ocrText: String?                // Erkannter Handschrifttext (unsichtbar)
├── linkedNotes: [String]           // Extrahierte [[wiki-links]]
├── customFields: [String: String]  // Erweiterbare Key-Value-Paare
└── isEncrypted: Bool
```

### 4.4 `VaultConfig` – Vault-Konfiguration

```
VaultConfig
├── id: UUID
├── name: String                    // "Mein Vault"
├── rootURL: URL                    // Speicherort
├── storageType: StorageType        // .local | .iCloudDrive | .webdav | .onedrive | .gdrive
├── isDefault: Bool
├── encryptionEnabled: Bool
├── encryptionKeyRef: String?       // Keychain-Referenz
├── templateStructure: VaultTemplate? // .para | .zettelkasten | .custom | nil
├── createdAt: Date
└── syncConfig: SyncConfig?
    ├── webdavURL: URL?
    ├── credentials: KeychainRef?
    └── syncInterval: TimeInterval
```

### 4.5 `EmbeddingEntry` – Vektor-Index

```
EmbeddingEntry
├── noteID: UUID
├── chunkIndex: Int                 // Position im Dokument
├── chunkText: String               // Originaler Text-Chunk (~512 Tokens)
├── embedding: [Float]              // Vektor (z.B. 512 Dimensionen)
└── lastUpdated: Date
```

Der **Embedding-Index** wird als binäre Datei im Vault gespeichert (`.quartz/embeddings.idx`) und beim Start in den Speicher geladen. Updates erfolgen inkrementell bei Dateiänderungen. Ab iOS 18+ / macOS 15+ werden bevorzugt die **nativen Apple Vector Search APIs** genutzt; der eigene Index dient als Fallback.

---

## 5. Dateiformat-Spezifikation

### 5.1 Notiz-Datei (`.md`)

```markdown
---
title: Meeting mit Design-Team
tags: [meeting, design, q1]
aliases: [Design-Meeting]
created: 2026-03-13T10:30:00+01:00
modified: 2026-03-13T11:45:00+01:00
template: meeting
ocr_text: ""
---

# Meeting mit Design-Team

## Teilnehmer
- Anna, Ben, Clara

## Notizen
Das Design für den **Editor** wurde finalisiert.

![[sketch-editor.png]]

## Action Items
- [ ] Anna: Mockups bis Freitag
- [ ] Ben: TextKit 2 Prototyp
```

### 5.2 Vault-Struktur (Beispiel: PARA)

```
MeinVault/
├── .quartz/                        # Versteckter App-Config-Ordner
│   ├── vault.json                  # VaultConfig
│   ├── embeddings.idx              # Vektor-Index (binär)
│   └── cache/                      # Thumbnails, Render-Cache
│
├── 1 - Projects/
│   └── App-Redesign/
│       ├── Briefing.md
│       └── assets/
│           └── mockup-v2.png
│
├── 2 - Areas/
│   ├── Gesundheit/
│   └── Finanzen/
│
├── 3 - Resources/
│   └── Swift-Snippets/
│
├── 4 - Archives/
│
├── Daily Notes/
│   ├── 2026-03-13-Daily.md
│   └── 2026-03-12-Daily.md
│
└── Templates/
    ├── daily.md
    ├── meeting.md
    └── zettelkasten.md
```

### 5.3 Asset-Management

- Bilder, die in eine Notiz eingefügt werden, landen in einem `assets/`-Unterordner relativ zur Notiz.
- Der Markdown-Link nutzt relative Pfade: `![Beschreibung](assets/bild.png)` oder Obsidian-Syntax `![[bild.png]]`.
- PencilKit-Zeichnungen werden als `.drawing`-Dateien im gleichen `assets/`-Ordner gespeichert und im Frontmatter referenziert.

---

## 6. Entwicklungs-Phasen (Sprints)

### Phase 1: Foundation (Wochen 1–3)

Das Fundament: Projekt-Setup, Dateisystem-Service und grundlegende Navigation.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 1.1 | **Xcode-Projekt & Package-Struktur** | Multi-Platform App Target + `QuartzKit` Swift Package erstellen. Ordnerstruktur wie in Abschnitt 2.1. Bundle-ID: `com.quartz.app`. | Baubares Projekt, alle Targets verlinkt |
| 1.2 | **Domain-Modelle definieren** | `FileNode`, `NoteDocument`, `Frontmatter`, `VaultConfig` als Swift-Structs. Protocols für Services. | Kompilierbare Modelle mit Unit Tests |
| 1.3 | **FileSystem-Service (lokal)** | `FileSystemVaultProvider`: Vault öffnen, Dateibaum lesen, Dateien erstellen/löschen/umbenennen. Actor-basiert. | CRUD auf Dateisystem funktioniert |
| 1.4 | **YAML-Frontmatter-Parser** | Frontmatter aus `.md` Dateien lesen und schreiben. Round-Trip-fähig (Body bleibt unverändert). | Parser mit Tests für Edge Cases |
| 1.5 | **Vault-Auswahl & Sidebar-UI** | Grundlegende SwiftUI-Navigation: Vault öffnen via Folder-Picker, Dateibaum in Sidebar anzeigen. | Navigierbare Sidebar auf iOS + Mac |
| 1.6 | **Einfacher Plaintext-Editor** | `TextEditor` als Platzhalter zum Bearbeiten von `.md` Dateien. Autosave. | Notizen öffnen, bearbeiten, speichern |
| 1.7 | **Appearance & Lokalisierung** | `AppearanceManager` (Hell/Dunkel/System), String Catalogs (`.xcstrings`) für DE + EN, Dynamic Type Support. `AppearanceSettingsView` in Settings. | Theme-Wechsel + zweisprachige App |

**Phase 1 Ergebnis:** Eine funktionierende (aber rudimentäre) App, die einen lokalen Ordner als Vault öffnet, Markdown-Dateien anzeigt und bearbeiten kann.

---

### Phase 2: Editor (Wochen 4–7)

Der Kern: WYSIWYG-Markdown-Editor mit TextKit 2.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 2.1 | **Markdown-Parser (AST)** | `swift-markdown` integrieren. Markdown-String → AST → AttributedString-Pipeline. | Parser liefert typisierte Nodes |
| 2.2 | **TextKit 2 WYSIWYG-Renderer** | Custom `NSTextContentStorage` + `NSTextLayoutManager`. Inline-Rendering: Headlines groß, Bold fett, Code monospace. Markdown-Syntax-Zeichen werden ausgeblendet. | Live-Rendering im Editor |
| 2.3 | **Formatierungs-Toolbar** | SwiftUI-Toolbar über dem Keyboard (iOS) / in der Toolbar (Mac). Buttons: Bold, Italic, Heading, List, Checkbox, Code, Link, Image. | Formatierung ohne MD-Kenntnis möglich |
| 2.4 | **Bild-Einbettung & Asset-Management** | Drag & Drop / Paste → Bild wird in `assets/` kopiert, relativer Link eingefügt. Inline-Vorschau im Editor. | Bilder nahtlos im Editor |
| 2.5 | **Frontmatter-UI** | Versteckter YAML-Block oben in der Notiz. Toggle zum Ein-/Ausblenden. Editierbar als Key-Value-Liste. | Frontmatter sichtbar per Toggle |
| 2.6 | **Fokus-/Typewriter-Modus** | Aktive Zeile vertikal zentriert. Umgebende Zeilen gedimmt. Alle Menüs ausgeblendet. | Immersives Schreiberlebnis |

> ⚠️ **Dev-Hinweis Phase 2:** TextKit 2 ist mächtig, aber komplex. Die Implementierung muss bewusst simpel gehalten werden: zuerst nur Headlines + Bold/Italic rendern, dann schrittweise weitere Syntax-Elemente hinzufügen. Keine Over-Engineering-Gefahr eingehen. Jeder Meilenstein muss isoliert funktionieren, bevor der nächste begonnen wird.

**Phase 2 Ergebnis:** Ein voll funktionsfähiger WYSIWYG-Markdown-Editor, der sich wie Apple Notes anfühlt, aber reines Markdown speichert.

---

### Phase 3: Organisation & Suche (Wochen 8–10)

Struktur, Verlinkung und Durchsuchbarkeit.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 3.1 | **Ordner-Management** | Erstellen, Umbenennen, Verschieben, Löschen von Ordnern. Drag & Drop in der Sidebar. | Vollständige Ordner-Verwaltung |
| 3.2 | **Inline-Tags** | `#tag`-Erkennung im Editor. Tag-Übersicht in der Sidebar. Filter nach Tags. | Tag-basierte Organisation |
| 3.3 | **Bi-direktionale Links** | `[[Notiz-Name]]` Syntax. Autocompletion beim Tippen. Backlinks-Panel ("Wer verlinkt hierher?"). | Wiki-style Verlinkung |
| 3.4 | **Volltext-Suche** | Schnelle Suche über alle Notizen im Vault. Spotlight-ähnliches UI. Suche in Frontmatter + Body. | Instant-Suche |
| 3.5 | **Onboarding & Templates** | Erster-Start-Flow: Vault erstellen, optionale PARA-Struktur. Template-System für Daily Notes, Zettelkasten. | Second Brain in 30 Sekunden |
| 3.6 | **iCloud Drive Sync** | `NSMetadataQuery` für Sync-Status, `NSFileCoordinator` für konfliktfreies Schreiben. Download-on-Demand. | Nahtloser iCloud-Sync |

**Phase 3 Ergebnis:** Vollständige Organisations-Features. Notizen sind verlinkbar, durchsuchbar und über iCloud synchronisiert.

---

### Phase 4: Quick Capture & OS-Integration (Wochen 11–13)

Die App tief ins Betriebssystem integrieren.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 4.1 | **Share Extension** | iOS/Mac Share Sheet → Text, URL, Bild in eine "Inbox"-Notiz oder neue Notiz speichern. | Capture aus jeder App |
| 4.2 | **Mac Quick Note (Schwebefenster)** | Globaler Hotkey (z.B. `⌥⌘N`) → kleines `NSPanel`. Notiz schreiben, Vault wählen, speichern. | Sofortige Notiz-Erfassung |
| 4.3 | **iOS Widgets** | Lockscreen-Widget (letzte Notiz), Home Screen Widget (Quick-Capture, Pinned Notes). `AppIntents` für Shortcuts. | Widgets auf dem Homescreen |
| 4.4 | **Control Center Toggle** | iOS 18+ Control Center Widget für schnelles Erstellen einer Notiz. | Ein-Tap-Capture |
| 4.5 | **Biometrie & App-Lock** | FaceID/TouchID beim App-Start. Optionaler Ordner-Lock für sensible Bereiche. | Datenschutz per Biometrie |
| 4.6 | **Vault-Verschlüsselung** | AES-256-GCM Verschlüsselung auf Dateiebene via `CryptoKit`. Key im Secure Enclave/Keychain. | Verschlüsselte Vaults |

**Phase 4 Ergebnis:** Quartz ist tief in iOS und macOS integriert. Quick Capture von überall, Sicherheit durch Biometrie und Verschlüsselung.

---

### Phase 5: iPad & Handschrift (Wochen 14–16)

PencilKit, OCR und das iPad-Erlebnis.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 5.1 | **PencilKit-Integration** | `PKCanvasView` als Block im Markdown-Editor. Zeichnungen inline zwischen Text-Absätzen. | Handschrift im Markdown |
| 5.2 | **Zeichnungs-Persistierung** | `PKDrawing` → `.drawing` Datei in `assets/`. Referenz im Frontmatter und als Markdown-Embed. | Zeichnungen als Dateien gespeichert |
| 5.3 | **Background-OCR** | `VNRecognizeTextRequest` auf PencilKit-Renderings. Automatisch nach dem Zeichnen. | Handschrift → Text |
| 5.4 | **Semantische OCR-Speicherung** | Erkannter Text → `ocr_text` Feld im YAML-Frontmatter. Durchsuchbar, aber unsichtbar. | Handschrift volltext-durchsuchbar |
| 5.5 | **iPad-optimiertes Layout** | Multi-Column-Layout, Sidebar-Resize, Keyboard-Shortcuts, Stage Manager Support. | Erstklassiges iPad-Erlebnis |

**Phase 5 Ergebnis:** Vollständige Handschrift-Integration. iPad wird zum primären Notiz-Gerät.

---

### Phase 6: KI & Audio (Wochen 17–22)

Intelligenz und Audio-Features.

| # | Meilenstein | Beschreibung | Ergebnis |
|---|---|---|---|
| 6.1 | **On-Device AI (Apple Intelligence)** | Zusammenfassen, Umschreiben, Tonfall ändern via nativer APIs. Inline über Textmarkierung. | KI ohne Internet |
| 6.2 | **BYOK-Provider-System** | Settings-UI für API-Keys (OpenAI, Anthropic, Gemini, Ollama). Adapter-Pattern für alle Provider. | Nutzer bringt eigenen KI-Schlüssel |
| 6.3 | **KI-Chat mit Notiz** | Seitenleiste: Chat über die aktuelle Notiz. Kontext = Notiz-Inhalt. | "Erkläre mir diese Notiz" |
| 6.4 | **Lokale Vektor-Embeddings** | **Native Apple Vector Search APIs** (iOS 18+ / macOS 15+) für Embeddings und Indexierung nutzen. Fallback: `NLEmbedding` + eigener Index. Speicherung in `.quartz/embeddings.idx`. | Semantischer Index des Vaults |
| 6.5 | **Vault-weite KI-Suche** | "Chat mit dem Vault": Frage → relevante Chunks via native Apple Vektor-Suche → KI-Antwort mit Quellenangabe. Kein externer Vektor-DB-Service. | Semantische Vault-Suche |
| 6.6 | **Audio-Aufnahme** | In-App Mic-Recording via `AVAudioRecorder`. Aufnahme-UI mit Wellenform. Speicherung als `.m4a` im Vault. | Audio-Notizen |
| 6.7 | **Transkription** | `SFSpeechRecognizer` für On-Device-Transkription. Optional: Whisper CoreML für bessere Qualität. | Sprache → Text |
| 6.8 | **Meeting Minutes** | KI-Pipeline: Transkription → Zusammenfassung → Strukturierte Minutes mit Action Items als Markdown. | Automatische Meeting-Protokolle |
| 6.9 | **Speaker Diarization** | `SoundAnalysis` + Custom ML für Sprechererkennung. "Sprecher A sagte..." in Transkription. | Wer hat was gesagt? |

**Phase 6 Ergebnis:** Vollständige KI-Integration und Audio-Pipeline. Quartz wird zum intelligenten Assistenten.

---

## 7. Risiken & offene Entscheidungen

### 7.1 Technische Risiken

| Risiko | Impact | Mitigation |
|---|---|---|
| **TextKit 2 Komplexität** | Hoch – WYSIWYG-Markdown ist der schwierigste Teil | Frühzeitiger Prototyp in Phase 2. Fallback: Simpler Split-View (Edit/Preview). **WICHTIG: Implementierung bewusst simpel halten!** Schritt für Schritt aufbauen, nicht in den Tiefen des Text-Renderings verlieren. Erst Headlines + Bold/Italic, dann schrittweise erweitern. |
| **iCloud Sync-Konflikte** | Mittel – Gleichzeitige Edits auf mehreren Geräten | Automatische Conflict Resolution via Timestamps + manuelle Merge-UI |
| **PencilKit in Markdown** | Mittel – Nicht nativ vorgesehen | Zeichnungen als separate Dateien, im Editor als Blöcke eingebettet |
| **Apple Intelligence Verfügbarkeit** | Mittel – Nur auf neueren Geräten | Graceful Degradation: Feature nur anzeigen wenn verfügbar |
| **Speaker Diarization** | Hoch – Keine fertige native API | Custom CoreML-Modell nötig. Kann als "Beta" gekennzeichnet werden |

### 7.2 Offene Architektur-Entscheidungen

| Entscheidung | Optionen | Tendenz |
|---|---|---|
| **Markdown-Parser** | `swift-markdown` (Apple) vs. komplett eigener Parser | `swift-markdown` als Basis, eigene Extensions |
| **Vektor-Embeddings & Suche** | Native Apple Vector Search APIs (iOS 18+) vs. eigene Implementierung | **Native Apple APIs first.** Fallback: `NLEmbedding` + `Accelerate` für ältere OS-Versionen |
| **WebDAV-Implementation** | Eigener Client vs. Open-Source-Lib | Eigener minimaler Client (wenige HTTP-Calls) |
| **Pro-Feature-Abgrenzung** | Welche Features sind Core vs. Pro? | Core: Editor, Sync, Organisation. Pro: KI-Chat, Meeting Minutes, Vault-Suche |

### 7.3 Mindest-Anforderungen

| Plattform | Minimum |
|---|---|
| iOS | 18.0 |
| iPadOS | 18.0 |
| macOS | 15.0 (Sequoia) |
| Xcode | 16.0+ |
| Swift | 6.0 |

---

> **Nächster Schritt:** Nach Freigabe dieses Plans wählen wir den ersten Meilenstein aus Phase 1 und beginnen mit der Implementierung.
