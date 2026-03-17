# Quartz Code Review Audit Plan v2.0
## Staff iOS/macOS Engineer × Apple Design Award Judge

**Datum:** 17. März 2026
**Scope:** 97 Swift-Dateien, ~14.085 LOC (QuartzKit Framework + App)
**Swift Tools Version:** 6.0 | Plattformen: iOS 18+, macOS 15+
**Auditor-Perspektive:** Kompromisslos. Nur Code, der auf einem Apple Design Award-Level performt, passiert dieses Review.

---

## Executive Summary

Die Codebase hat seit dem letzten Audit (v1.0) signifikante Verbesserungen erfahren. Viele kritische Befunde wurden adressiert:
- ✅ `CoordinatedFileWriter` extrahiert und konsistent genutzt
- ✅ `CommandAction`-Enum statt Bool-Toggles in AppState
- ✅ Pre-computed lowercase im VaultSearchIndex
- ✅ Task-Parallelität begrenzt (maxConcurrency: 16)
- ✅ Deep Link Handler vollständig implementiert
- ✅ macOS-Fallback für DrawingBlockView vorhanden
- ✅ Accessibility Hints in FormattingToolbar
- ✅ Word Count off-main-thread
- ✅ URLSession Timeouts für AI Provider
- ✅ BacklinkUseCase mit Constructor Injection
- ✅ `@SceneStorage` für Column Visibility
- ✅ SearchView Loading-Indikator
- ✅ SidebarViewModel Filter-Caching

**Verbleibende und neue Befunde folgen.**

---

## Säule 1: Cross-Platform & Compiler-Kompatibilität (iOS, iPadOS, macOS)

### 🚨 [Cross-Platform] MarkdownTextView: macOS NSTextView `isRichText = false` bricht AttributedString-Rendering
- **Schweregrad:** Kritisch
- **Das Problem:** `MarkdownTextView.swift:138` — `isRichText = false` wird im macOS Setup gesetzt. Aber `setMarkdown()` auf Zeile 151 setzt `textStorage?.setAttributedString(nsAttributed)` mit einem formatierten AttributedString. Bei `isRichText = false` wird NSTextView die Formatierung ignorieren oder unvorhersagbar darstellen. Der Markdown-Renderer rendert Headings mit fetten Fonts, Code-Blöcke mit Monospace — all das wird bei `isRichText = false` verworfen.
- **Der Fix:**
```swift
private func setup() {
    font = .preferredFont(forTextStyle: .body)
    textContainerInset = NSSize(width: 12, height: 16)
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isRichText = true  // MUSS true sein für AttributedString-Rendering
    usesFontPanel = false  // Font-Panel verbergen, da wir Markdown steuern
    allowsUndo = true
    delegate = self
}
```

### 🚨 [Cross-Platform] ContentView nutzt 2-Column NavigationSplitView statt 3-Column auf iPad
- **Schweregrad:** Hoch
- **Das Problem:** `ContentView.swift:23-27` — `NavigationSplitView` hat nur `sidebar` und `detail`, kein `content` Column. Auf iPad im Landscape/Stage Manager fehlt die mittlere Column für eine Note-Liste. `AdaptiveLayoutView` existiert als 3-Column-Variante (Zeile 9-47), wird aber nirgendwo benutzt. ContentView implementiert sein eigenes 2-Column Layout.
- **Der Fix:** `AdaptiveLayoutView` in `ContentView` integrieren:
```swift
var body: some View {
    AdaptiveLayoutView {
        sidebarColumn
    } content: {
        // Note list für den ausgewählten Ordner
        noteListColumn
    } detail: {
        detailColumn
    }
}
```

### 🚨 [Cross-Platform] CloudSyncService: NSMetadataQuery auf Main Thread
- **Schweregrad:** Hoch
- **Das Problem:** `CloudSyncService.swift:27-63` — `NSMetadataQuery.start()` muss auf dem Main Thread aufgerufen werden, aber `CloudSyncService` ist ein `actor` ohne `@MainActor`-Isolation. `query.start()` auf Zeile 61 wird auf einem beliebigen Thread ausgeführt, was zu undefiniertem Verhalten führt.
- **Der Fix:**
```swift
public func startMonitoring(vaultRoot: URL) -> AsyncStream<(URL, CloudSyncStatus)> {
    let query = NSMetadataQuery()
    query.searchScopes = [vaultRoot]
    query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemPathKey)
    self.metadataQuery = query

    return AsyncStream { continuation in
        // ... observer setup ...

        // NSMetadataQuery MUSS auf Main Thread gestartet werden
        Task { @MainActor in
            query.start()
        }
    }
}
```

### 🚨 [Cross-Platform] SettingsView wird auf macOS als Sheet statt native Settings gezeigt
- **Schweregrad:** Mittel
- **Das Problem:** `ContentView.swift:65-67` — `SettingsView` wird als `.sheet` auf iOS UND macOS gezeigt. Aber `QuartzApp.swift:39-42` definiert bereits eine native macOS `Settings` Scene. Die Sheet-Variante in ContentView kollidiert — auf macOS öffnet sich sowohl die native Settings-Scene (⌘,) als auch ein redundantes Sheet.
- **Der Fix:** Settings-Button in ContentView nur auf iOS anzeigen:
```swift
#if os(iOS)
.sheet(isPresented: $showSettings) {
    SettingsView()
}
#endif
```

