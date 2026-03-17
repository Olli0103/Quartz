# Quartz Code Review Audit Plan v3.0
## Staff iOS/macOS Engineer × Apple Design Award Judge

**Datum:** 17. März 2026
**Scope:** ~95 Swift-Dateien (QuartzKit Framework + App Target)
**Swift Tools Version:** 6.0 | Plattformen: iOS 18+, macOS 15+
**Auditor-Perspektive:** Kompromisslos. Nur Code auf Apple Design Award-Level passiert.

---

## Executive Summary

Die Codebase hat seit v2.0 weitere signifikante Verbesserungen erfahren. Viele frühere Befunde wurden korrekt adressiert:

- ✅ `isRichText = true` auf macOS (MarkdownNSTextView.swift:139)
- ✅ `AdaptiveLayoutView` wird korrekt als 3-Column Layout in ContentView verwendet
- ✅ `@FocusState` in FrontmatterEditorView implementiert (4 Felder: title, newTag, customKey, customValue)
- ✅ NSMetadataQuery wird auf Main Thread gestartet (`Task { @MainActor in query.start() }`)
- ✅ `matchedGeometryEffect` auf Note-Titel in ContentView.noteListColumn
- ✅ MeshGradient-API statt Canvas im Onboarding-Background
- ✅ Error-Banner Auto-Dismiss nach 5 Sekunden
- ✅ Error-Queue im AppState statt einzelner String
- ✅ Settings-Sheet nur auf iOS (`#if os(iOS)`)
- ✅ `DateFormatter` mit `en_US_POSIX` Locale in ContentViewModel.createDailyNote
- ✅ Word Count mit `^[\(count) word](inflect: true)` Pluralisierung
- ✅ `[weak self]` in autosaveTask und wordCountTask
- ✅ DrawingBlockView macOS-Fallback mit informativer Platzhalter-View
- ✅ VaultSearchIndex pre-computed lowercase Strings
- ✅ VaultSearchIndex Task-Parallelität begrenzt (maxConcurrency: 16)

**Verbleibende und neue Befunde folgen.**

---

## Säule 1: Cross-Platform & Compiler-Kompatibilität (iOS, iPadOS, macOS)

### 🚨 [Cross-Platform] `listStyle(.insetGrouped)` kompiliert nicht auf macOS
- **Schweregrad:** Kritisch
- **Das Problem:** `ContentView.swift:164` — `.listStyle(.insetGrouped)` existiert nur auf iOS/iPadOS. Der macOS-Compiler wird einen Fehler werfen. Show-Stopper für das macOS-Target.
- **Der Fix (Code):**
```swift
// ContentView.swift – noteListColumn
List(notes, id: \.url, selection: $selectedNoteURL) { node in
    // ...
}
#if os(iOS)
.listStyle(.insetGrouped)
#else
.listStyle(.sidebar)
#endif
```

### 🚨 [Cross-Platform] MarkdownNSTextView: TextKit 2 nicht korrekt initialisiert
- **Schweregrad:** Hoch
- **Das Problem:** `MarkdownTextView.swift:198-207` — `MarkdownNSTextView()` wird mit dem parameterlosen Init erstellt, der TextKit 1 verwendet. Für echtes TextKit 2 muss `NSTextContentStorage` + `NSTextLayoutManager` aufgesetzt werden. `setMarkdown()` funktioniert, fällt aber auf TextKit 1 zurück.
- **Der Fix (Code):**
```swift
public func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    contentStorage.addTextLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(
        width: scrollView.contentSize.width,
        height: .greatestFiniteMagnitude
    ))
    container.widthTracksTextView = true
    layoutManager.textContainer = container

    let textView = MarkdownNSTextView(frame: .zero, textContainer: container)
    textView.autoresizingMask = [.width, .height]
    textView.onTextChange = { [_text] newText in
        _text.wrappedValue = newText
    }
    scrollView.documentView = textView
    return scrollView
}
```

### 🚨 [Cross-Platform] `columnVisibility` State-Duplikation zwischen ContentView und AdaptiveLayoutView
- **Schweregrad:** Hoch
- **Das Problem:** `ContentView.swift:17` deklariert `@State private var columnVisibility`, aber `AdaptiveLayoutView.swift:11` hat eine eigene `@State private var columnVisibility`. Der `toggleSidebar`-Command in `handleCommand()` ändert die Variable in ContentView, aber AdaptiveLayoutView verwaltet seine eigene – die zwei Zustände sind nie verbunden. **Der Sidebar-Toggle-Shortcut (⌘/) funktioniert nicht.**
- **Der Fix (Code):**
```swift
// AdaptiveLayoutView.swift – columnVisibility als Binding akzeptieren
public struct AdaptiveLayoutView<Sidebar: View, Content: View, Detail: View>: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.sidebar = sidebar
        self.content = content
        self.detail = detail
    }
    // ...
}

// ContentView.swift – Binding durchreichen
AdaptiveLayoutView(columnVisibility: $columnVisibility) {
    sidebarColumn
} content: {
    noteListColumn
} detail: {
    detailColumn
}
```

### 🚨 [Cross-Platform] `DrawingCanvasView` vorhanden aber nicht in den Editor-Flow integriert
- **Schweregrad:** Mittel
- **Das Problem:** `DrawingCanvasView.swift` hat einen sauberen `#if canImport(PencilKit)` Guard mit macOS-Fallback. Jedoch wird `DrawingBlockView` nirgends im `NoteEditorView` eingebettet oder dynamisch aktiviert. Das Feature existiert als View, ist aber nicht verdrahtet.
- **Der Fix:** Integration in v1.1 – DrawingBlockView als inline-Block zwischen Markdown-Paragraphen einbetten.

---

## Säule 2: Architektur, Verdrahtung & Memory Management

### 🚨 [Architektur] ServiceContainer – VaultProvider wird nicht beim App-Start registriert
- **Schweregrad:** Hoch
- **Das Problem:** `QuartzApp.swift:21` registriert nur `featureGate` im Container. `vaultProvider` und `frontmatterParser` werden erst lazy bei `resolveVaultProvider()` erstellt. Wenn `ContentViewModel.openNote()` und `ContentViewModel.loadVault()` jeweils `resolveVaultProvider()` aufrufen, können sie verschiedene Instanzen erhalten (beim ersten Aufruf wird eine neue erstellt und cached, danach die gecachte zurückgegeben). Das ist korrekt, aber fragil – die Reihenfolge der Aufrufe bestimmt, ob alle denselben Provider verwenden.
- **Der Fix (Code):**
```swift
// QuartzApp.swift – Explizit alle Services beim Start bootstrappen
.task {
    ServiceContainer.shared.bootstrap(
        vaultProvider: FileSystemVaultProvider(frontmatterParser: FrontmatterParser()),
        frontmatterParser: FrontmatterParser(),
        featureGate: proFeatureGate
    )
    await proFeatureGate.checkPurchaseStatus()
    _ = proFeatureGate.observeTransactionUpdates()
}
```

### 🚨 [Memory] ContentViewModel wird in `.task` erstellt – potenziell doppelte Erstellung
- **Schweregrad:** Hoch
- **Das Problem:** `ContentView.swift:30` — `.task { viewModel = ContentViewModel(appState: appState) }`. Wenn die View bei Orientation-Change oder Window-Resize re-evaluated wird, kann `.task` erneut feuern und einen neuen ViewModel erstellen. Der alte ViewModel mit laufendem editorViewModel (und dessen autosaveTask) wird verworfen, ohne dass `cancelAllTasks()` aufgerufen wird.
- **Der Fix (Code):**
```swift
// ContentView.swift
.task {
    if viewModel == nil {
        viewModel = ContentViewModel(appState: appState)
    }
}
```

### 🚨 [Memory] NoteEditorViewModel Tasks nicht gecancelled bei Vault-Wechsel
- **Schweregrad:** Hoch
- **Das Problem:** `ContentViewModel.loadVault()` ersetzt `sidebarViewModel`, aber ruft **nicht** `editorViewModel?.cancelAllTasks()` auf. Der alte EditorViewModel hat möglicherweise noch einen laufenden `autosaveTask`, der nach dem Vault-Wechsel versucht, in den alten Vault zu schreiben.
- **Der Fix (Code):**
```swift
// ContentViewModel.swift
public func loadVault(_ vault: VaultConfig) {
    // Cancel previous editor tasks before replacing
    editorViewModel?.cancelAllTasks()
    editorViewModel = nil

    let provider = ServiceContainer.shared.resolveVaultProvider()
    let viewModel = SidebarViewModel(vaultProvider: provider)
    sidebarViewModel = viewModel
    // ... rest
}
```