### 🚨 [Cross-Platform] `.hoverEffect(.highlight)` nur auf iOS, keine macOS Hover-States
- **Schweregrad:** Mittel
- **Das Problem:** `FileNodeRow.swift:42`, `OnboardingView.swift:333`, `FrontmatterEditorView.swift:100,154` — `.hoverEffect(.highlight)` ist iOS-only (iPad Pointer). macOS bekommt keinerlei Hover-Feedback für interaktive Elemente. Das verletzt die HIG für macOS-Apps.
- **Der Fix:** macOS bekommt Hover-States automatisch über `List` und `Button`. Für Custom Views:
```swift
#if os(iOS)
.hoverEffect(.highlight)
#endif
// macOS: SwiftUI handles hover via List/Button styles natively
```
Status: Bereits korrekt implementiert mit `#if os(iOS)`. Kein Fix nötig, aber macOS Custom-Buttons (BacklinksPanel, FrontmatterEditor) sollten `.onHover` mit Cursor-Änderung bekommen.

---

## Säule 2: Architektur, Verdrahtung & Memory Management

### 🚨 [Architektur] ServiceContainer.shared ist ein Anti-Pattern in SwiftUI
- **Schweregrad:** Hoch
- **Das Problem:** `ServiceContainer.swift` — `@MainActor` Singleton mit `static let shared`. Wird in `ContentView.swift:250,283-286` direkt aufgerufen. Probleme:
  1. Nicht testbar ohne Mocking-Framework
  2. Versteckte Abhängigkeiten — Views deklarieren ihre Dependencies nicht
  3. `bootstrap()` kann vergessen werden
  4. Circular: `resolveVaultProvider()` ruft `resolveFrontmatterParser()` auf
- **Der Fix:** Services als `@Environment` injizieren, Container nur als Composition Root:
```swift
// In QuartzApp.swift — einmalig erstellen
@State private var vaultProvider = FileSystemVaultProvider(
    frontmatterParser: FrontmatterParser()
)

// Per Environment weiterreichen
ContentView()
    .environment(\.vaultProvider, vaultProvider)
```

### 🚨 [Architektur] Doppelte Tier-Map in ProFeatureGate und DefaultFeatureGate
- **Schweregrad:** Hoch
- **Das Problem:** `ProFeatureGate.swift:29-50` dupliziert die komplette `tierMap` von `DefaultFeatureGate.swift:13-34`. Wenn ein Feature seinen Tier ändert, muss man an zwei Stellen updaten. Single Source of Truth verletzt.
- **Der Fix:** `ProFeatureGate` soll `DefaultFeatureGate` erben oder die Tier-Map aus einer shared Quelle lesen:
```swift
final class ProFeatureGate: FeatureGating, @unchecked Sendable {
    private let base = DefaultFeatureGate()
    private let lock = NSLock()
    private var _hasPurchasedPro = false

    func isEnabled(_ feature: Feature) -> Bool {
        switch base.tier(for: feature) {
        case .free: true
        case .pro: lock.withLock { _hasPurchasedPro }
        }
    }

    func tier(for feature: Feature) -> FeatureTier {
        base.tier(for: feature)
    }
}
```

### 🚨 [Architektur] NoteEditorViewModel erstellt kein Debounce für Content-Änderungen
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorViewModel.swift:10-17` — Der `didSet`-Observer auf `content` feuert bei JEDEM Zeichen. Das löst aus:
  1. `isDirty = true`
  2. `scheduleWordCountUpdate()` — erstellt und cancelt Task
  3. `scheduleAutosave()` — erstellt und cancelt Task

  Bei schnellem Tippen werden hunderte Tasks pro Sekunde erstellt und gecancelt. Die Autosave/WordCount-Tasks haben zwar `Task.sleep` als Debounce, aber die Task-Erstellung selbst ist overhead.
- **Der Fix:** Acceptable overhead für Swift Structured Concurrency. Die Tasks werden sofort gecancelt, der Overhead ist minimal. Kein Code-Fix nötig, aber ein `@TaskLocal` oder Debounce-Utility wäre eleganter.

### 🚨 [Memory] OnboardingView erstellt VaultTemplateService innerhalb einer Closure
- **Schweregrad:** Mittel
- **Das Problem:** `OnboardingView.swift:349` — `VaultTemplateService()` wird in `createVault()` als lokaler Actor erstellt. Korrekt, da der Actor nur für diese Operation gebraucht wird. Aber: `OnboardingView.swift:363` ruft `url.stopAccessingSecurityScopedResource()` auf, BEVOR der `onComplete`-Callback feuert (Zeile 371). Wenn der Caller den Vault sofort öffnet, hat er keinen Security-Scoped Access mehr.
- **Der Fix:**
```swift
// Security Scope NUR freigeben wenn Vault-Erstellung fehlschlägt.
// Beim Erfolg: Caller ist verantwortlich für den Lifecycle.
let vault = VaultConfig(
    name: url.lastPathComponent,
    rootURL: url,
    templateStructure: selectedTemplate
)
// NICHT url.stopAccessingSecurityScopedResource() aufrufen
// Der Caller (ContentView.loadVault) benötigt den Zugriff weiter
await MainActor.run {
    onComplete(vault)
}
```

### 🚨 [Memory] AIProviderRegistry.shared als @MainActor Singleton
- **Schweregrad:** Mittel
- **Das Problem:** `AIProvider.swift:350` — `AIProviderRegistry` ist `@Observable @MainActor` mit `static let shared`. Lebt für die gesamte App-Laufzeit, hält Referenzen auf alle Provider-Instanzen. Nicht problematisch per se, aber das Singleton-Pattern erschwert Testing und verhindert Multi-Window-Szenarien (Stage Manager).
- **Der Fix:** Registry per Environment injizieren statt Singleton.

### 🚨 [Memory] FileWatcher: File Descriptor Leak bei Actor-Deallokation
- **Schweregrad:** Hoch
- **Das Problem:** `FileWatcher.swift:8-9` — `fileDescriptor` wird via `open()` geöffnet. `close(fd)` passiert nur im `DispatchSource.setCancelHandler` (Zeile 53). Wenn der `FileWatcher`-Actor deallokiert wird OHNE dass der Stream terminiert wurde, leakt der File Descriptor. Der Actor hat `stopWatching()` (Zeile 65), aber keinen `deinit`.
- **Der Fix:**
```swift
deinit {
    source?.cancel()
    // source cancel handler schließt den FD
}
```
Hinweis: `deinit` auf Actors hat Einschränkungen, aber der `DispatchSource.cancel()` ist thread-safe.

---

## Säule 3: Exception Handling & Edge Cases

### 🚨 [Error Handling] DrawingStorageService schreibt ohne File Coordination
- **Schweregrad:** Kritisch
- **Das Problem:** `DrawingStorageService.swift:38-39` — `drawing.dataRepresentation()` und `data.write(to:options:.atomic)` ohne `NSFileCoordinator`. Die Zeichnungsdateien liegen im selben Vault wie die Markdown-Dateien. Bei iCloud-Sync können Zeichnungen verloren gehen oder korrumpiert werden.

  Ebenfalls betroffen:
  - Zeile 53: `Data(contentsOf: fileURL)` — Read ohne Coordination
  - Zeile 62-70: `removeItem` ohne Coordination
  - Zeile 134: `pngData.write(to:)` — Thumbnail-Write ohne Coordination
- **Der Fix:** `CoordinatedFileWriter.shared` nutzen:
```swift
public func save(drawing: PKDrawing, drawingID: String, noteURL: URL) throws -> String {
    let assetsFolder = assetsURL(for: noteURL)
    try CoordinatedFileWriter.shared.createDirectory(at: assetsFolder)

    let fileName = "\(drawingID).drawing"
    let fileURL = assetsFolder.appending(path: fileName)
    let data = drawing.dataRepresentation()
    try CoordinatedFileWriter.shared.write(data, to: fileURL)

    // Thumbnail
    let thumbnailURL = assetsFolder.appending(path: "\(drawingID).png")
    try saveThumbnail(drawing: drawing, to: thumbnailURL)
    return "assets/\(fileName)"
}
```

### 🚨 [Error Handling] VaultPickerView: Bookmark-Fehler wird verschluckt
- **Schweregrad:** Hoch
- **Das Problem:** `VaultPickerView.swift:96-98` — Bookmark-Erstellung kann fehlschlagen, der `catch`-Block ist leer mit nur einem Kommentar. Wenn die Bookmark-Persistierung fehlschlägt, kann der Vault nach App-Neustart nicht wieder geöffnet werden. Der Nutzer bemerkt das erst beim nächsten Start.
- **Der Fix:**
```swift
} catch {
    // Log the error, but don't block vault opening
    // The vault works for this session; bookmark will be retried on next open
    os_log(.error, "Failed to persist vault bookmark: %{public}@", error.localizedDescription)
}
```
Besser noch: Dem Nutzer einen dezenten Hinweis geben, dass die Vault-Auswahl nicht persistiert werden konnte.

### 🚨 [Error Handling] ContentView.createDailyNote hat keinen Fehler-Feedback
- **Schweregrad:** Mittel
- **Das Problem:** `ContentView.swift:267-275` — `createDailyNote()` erstellt einen `DateFormatter` mit `dateFormat: "yyyy-MM-dd"` ohne `Locale(identifier: "en_US_POSIX")`. In manchen Locales kann `dateFormat` andere Kalender-Systeme nutzen (z.B. buddhistische Zeitrechnung in Thai-Locale). Außerdem fehlt jegliches Error-Handling wenn `createNote` fehlschlägt.
- **Der Fix:**
```swift
private func createDailyNote() {
    guard let root = sidebarViewModel?.vaultRootURL else { return }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let name = formatter.string(from: Date())
    Task {
        do {
            try await sidebarViewModel?.createNote(named: name, in: root)
        } catch {
            // SidebarViewModel.createNote already handles errors internally
            // but if vaultProvider throws, user should know
        }
    }
}
```

### 🚨 [Error Handling] FrontmatterParser: Multiline YAML Values nicht unterstützt
- **Schweregrad:** Mittel
- **Das Problem:** `FrontmatterParser.swift:76-117` — Parsed YAML zeilenbasiert. Multiline-Werte (Block Scalars `|` und `>`, oder Strings mit `\n`) werden nicht korrekt geparst. Ein Frontmatter-Block wie:
```yaml
title: My Note
description: |
  This is a long
  description