### 🚨 [Architektur] `collectNotes(from:)` in ContentView – O(n) Rekursion bei jedem Render
- **Schweregrad:** Mittel
- **Das Problem:** `ContentView.swift:185-196` traversiert rekursiv den gesamten Dateibaum bei jedem Render der `noteListColumn`. Bei großen Vaults (1000+ Notizen) unnötige CPU-Last auf dem Main Thread.
- **Der Fix (Code):**
```swift
// SidebarViewModel.swift – Flache Notes-Liste als cached property
public var flatNotes: [FileNode] {
    if let cached = cachedFlatNotes { return cached }
    let result = collectNotesFromTree(filteredTree)
    cachedFlatNotes = result
    return result
}
private var cachedFlatNotes: [FileNode]?

private func invalidateFilterCache() {
    cachedFilteredTree = nil
    cachedFlatNotes = nil
}
```

### 🚨 [Architektur] `nonisolated(unsafe)` EnvironmentKey Default Values
- **Schweregrad:** Mittel
- **Das Problem:** `AppearanceManager.swift:78` und `FocusModeManager.swift:40` verwenden `nonisolated(unsafe) static let defaultValue`. Das ist ein bekannter Swift 6 Workaround für `@MainActor`-isolierte EnvironmentKey-Defaults. Korrekt, aber sollte dokumentiert werden.
- **Der Fix (Code):**
```swift
private struct AppearanceManagerKey: EnvironmentKey {
    // SAFETY: Default only accessed from main actor in SwiftUI's
    // environment resolution. Swift 6 EnvironmentKey workaround.
    nonisolated(unsafe) static let defaultValue = AppearanceManager()
}
```

---

## Säule 3: Exception Handling & Edge Cases

### 🚨 [Exception] CloudSyncService – kein iCloud-Verfügbarkeitsprüfung vor Monitoring-Start
- **Schweregrad:** Hoch
- **Das Problem:** `CloudSyncService.swift:27` – `startMonitoring(vaultRoot:)` erstellt eine NSMetadataQuery und startet sie, ohne zu prüfen, ob iCloud verfügbar ist. Wenn kein iCloud-Account eingerichtet ist, gibt der Stream keine Ergebnisse und der Consumer bekommt keine Fehlermeldung.
- **Der Fix (Code):**
```swift
public func startMonitoring(vaultRoot: URL) -> AsyncStream<(URL, CloudSyncStatus)> {
    guard Self.isAvailable else {
        return AsyncStream { $0.finish() }
    }
    // ... existing code
}
```

### 🚨 [Exception] FileSystemVaultProvider.buildTree – keine Tiefenbegrenzung
- **Schweregrad:** Hoch
- **Das Problem:** `FileSystemVaultProvider.swift:187` – `buildTree()` rekursiert ohne Tiefenlimit. APFS Firmlinks oder pathologisch tiefe Ordnerstrukturen können zu Stack Overflow führen. Symlinks werden korrekt gefiltert (Zeile 202), aber Hard Links nicht.
- **Der Fix (Code):**
```swift
private func buildTree(at url: URL, relativeTo root: URL, depth: Int = 0) throws -> [FileNode] {
    guard depth < 50 else { return [] }
    // ... existing code, passing depth + 1 in recursive call
}
```

### 🚨 [Exception] OnboardingView – Security-Scoped Resource Leak bei Ordnerwechsel
- **Schweregrad:** Hoch
- **Das Problem:** `OnboardingView.swift:143` ruft `url.startAccessingSecurityScopedResource()` auf. Wenn der User im Template-Schritt auf "Back" klickt und einen anderen Ordner wählt, wird die erste URL nie mit `stopAccessingSecurityScopedResource()` balanciert.
- **Der Fix (Code):**
```swift
// OnboardingView.swift – fileImporter result handler
if case .success(let urls) = result, let url = urls.first {
    // Release previous security scope before acquiring new one
    if let previous = vaultURL, previous != url {
        previous.stopAccessingSecurityScopedResource()
    }
    guard url.startAccessingSecurityScopedResource() else { return }
    vaultURL = url
    currentStep = .chooseTemplate
}
```

### 🚨 [Exception] VaultPickerView – Bookmark-Key kollidiert bei gleichnamigen Vaults
- **Schweregrad:** Mittel
- **Das Problem:** `VaultPickerView.swift:97` speichert Bookmarks unter `"quartz.vault.bookmark.\(url.lastPathComponent)"`. Zwei Vaults namens "Notes" überschreiben sich gegenseitig.
- **Der Fix (Code):**
```swift
// UUID-basierten Key verwenden
let bookmarkKey = "quartz.vault.bookmark.\(vault.id.uuidString)"
UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
```

### 🚨 [Exception] NoteEditorViewModel.save() – keine Re-Entry-Protection
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorViewModel.swift:61-80` – `save()` prüft `isDirty` aber nicht `isSaving`. Wenn der User schnell ⌘S drückt während ein Autosave läuft, können zwei Saves gleichzeitig starten.
- **Der Fix (Code):**
```swift
public func save() async {
    guard var currentNote = note, isDirty, !isSaving else { return }
    isSaving = true
    // ... rest
}
```

### 🚨 [Exception] VectorEmbeddingService – binäres Index-Format ohne Migrations-Strategie
- **Schweregrad:** Mittel
- **Das Problem:** `VectorEmbeddingService.swift:55` definiert `formatVersion: UInt32 = 1`. Wenn sich das Format ändert, wirft `decodeBinary` `.unsupportedVersion`. Es gibt keinen Migrations-Pfad – der alte Index wird einfach unlesbar. Bei 10.000 indizierten Notizen müsste der gesamte Index neu gebaut werden.
- **Der Fix:** Akzeptabel für v1.0. Für v2.0: Migration-Handler der Version 1 → 2 konvertiert.

---

## Säule 4: Apple Design Awards Level UI/UX & HIG

### 🚨 [HIG] Alle Animationen respektieren `accessibilityReduceMotion` – EXZELLENT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. Alle 12 Animation-Modifier in `LiquidGlass.swift` prüfen `@Environment(\.accessibilityReduceMotion)`. `FloatingButtonStyle`, `QuartzPressButtonStyle`, `QuartzCardButtonStyle`, `QuartzBounceButtonStyle` – alle haben den Check. `QuartzTagBadge` hat ihn ebenfalls. **Volle Punktzahl.**

### 🚨 [HIG] Spring Animations – konsistentes, zentralisiertes System – EXZELLENT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `QuartzAnimation.swift` definiert 17 vordefinierte Spring-Animationen mit dokumentierten response/dampingFraction-Werten. Keine einzige View nutzt hardcodierte Animation-Werte. Einzige Ausnahme: `shimmer` nutzt korrekterweise `.linear`. **Apple Design Award-Level.**

### 🚨 [HIG] Touch Targets 44x44pt – konsequent eingehalten – EXZELLENT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `FormattingToolbar.swift:101` – `frame(minWidth: 44, minHeight: 44)`. `FrontmatterEditorView.swift:85,103,163` – `frame(minWidth: 44, minHeight: 44)`. Alle interaktiven Elemente haben korrekte Touch-Target-Größen.

### 🚨 [HIG] `FileNodeRow` Padding zu gering
- **Schweregrad:** UI-Polish
- **Das Problem:** `FileNodeRow.swift:39` – `.padding(.vertical, 1)`. Visuell zu eng. Apple Notes hat mindestens 6-8pt.
- **Der Fix (Code):**
```swift
.padding(.vertical, 4)
```

### 🚨 [HIG] macOS Focus States – nur FileNodeRow hat `.focusable()`
- **Schweregrad:** Hoch
- **Das Problem:** `FileNodeRow.swift:43` hat `#elseif os(macOS) .focusable()`. Aber `QuartzButton`, Template-Cards im Onboarding, Tag-Badges haben keine Focus-State-Unterstützung. Die App ist per Tab-Taste nicht vollständig navigierbar auf macOS.
- **Der Fix (Code):**
```swift
// QuartzButton.swift
Button(action: action) { /* ... */ }
    .buttonStyle(QuartzPressButtonStyle())
    #if os(macOS)
    .focusable()
    #endif
```