tags: [tag1]
```
würde `description` nur als leer parsen und die folgenden Zeilen als separate Keys interpretieren.
- **Der Fix:** Kurzfristig: Dokumentieren, dass nur single-line Values unterstützt werden. Langfristig: Einen echten YAML-Parser (z.B. `Yams` SPM package) verwenden, oder zumindest Block-Scalar-Erkennung implementieren.

### 🚨 [Error Handling] VaultEncryptionService: Key im Memory nach Verwendung
- **Schweregrad:** Hoch
- **Das Problem:** `VaultEncryptionService.swift:57-59` — `loadKey()` gibt einen `SymmetricKey` zurück, der im Caller-Memory verbleibt. Kein Zeroing nach Verwendung. In Swift ist Memory-Zeroing schwierig, aber der Key sollte zumindest nicht länger als nötig gehalten werden.
- **Der Fix:** Keys nur innerhalb von Closures verfügbar machen:
```swift
public func withKey<T>(ref: String, operation: (SymmetricKey) throws -> T) throws -> T {
    let key = try loadKey(ref: ref)
    defer { /* SymmetricKey wird nach Scope freigegeben */ }
    return try operation(key)
}
```

---

## Säule 4: Apple Design Awards Level UI/UX & HIG

### 🚨 [HIG] Kein matchedGeometryEffect für Note-Übergänge
- **Schweregrad:** Hoch
- **Das Problem:** `ContentView.swift:154-159` — Beim Wechsel zwischen Notizen wird eine `.transition(.asymmetric(...))` verwendet. Das erzeugt einen Opacity+Scale-Übergang. Apple Notes verwendet Hero-Transitions mit `matchedGeometryEffect`, wobei der Notiz-Titel von der Sidebar in den Editor-Header "fliegt". Quartz springt hart.
- **Der Fix:**
```swift
@Namespace private var noteTransition

// In SidebarView — auf dem selektierten Titel:
Text(node.name)
    .matchedGeometryEffect(id: node.url, in: noteTransition)

// In NoteEditorView — auf dem Navigationstitel oder Header:
Text(viewModel.note?.displayName ?? "")
    .matchedGeometryEffect(id: viewModel.note?.fileURL, in: noteTransition)
```
Hinweis: `@Namespace` muss von einem gemeinsamen Parent gehalten und als Parameter durchgereicht werden.

### 🚨 [HIG] Onboarding MeshGradientBackground: Canvas-basiert statt MeshGradient API
- **Schweregrad:** Mittel
- **Das Problem:** `OnboardingView.swift:389-441` — Der Hintergrund wird manuell über `Canvas` + `TimelineView` mit Ellipsen gerendert. Ab iOS 18 / macOS 15 gibt es die native `MeshGradient`-API, die GPU-optimiert ist und weniger CPU verbraucht. Der Canvas-Ansatz rendert bei 10fps (Zeile 406: `minimumInterval: 1.0 / 10.0`), was auf ProMotion-Displays ruckelig aussieht.
- **Der Fix:**
```swift
MeshGradient(width: 3, height: 3, points: [
    [0, 0], [0.5, 0], [1, 0],
    [0, 0.5], [0.5, 0.5], [1, 0.5],
    [0, 1], [0.5, 1], [1, 1]
], colors: [
    .clear,
    QuartzColors.folderYellow.opacity(0.15),
    .clear,
    QuartzColors.noteBlue.opacity(0.1),
    QuartzColors.canvasPurple.opacity(0.12),
    QuartzColors.noteBlue.opacity(0.1),
    .clear,
    QuartzColors.folderYellow.opacity(0.15),
    .clear
])
```

### 🚨 [HIG] Kein Haptics auf macOS (UIImpactFeedbackGenerator)
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorView.swift:43-44` — `.sensoryFeedback(.success, ...)` und `.sensoryFeedback(.impact, ...)` sind korrekt cross-platform (SwiftUI ignoriert Haptics auf macOS). Aber: macOS hat Haptic-Support via Force Touch Trackpad (`NSHapticFeedbackManager`). Für einen Apple Design Award sollte man macOS-native Haptics berücksichtigen.
- **Der Fix:** Acceptable as-is. `.sensoryFeedback` auf macOS mit Force Touch Trackpad funktioniert seit macOS 14. Kein Fix nötig.