### 🚨 [HIG] `QuartzEmptyState` – Missing Accessibility-Zusammenfassung
- **Schweregrad:** UI-Polish
- **Das Problem:** `LiquidGlass.swift:659-689` – VoiceOver liest Icon, Titel und Subtitle als drei separate Elemente.
- **Der Fix (Code):**
```swift
public var body: some View {
    VStack(spacing: 16) { /* ... */ }
    .padding(40)
    .accessibilityElement(children: .combine)
}
```

### 🚨 [HIG] Haptics – subtil und HIG-konform – EXZELLENT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `.sensoryFeedback(.success)` bei manuellem Speichern, `.sensoryFeedback(.impact)` bei Focus-Mode-Toggle, `.sensoryFeedback(.selection)` bei Tag-Auswahl, `.sensoryFeedback(.warning)` bei Deletion. Autosave triggert bewusst KEINE Haptic. **Perfekt.**

---

## Säule 5: Lokalisation (L10n) & Internationalisierung (I18n)

### 🚨 [L10n] `VectorEmbeddingService` – Hardcoded `.german` Language Default
- **Schweregrad:** Kritisch
- **Das Problem:** `VectorEmbeddingService.swift:48` – `language: NLLanguage = .german`. Alle User bekommen standardmäßig deutsche Sentence-Embeddings. Für englische, französische, japanische User liefert die semantische Suche signifikant schlechtere Ergebnisse.
- **Der Fix (Code):**
```swift
public init(
    vaultURL: URL,
    chunkSize: Int = 512,
    language: NLLanguage = .english // Internationaler Default
) {
    // ...
}

// Idealerweise: automatische Spracherkennung pro Chunk
private func detectLanguage(for text: String) -> NLLanguage {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return recognizer.dominantLanguage ?? .english
}
```

### 🚨 [L10n] `AudioRecordingService.formattedDuration` – hardcodiertes Zeitformat
- **Schweregrad:** Mittel
- **Das Problem:** `AudioRecordingService.swift:199` – `String(format: "%02d:%02d", ...)` nutzt westliche Ziffern. Locales mit arabischen Ziffern (z.B. `ar_SA`) zeigen keine nativen Ziffern.
- **Der Fix (Code):**
```swift
public var formattedDuration: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: duration) ?? "00:00"
}
```

### 🚨 [L10n] Datums/Zeit-Formate in FrontmatterEditorView – korrekt locale-aware
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `FrontmatterEditorView.swift:119,125` nutzt `Text(date, style: .date)` und `Text(date, style: .relative)` – automatisch locale-aware. `ContentViewModel.createDailyNote()` nutzt `en_US_POSIX` für ISO-Dateinamen. **Perfekt.**

### 🚨 [L10n] Pluralisierung korrekt via `inflect: true`
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `NoteEditorView.swift:133` und `FrontmatterEditorView.swift:185` nutzen `^[\(count) word](inflect: true)` / `^[\(count) tag](inflect: true)`. Automatische Grammatik-Anpassung für alle unterstützten Sprachen.

### 🚨 [L10n] RTL-Layout architektonisch vorbereitet, aber nicht getestet
- **Schweregrad:** Mittel
- **Das Problem:** SwiftUI handhabt RTL automatisch. `MarkdownTextView` hat symmetrische Insets (left: 12, right: 12 auf iOS; width: 12 auf macOS). Kein systematischer RTL-Test vorhanden. Arabisch und Hebräisch sind nicht in den 7 Basis-Sprachen enthalten.
- **Der Fix:** RTL-Pseudo-Language im Xcode-Schema für visuelles Testing aktivieren.

---

## Säule 6: Performance & Device Capabilities

### 🚨 [Performance] `FileSystemVaultProvider.buildTree` – synchrones I/O blockiert Actor
- **Schweregrad:** Hoch
- **Das Problem:** `FileSystemVaultProvider.swift:187-236` – `buildTree()` ist synchron und rekursiv. Da `FileSystemVaultProvider` ein Actor ist, serialisiert er alle Calls. Bei 5000 Dateien blockiert `buildTree` den Actor für Sekunden, während derer kein `readNote`, `saveNote` etc. ausgeführt werden kann. Das betrifft nicht den Main Thread direkt, aber blockiert alle File-Operationen.
- **Der Fix (Code):**
```swift
public func loadFileTree(at root: URL) async throws -> [FileNode] {
    vaultRoot = root
    return try await Task.detached(priority: .userInitiated) {
        [fileManager, frontmatterParser] in
        try Self.buildTreeStatic(at: root, relativeTo: root,
                                  fileManager: fileManager)
    }.value
}
```

### 🚨 [Performance] VaultSearchIndex – doppelter `loadFileTree` Call
- **Schweregrad:** Hoch
- **Das Problem:** `VaultSearchIndex.swift:31` – `buildIndex()` ruft `vaultProvider.loadFileTree(at: root)` auf. `ContentViewModel.loadVault()` hat bereits `loadTree(at: vault.rootURL)` in Zeile 32 aufgerufen. Der Dateibaum wird also **zweimal** vollständig gelesen – einmal für die Sidebar, einmal für den Suchindex.
- **Der Fix (Code):**
```swift
// ContentViewModel.swift – Dateibaum nur einmal laden und teilen
public func loadVault(_ vault: VaultConfig) {
    let provider = ServiceContainer.shared.resolveVaultProvider()
    let sidebarVM = SidebarViewModel(vaultProvider: provider)
    sidebarViewModel = sidebarVM

    let index = VaultSearchIndex(vaultProvider: provider)
    searchIndex = index

    Task {
        await sidebarVM.loadTree(at: vault.rootURL)
        // Nutze den bereits geladenen Baum für den Suchindex
        await index.indexNodes(sidebarVM.fileTree)
    }
}
```

### 🚨 [Performance] `MarkdownTextView` – Re-Rendering nur bei Nicht-First-Responder – KORREKT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `MarkdownTextView.swift:100` (iOS) prüft `!uiView.isFirstResponder` und `MarkdownTextView.swift:217` (macOS) prüft `textView.window?.firstResponder !== textView`. Das verhindert Re-Rendering während der User tippt. **Gut gelöst.**

### 🚨 [Performance] `AudioRecordingService` Timer auf @MainActor – 12Hz UI-Updates
- **Schweregrad:** Mittel
- **Das Problem:** `AudioRecordingService.swift:205` – Metering-Timer feuert alle 83ms. Da die Klasse `@Observable` ist, triggert jede Property-Änderung (`currentLevel`, `peakLevel`, `levelHistory`) SwiftUI-Updates. Das sind 12 Re-Renders pro Sekunde nur für die Wellenform.
- **Der Fix:** Akzeptabel für die Aufnahme-View. Optional: `levelHistory` in einer separaten, nicht-`@Observable` Property speichern und nur bei sichtbarer Wellenform-View Readings propagieren.

### 🚨 [Performance] Sensory Feedback korrekt eingesetzt – EXZELLENT
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. Haptics werden sparsam und nur bei expliziten User-Aktionen eingesetzt. Kein Haptic bei Autosave. Kein Haptic bei Scroll. Kein Haptic bei Hover. **HIG-konform.**

---

## Zusätzliche Befunde

### 🚨 [Security] Deep Link Path Traversal – korrekt abgesichert
- **Schweregrad:** UI-Polish (Positiv!)
- **Das Problem:** Kein Problem. `AdaptiveLayoutView.swift:136-137` prüft korrekt `noteURL.standardizedFileURL.path().hasPrefix(vaultRoot.standardizedFileURL.path())`. Auch `FileSystemVaultProvider.rename()` (Zeile 105) und `createFolder()` (Zeile 125) haben die gleiche Prüfung. **Path Traversal ist verhindert.**