### 🚨 [HIG] Error-Banner in ContentView blockiert keine Interaktion
- **Schweregrad:** UI-Polish
- **Das Problem:** `ContentView.swift:95-99` — Error-Banner wird als `.overlay` gezeigt, aber die darunterliegende UI bleibt interaktiv. Das Banner kann durch Scroll-Gesten verdeckt werden. Kein Auto-Dismiss.
- **Der Fix:**
```swift
.overlay(alignment: .top) {
    if let error = appState.errorMessage {
        errorBanner(message: error)
            .task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation { appState.errorMessage = nil }
            }
    }
}
```

### 🚨 [HIG] QuartzButton Foreground ist hardcoded `.white`
- **Schweregrad:** Mittel
- **Das Problem:** `LiquidGlass.swift:572` — `.foregroundStyle(.white)` auf dem Button-Text. Bei hellem Accent Color (z.B. Gelb auf Weiß) wird der Text unleserlich. Apple empfiehlt, den Foreground-Kontrast dynamisch zu berechnen.
- **Der Fix:** Entweder den Accent Color dunkel genug halten (aktuell 0xF2994A = Orange, OK) oder dynamischen Kontrast nutzen:
```swift
.foregroundStyle(Color.accentColor.contrastingForeground)
```
Aktuell akzeptabel mit dem Orange-Accent, aber bei Custom-Themes riskant.

### 🚨 [HIG] Kein `@FocusState` für Keyboard-Navigation auf macOS
- **Schweregrad:** Hoch
- **Das Problem:** Keine einzige View in der Codebase nutzt `@FocusState`. macOS-Keyboard-Navigation (Tab-Reihenfolge, Focus-Ring) funktioniert nur über SwiftUI-Default-Verhalten. Custom Views wie der `FrontmatterEditorView` mit TextFields haben keine explizite Focus-Verwaltung. Tab drücken springt nicht intuitiv zwischen Title → Tags → Custom Fields.
- **Der Fix:**
```swift
@FocusState private var focusedField: FrontmatterField?

enum FrontmatterField: Hashable {
    case title, newTag, customKey, customValue
}

TextField("Title", text: ...)
    .focused($focusedField, equals: .title)
    .onSubmit { focusedField = .newTag }
```

---

## Säule 5: Lokalisation (L10n) & Internationalisierung (I18n)

### 🚨 [L10n] NoteTemplate.displayName nicht lokalisiert
- **Schweregrad:** Hoch
- **Das Problem:** `VaultTemplateService.swift:173-180` — `NoteTemplate.displayName` gibt hardcodierte englische Strings zurück:
```swift
case .blank: "Blank Note"
case .daily: "Daily Note"
case .meeting: "Meeting Notes"
```
Diese Strings werden in der UI angezeigt (z.B. Template-Auswahl im Onboarding), sind aber nicht über `String(localized:)` lokalisiert.
- **Der Fix:**
```swift
public var displayName: String {
    switch self {
    case .blank: String(localized: "Blank Note", bundle: .module)
    case .daily: String(localized: "Daily Note", bundle: .module)
    case .meeting: String(localized: "Meeting Notes", bundle: .module)
    case .zettel: String(localized: "Zettelkasten Note", bundle: .module)
    case .project: String(localized: "Project Brief", bundle: .module)
    }
}
```

### 🚨 [L10n] VaultTemplateService Template-Content hardcodiert Englisch
- **Schweregrad:** Hoch
- **Das Problem:** `VaultTemplateService.swift:88-160` — Die gesamte Template-Struktur (PARA-Ordnernamen "1 Projects", "2 Areas", etc., Zettelkasten "Fleeting Notes", "Literature Notes", etc.) und die Welcome.md-Inhalte sind auf Englisch hardcodiert. Deutsche, französische etc. Nutzer bekommen englische Ordnerstrukturen.
- **Der Fix:** Ordnernamen über `String(localized:)` lokalisieren:
```swift
private func createPARAStructure(in root: URL) throws {
    let folders = [
        String(localized: "1 Projects", bundle: .module),
        String(localized: "2 Areas", bundle: .module),
        String(localized: "3 Resources", bundle: .module),
        String(localized: "4 Archive", bundle: .module),
        String(localized: "Daily Notes", bundle: .module),
        String(localized: "Templates", bundle: .module),
    ]
    // ...
}
```
**Achtung:** Ordnernamen lokalisieren ist kontrovers — Obsidian z.B. nutzt immer Englisch. Design-Entscheidung, aber muss bewusst getroffen werden.

### 🚨 [L10n] NoteTemplate.content() generiert englische Markdown-Inhalte
- **Schweregrad:** Mittel
- **Das Problem:** `VaultTemplateService.swift:193-311` — Template-Inhalte enthalten englische Headings ("## Tasks", "## Notes", "## Attendees", "## Action Items", etc.). Diese werden direkt in Markdown-Dateien geschrieben.
- **Der Fix:** Headings in Templates lokalisieren, oder bewusst als universelle Englisch-Templates belassen (wie Notion/Obsidian). Design-Entscheidung dokumentieren.