### 🚨 [Security] VaultEncryptionService – Feature-Gap
- **Schweregrad:** Hoch
- **Das Problem:** `Frontmatter.isEncrypted` und `VaultConfig.encryptionEnabled` existieren als Properties, aber `VaultEncryptionService` wurde im Audit nicht als vollständige Implementierung gefunden. User könnten erwarten, dass Encryption funktioniert.
- **Der Fix:** Feature hinter Feature-Flag verstecken bis Implementierung abgeschlossen. Toggle im UI als "Coming Soon" markieren.

### 🚨 [Security] VaultPickerView – Security-Scoped Resources akkumulieren
- **Schweregrad:** Hoch
- **Das Problem:** `VaultPickerView.swift:108-111` – `stopAccessingSecurityScopedResource()` wird bewusst nicht aufgerufen (Kommentar erklärt warum). Aber bei Vault-Wechseln akkumulieren sich die Resources. Apple empfiehlt streng balanciertes Start/Stop.
- **Der Fix (Code):**
```swift
// In AppState oder ContentView beim Vault-Wechsel
func switchVault(from oldVault: VaultConfig?, to newVault: VaultConfig) {
    oldVault?.rootURL.stopAccessingSecurityScopedResource()
    currentVault = newVault
}
```

---

## Gesamtnote

### 📊 A- (90/100)

**Signifikante Verbesserung gegenüber v2.0 (B+).**

**Herausragend:**
- Saubere 3-Layer-Architektur (Data/Domain/Presentation) mit klarer Protocol-basierter Trennung
- Modernes Swift 6: `@Observable`, `actor`, `Sendable`, Structured Concurrency durchgängig korrekt
- Exzellentes Design-System: LiquidGlass-Komponenten, 17 zentrale Spring-Animations, Material-Effekte
- Vorbildliche Accessibility: `accessibilityReduceMotion` in ALLEN 12+ Modifiers, VoiceOver Labels/Hints, Dynamic Type via `@ScaledMetric`
- Konsistente Lokalisierung: 7 Sprachen, String Catalogs, `inflect: true` Pluralisierung
- Subtile, HIG-konforme Haptics (nur bei expliziten User-Aktionen)
- `CoordinatedFileWriter` für iCloud-sichere File-Ops
- NSFileCoordinator im VaultProvider für koordiniertes Lesen/Schreiben
- Path Traversal Prevention in Deep Links und File Operations
- Touch Targets konsequent 44x44pt

**Was den Apple Design Award verhindert:**
1. `listStyle(.insetGrouped)` – macOS Compilation Failure (Kritisch)
2. `VectorEmbeddingService` hardcoded `.german` (Kritisch – internationale User betroffen)
3. `columnVisibility` Duplikation – Sidebar-Toggle broken (Hoch)
4. Doppelter `loadFileTree` Call – Performance-Verschwendung (Hoch)
5. Security-Scoped Resource Leaks bei Vault-Wechsel (Hoch)

---

## Top 3 Architektur-Prioritäten

### 1. 🔴 Cross-Platform Fix: `listStyle(.insetGrouped)` + `columnVisibility` Binding
**Impact:** App kompiliert nicht auf macOS + Sidebar-Toggle-Shortcut ist broken.
**Aufwand:** 30 Minuten. Einfachster Fix mit dem größten Impact.

### 2. 🔴 L10n Fix: `VectorEmbeddingService` Language Detection statt hardcoded `.german`
**Impact:** Semantische Suche funktioniert nur gut für deutsche Texte. Alle anderen Sprachen leiden.
**Aufwand:** 1 Stunde. `NLLanguageRecognizer` für automatische Detection pro Chunk.

### 3. 🟡 Performance: Doppeltes `loadFileTree` eliminieren + `buildTree` vom Actor auslagern
**Impact:** Vault-Öffnung dauert doppelt so lang wie nötig. Actor-Blockade bei großen Vaults.
**Aufwand:** 2 Stunden. Shared Tree zwischen Sidebar und SearchIndex, `Task.detached` für I/O.

---

*Audit v3.0 durchgeführt am 17. März 2026. Die Codebase ist nah an Apple-Design-Award-Level. Die Top-3 Fixes bringen sie in die "Submission-Ready" Kategorie.*