### 🚨 [L10n] Word Count String braucht Plural-Varianten
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorView.swift:109` — `"\(viewModel.wordCount) word(s)"` hat einen Kommentar "Uses plural rules", aber String Catalogs benötigen explizite Plural-Definitionen für jede Sprache. Deutsch: "1 Wort" vs "5 Wörter". Japanisch: Kein Plural. Arabisch: 6 Plural-Formen.
- **Der Fix:** In den `.xcstrings` Dateien die `stringsdict`-äquivalenten Plural-Varianten definieren:
```
// In Localizable.xcstrings:
"%lld word(s)" → Variations → Plural
    one: "%lld word"
    other: "%lld words"
```

### 🚨 [L10n] DateFormatter ohne POSIX Locale an 2 Stellen
- **Schweregrad:** Mittel
- **Das Problem:**
  1. `ContentView.swift:269` — `DateFormatter()` mit `dateFormat: "yyyy-MM-dd"` ohne `locale = Locale(identifier: "en_US_POSIX")`. In manchen Locales (z.B. Saudi-Arabien) wird der islamische Kalender verwendet, `yyyy` gibt dann Jahr 1447 zurück.
  2. `VaultTemplateService.swift:210-212` — `DateFormatter()` mit `dateStyle = .full` ohne POSIX für ISO-Formatter auf Zeile 194.
- **Der Fix:**
```swift
// ContentView.swift:269
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.dateFormat = "yyyy-MM-dd"
```

### 🚨 [L10n] Kein RTL-Test-Strategie
- **Schweregrad:** Mittel
- **Das Problem:** Die Codebase unterstützt grundsätzlich RTL (SwiftUI flippt automatisch). Aber manuell gesetzte Elemente könnten brechen:
  - `LiquidGlass.swift:46-52` — Gradient `startPoint: .topLeading, endPoint: .bottomTrailing` — OK, SwiftUI flippt
  - `MarkdownTextView.swift:30` — `textContainerInset` mit festen Werten — Wird NICHT geflippt
  - `QuartzAnimation.swift` — Alle Offsets (`offset(y:)`) sind vertikal → OK

  Kein systematischer RTL-Test vorhanden.
- **Der Fix:** RTL-Pseudo-Language im Xcode-Schema aktivieren und alle Views durchgehen. `textContainerInset` auf NSTextView/UITextView sollte `.writingDirectionLeftToRight` / `.writingDirectionRightToLeft` berücksichtigen oder symmetrische Insets verwenden (aktuell: `left: 12, right: 12` → symmetrisch, OK).

---

## Säule 6: Performance & Device Capabilities

### 🚨 [Performance] MarkdownTextView vollständiges Re-Rendering bei jedem Update
- **Schweregrad:** Kritisch
- **Das Problem:** `MarkdownTextView.swift:96-102` (iOS), `210-217` (macOS) — `updateUIView`/`updateNSView` prüft `rawMarkdown != text` und ruft dann `setMarkdown()` auf, das den KOMPLETTEN Text neu parsed und als AttributedString rendert. Bei einem 10.000-Wort-Dokument bedeutet jeder SwiftUI-State-Change (z.B. Font-Scale-Änderung via Slider) ein vollständiges Re-Rendering aller Markdown-Attributes.

  Das Hauptproblem: Wenn der Nutzer tippt, triggert `textViewDidChange` → `onTextChange` → `text = newText` (State-Change) → `updateUIView` wird aufgerufen → `rawMarkdown != text` ist `true` weil der text gerade erst gesetzt wurde → `setMarkdown()` wird aufgerufen → Cursor-Position geht potenziell verloren.
- **Der Fix:** Differentielles Rendering nur für geänderte Paragraphen:
```swift
public func updateUIView(_ uiView: MarkdownUITextView, context: Context) {
    let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
    let newFont = UIFont.systemFont(ofSize: baseSize * editorFontScale)
    if uiView.font != newFont {
        uiView.font = newFont
    }
    // Nur updaten wenn sich der Source-Text tatsächlich geändert hat
    // UND die Änderung nicht vom UITextView selbst kam
    if uiView.rawMarkdown != text && !uiView.isFirstResponder {
        uiView.setMarkdown(text)
    }
}
```
Langfristig: TextKit 2 `NSTextContentManager` mit `NSTextLayoutFragment`-basiertem inkrementellen Rendering.

### 🚨 [Performance] BacklinkUseCase liest jede Notiz im Vault sequentiell
- **Schweregrad:** Hoch
- **Das Problem:** `BacklinkUseCase.swift:43-59` — `scanForBacklinks` iteriert sequentiell über alle Nodes und ruft für jede Notiz `vaultProvider.readNote(at:)` auf. Kein `TaskGroup`, keine Parallelität. Bei 1000 Notizen = 1000 sequentielle File-Reads.
- **Der Fix:**
```swift
private func scanForBacklinks(
    in nodes: [FileNode],
    targetName: String
) async throws -> [Backlink] {
    let noteNodes = collectNotes(from: nodes)

    return try await withThrowingTaskGroup(of: [Backlink].self) { group in
        for node in noteNodes {
            group.addTask {
                let note = try await vaultProvider.readNote(at: node.url)
                let links = linkExtractor.extractLinks(from: note.body)
                return links
                    .filter { $0.target.caseInsensitiveCompare(targetName) == .orderedSame }
                    .map { link in
                        Backlink(
                            sourceNoteURL: node.url,
                            sourceNoteName: node.name.replacingOccurrences(of: ".md", with: ""),
                            context: extractContext(for: link, in: note.body)
                        )
                    }
            }
        }
        var all: [Backlink] = []
        for try await batch in group { all.append(contentsOf: batch) }
        return all
    }
}
```

### 🚨 [Performance] SidebarView erstellt Array-Kopien bei jedem Render
- **Schweregrad:** Mittel
- **Das Problem:** `SidebarView.swift:189` — `Array(viewModel.filteredTree.enumerated())` erstellt bei jedem View-Body-Aufruf ein neues Array. `SidebarView.swift:144` — `Array(viewModel.tagInfos.prefix(12).enumerated())` ebenfalls.
- **Der Fix:** Die Arrays vor dem `body` cachen oder `LazyVStack` statt `List` für große Bäume verwenden. Minimal-Impact da SwiftUI's diffing effizient ist, aber bei >500 Nodes messbar.

### 🚨 [Performance] VaultSearchIndex: `search()` ist synchron auf dem Actor
- **Schweregrad:** Mittel
- **Das Problem:** `VaultSearchIndex.swift:64` — `search(query:)` ist nicht `async`, blockiert den Actor für die gesamte Suchdauer. Wenn parallel ein `updateEntry` läuft, blockiert dieser bis die Suche fertig ist. Bei 10.000 Entries und komplexer Query kann das spürbar sein.
- **Der Fix:** Akzeptabel für In-Memory-Suche. Ein Trie oder Inverted Index würde O(1)-Lookups ermöglichen statt O(n)-Scan.

### 🚨 [Performance] Onboarding Canvas-Animation läuft bei 10fps
- **Schweregrad:** UI-Polish
- **Das Problem:** `OnboardingView.swift:406` — `TimelineView(.animation(minimumInterval: 1.0 / 10.0))` rendert bei nur 10fps. Auf ProMotion-Displays (120Hz) ist die Animation sichtbar ruckelig. Canvas-Rendering mit 3 Ellipsen und Blur ist nicht CPU-intensiv genug, um 10fps zu rechtfertigen.
- **Der Fix:** `minimumInterval: nil` (System-Default, typisch 60fps) oder besser: Native `MeshGradient` nutzen (siehe Säule 4).

---

## Zusätzliche Befunde

### 🚨 [Security] VaultPickerView: Security-Scoped Resource Lifecycle
- **Schweregrad:** Hoch
- **Das Problem:** `VaultPickerView.swift:75-110` — `url.startAccessingSecurityScopedResource()` wird aufgerufen, aber `stopAccessingSecurityScopedResource()` wird NIEMALS aufgerufen (bewusst per Kommentar Zeile 106-109). Das Bookmark wird gespeichert, aber beim nächsten App-Start wird das Bookmark resolved, was einen neuen Security-Scoped Access startet — ohne den alten zu beenden. Über mehrere Vault-Öffnungen akkumulieren sich die Security-Scoped Resource Accesses.
- **Der Fix:** Beim Wechsel des Vaults den alten Security-Scope beenden:
```swift
// In ContentView oder AppState
func switchVault(to newVault: VaultConfig) {
    currentVault?.rootURL.stopAccessingSecurityScopedResource()
    currentVault = newVault
    loadVault(newVault)
}
```

### 🚨 [Architecture] Widgets sind non-functional
- **Schweregrad:** Kritisch
- **Das Problem:** Die Widget-Dateien (`QuartzWidgets.swift`, `QuartzControlWidget.swift`, `QuartzAppIntents.swift`) existieren, aber der Timeline Provider gibt nur Placeholder-Daten zurück. Widgets zeigen keine echten Notiz-Daten an. Für einen App Store Release müssen Widgets entweder funktionieren oder entfernt werden — Apple reviewt non-functional Widgets.
- **Der Fix:** App Group für shared UserDefaults einrichten, letzte Notizen darin cachen, Timeline Provider daraus lesen. Oder: Widgets erst in v2 ausliefern und aus dem Target entfernen.

### 🚨 [Architecture] Keine Unit Tests für Presentation Layer
- **Schweregrad:** Hoch
- **Das Problem:** 14 Test-Files existieren, aber alle testen Data/Domain Layer (FrontmatterParser, MarkdownRenderer, CloudSync, etc.). Kein einziger Test für ViewModels (`NoteEditorViewModel`, `SidebarViewModel`). Die ViewModels enthalten Business-Logik (Autosave, Filtering, Word Count) die testbar und testWÜRDIG ist.
- **Der Fix:** ViewModel-Tests hinzufügen:
```swift
@Test func autosaveTriggerOnContentChange() async {
    let mockProvider = MockVaultProvider()
    let vm = NoteEditorViewModel(vaultProvider: mockProvider, frontmatterParser: FrontmatterParser())
    await vm.loadNote(at: testNoteURL)
    vm.content = "Updated content"
    // Wait for autosave delay
    try await Task.sleep(for: .seconds(3))
    #expect(mockProvider.savedNotes.count == 1)
}
```

### 🚨 [Architecture] Kein Error Logging / Crash Reporting Infrastructure
- **Schweregrad:** Mittel
- **Das Problem:** Die App nutzt `os.Logger` in einigen Services (`VaultSearchIndex`, `DrawingStorageService`, `MarkdownTextView`), aber es gibt keine zentrale Logging-Strategie. Errors in ViewModels werden als `errorMessage: String?` gespeichert und dem User angezeigt, aber nicht geloggt. Kein Crash-Reporting-Hook.
- **Der Fix:** Einen zentralen `QuartzLogger` erstellen und konsistent nutzen.

### 🚨 [Security] API Keys in CustomModelStore via UserDefaults
- **Schweregrad:** Mittel
- **Das Problem:** `AIProvider.swift:409-454` — `CustomModelStore` persistiert benutzerdefinierte Modelle in `UserDefaults`. Das ist OK für Modell-Metadaten. Aber die Keychain-basierte Key-Speicherung (`KeychainHelper`) nutzt `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — perfekt. Allerdings: `hasKey()` auf Zeile 511 ist `nonisolated` und ruft `SecItemCopyMatching` ohne Actor-Isolation auf. Das ist thread-safe (Keychain ist thread-safe), aber der `nonisolated`-Marker umgeht die Actor-Isolation bewusst.
- **Der Fix:** Akzeptabel. `SecItemCopyMatching` ist dokumentiert als thread-safe. Der `nonisolated`-Marker ist korrekt.

---

## Gesamtnote

### 📊 B+ (Gut mit gezieltem Optimierungsbedarf)

**Deutliche Verbesserung gegenüber v1.0 (C+).**

**Herausragend:**
- Saubere 3-Layer-Architektur (Data/Domain/Presentation) mit klarer Trennung
- Modernes Swift 6: `@Observable`, `actor`, `Sendable`, Structured Concurrency durchgängig
- Exzellentes Design-System: LiquidGlass-Komponenten, QuartzAnimation-Constants, Spring-basierte Animationen
- Vorbildliche `#if canImport()` Guards für cross-platform (UIKit/AppKit, PencilKit)
- Konsistente L10n mit `String(localized:bundle:.module)` — 245+ Strings
- 7 Sprachen architektonisch vorbereitet (EN, DE, FR, ES, IT, ZH, JA)
- Gutes Accessibility-Fundament (`accessibilityReduceMotion`, `.accessibilityLabel`, `.accessibilityHint`, `.sensoryFeedback`)
- `CoordinatedFileWriter` für iCloud-sichere File-Ops
- Feature-Gating mit Clean FeatureGating Protocol
- Keychain-basierte API-Key-Speicherung

**Muss gefixt werden für Apple Design Award:**
- MarkdownTextView macOS `isRichText = false` (Kritisch — rendert nicht korrekt)
- DrawingStorageService ohne File Coordination (Kritisch — iCloud-Datenverlust)
- MarkdownTextView vollständiges Re-Rendering bei jedem Keystroke (Kritisch — Performance)
- Widget-Implementation ist non-functional (Kritisch — App Store Rejection)
- ContentView nutzt AdaptiveLayoutView nicht (Hoch — iPad-Experience)
- Keine ViewModel-Tests (Hoch — Regressions-Risiko)
- Kein `@FocusState` für macOS Keyboard-Navigation (Hoch — HIG-Verletzung)

---

## Top 3 Architektur-Prioritäten

### 1. 🔴 MarkdownTextView: isRichText + Inkrementelles Rendering
`isRichText = false` auf macOS fixen. Langfristig inkrementelles Rendering implementieren (nur geänderte Paragraphen neu rendern). **Ohne Fix: macOS-Editor ist visuell gebrochen. Mit Fix: Grundlage für flüssiges 120Hz-Editing.**

### 2. 🔴 File Coordination für DrawingStorageService
Alle File-Ops in `DrawingStorageService` über `CoordinatedFileWriter` leiten. Dasselbe Pattern wie bereits in `AssetManager` und `VaultTemplateService` implementiert. **Ohne Fix: Zeichnungen können bei iCloud-Sync korrumpiert oder verloren gehen.**

### 3. 🟡 iPad 3-Column Layout + macOS Focus States
`AdaptiveLayoutView` in `ContentView` integrieren für die volle iPad/Mac-Experience. `@FocusState` in FrontmatterEditor und Search implementieren. **Ohne Fix: Die App fühlt sich auf iPad und Mac wie eine vergrößerte iPhone-App an — das Gegenteil eines Apple Design Award.**

---

*Audit durchgeführt am 17. März 2026. Nächstes Review empfohlen nach Behebung der Kritisch/Hoch-Befunde.*
