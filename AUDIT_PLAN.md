# Quartz Code Review Audit Plan
## Staff iOS/macOS Engineer × Apple Design Award Judge

**Datum:** 16. März 2026
**Scope:** 69 Swift-Dateien, ~8.500 LOC (QuartzKit Framework)
**Swift Tools Version:** 6.0 | Plattformen: iOS 18+, macOS 15+

---

## Säule 1: Cross-Platform & Compiler-Kompatibilität

### 🚨 [Cross-Platform] DrawingCanvasView hat keinen macOS-Fallback
- **Schweregrad:** Kritisch
- **Das Problem:** `DrawingCanvasView.swift` ist komplett in `#if canImport(PencilKit) && canImport(UIKit)` gewrapped. Auf macOS existiert kein View — jede Referenz auf `DrawingBlockView` in Shared-Code erzeugt einen Compiler-Fehler oder ein fehlendes Feature ohne Feedback.
- **Der Fix:**
```swift
// Am Ende von DrawingCanvasView.swift hinzufügen:
#else
/// macOS Fallback – Drawing nicht unterstützt.
public struct DrawingBlockView: View {
    let drawingID: String
    let height: CGFloat

    public init(drawingID: String, initialDrawing: Any? = nil, height: CGFloat = 300, onSave: ((Any) -> Void)? = nil) {
        self.drawingID = drawingID
        self.height = height
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.tip.crop.circle.badge.minus")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(String(localized: "Drawing is only available on iPad", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(.fill.quaternary))
    }
}
#endif
```

### 🚨 [Cross-Platform] AudioRecordingService fehlt macOS Audio Session Setup
- **Schweregrad:** Hoch
- **Das Problem:** `AudioRecordingService.swift:96-104` — Audio Session Setup nur für iOS implementiert. Auf macOS wird die Audio-Session nie konfiguriert, AVAudioRecorder könnte mit Default-Einstellungen scheitern oder schlechte Audio-Qualität liefern.
- **Der Fix:**
```swift
private func setupAudioSession() throws {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
    #elseif os(macOS)
    // macOS benötigt keine explizite Audio Session, aber Microphone-Permission prüfen
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: break
    case .notDetermined:
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw RecordingError.permissionDenied }
    default:
        throw RecordingError.permissionDenied
    }
    #endif
}
```

### 🚨 [Cross-Platform] QuickNotePanel existiert nur auf macOS
- **Schweregrad:** Mittel
- **Das Problem:** `QuickNotePanel.swift` ist `#if os(macOS)` — korrekt. Aber `QuickNoteView.swift` wird auf beiden Plattformen kompiliert und referenziert `QuickNotePanel` nicht. Das ist in Ordnung, aber es fehlt ein iOS-Äquivalent für Quick Capture (z.B. via Live Activities oder Dynamic Island).
- **Der Fix:** Designentscheidung — kein Code-Fix nötig, aber Feature-Parity prüfen.

### 🚨 [Cross-Platform] Widget ControlWidget nur iOS
- **Schweregrad:** Mittel
- **Das Problem:** `QuartzControlWidget.swift:1` — `#if canImport(WidgetKit) && canImport(AppIntents) && os(iOS)`. Control Widgets sind iOS-only, korrekt. Aber `QuickNoteControlIntent` ist `@available(iOS 18.0, macOS 15.0, *)` deklariert — wird auf macOS nie kompiliert wegen der äußeren `#if os(iOS)` Guard. Inkonsistente Availability-Deklaration.
- **Der Fix:** `@available(iOS 18.0, *)` ohne macOS-Deklaration innerhalb des iOS-Blocks.

---

## Säule 2: Architektur, Verdrahtung & Memory Management

### 🚨 [Architektur] NoteChatSession/VaultChatSession gehören in Presentation, nicht Domain
- **Schweregrad:** Hoch
- **Das Problem:** `NoteChatService.swift:89-90` und `VaultChatService.swift:171` — `NoteChatSession` und `VaultChatSession` sind `@Observable @MainActor` — das sind ViewModel-Klassen, die direkt an SwiftUI gebunden sind. Sie leben im Domain-Layer (`Domain/AI/`), verletzen Clean Architecture.
- **Der Fix:** Diese Klassen in `Presentation/Editor/` oder `Presentation/Chat/` verschieben. Domain sollte nur die AI-Provider-Protokolle und Use Cases enthalten.

### 🚨 [Architektur] VaultSearchIndex lebt im falschen Layer
- **Schweregrad:** Mittel
- **Das Problem:** `VaultSearchIndex.swift` liegt in `Data/FileSystem/`, hängt aber von `VaultProviding` (Domain-Protokoll) ab. Invertierte Abhängigkeit — Data darf nicht von Domain abhängen.
- **Der Fix:** Index-Logik in Domain verschieben, nur die Persistenz (Disk I/O) in Data lassen.

### 🚨 [Architektur] ServiceContainer nutzt Singleton statt Environment-Injection
- **Schweregrad:** Hoch
- **Das Problem:** `ServiceContainer.shared` ist ein `@MainActor` Singleton. In SwiftUI sollten Services via `@Environment` injiziert werden, nicht über einen globalen Container. Das macht Testing schwieriger und verstößt gegen SwiftUI-Idiome.
- **Der Fix:**
```swift
// EnvironmentKey-basierte Injection (zusätzlich zum Container)
private struct VaultProviderKey: EnvironmentKey {
    static let defaultValue: any VaultProviding = FileSystemVaultProvider(
        frontmatterParser: FrontmatterParser()
    )
}

extension EnvironmentValues {
    public var vaultProvider: any VaultProviding {
        get { self[VaultProviderKey.self] }
        set { self[VaultProviderKey.self] = newValue }
    }
}
```

### 🚨 [Memory] Potentielle Retain Cycles in QuickNoteManager
- **Schweregrad:** Hoch
- **Das Problem:** `QuickNotePanel.swift:72-82` — `NSEvent.addGlobalMonitorForEvents` mit `[weak self]` ist korrekt. ABER: `deinit` auf Zeile 120-127 wird bei `@MainActor` Klassen nie auf dem Main Thread aufgerufen werden — `NSEvent.removeMonitor` ist nicht thread-safe.
- **Der Fix:**
```swift
deinit {
    // Event monitors müssen explizit via unregisterHotkey() entfernt werden
    // bevor der Manager deallokiert wird, da deinit nicht @MainActor-isoliert ist.
    if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
}
```
Besser: `unregisterHotkey()` explizit beim Teardown aufrufen statt sich auf deinit zu verlassen.

### 🚨 [Memory] AppState hält alle Command-Trigger als Bool-Toggle
- **Schweregrad:** Mittel
- **Das Problem:** `AppState.swift:24-35` — 6 separate `Bool`-Properties für Command Actions (`newNoteAction`, `searchAction`, etc.) die per Toggle ausgelöst werden. Jeder Toggle erzeugt zwei SwiftUI-View-Updates (true → false). Stattdessen sollte ein einzelner Published enum verwendet werden.
- **Der Fix:**
```swift
public enum CommandAction: Equatable {
    case none
    case newNote, newFolder, search, globalSearch, toggleSidebar, dailyNote
}

@Observable @MainActor
public final class AppState {
    public var currentVault: VaultConfig?
    public var fileTree: [FileNode] = []
    public var selectedNote: NoteDocument?
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var pendingCommand: CommandAction = .none
    public init() {}
}
```

### 🚨 [Memory] VaultSearchIndex unbounded Task-Erstellung
- **Schweregrad:** Hoch
- **Das Problem:** `VaultSearchIndex.swift:117-125` — `withTaskGroup` erstellt für jede Notiz einen eigenen Task. Bei 10.000+ Notizen entstehen tausende gleichzeitige Tasks mit jeweils einer File-I/O-Operation. Kann System-Ressourcen erschöpfen.
- **Der Fix:**
```swift
// Begrenzte Parallelität mit TaskGroup
await withTaskGroup(of: (URL, SearchEntry?).self) { group in
    let maxConcurrency = 16
    var pending = 0
    for note in notes {
        if pending >= maxConcurrency {
            if let result = await group.next() { /* process */ }
            pending -= 1
        }
        group.addTask { /* index note */ }
        pending += 1
    }
    for await result in group { /* process */ }
}
```

---

## Säule 3: Exception Handling & Edge Cases

### 🚨 [Error Handling] Fehlende NSFileCoordinator in 3 kritischen Services
- **Schweregrad:** Kritisch
- **Das Problem:**
  - `MeetingMinutesService.swift:115` — `FileManager.default.createDirectory()` direkt, ohne Coordination
  - `VaultTemplateService.swift:23-65` — Template-Erstellung schreibt direkt ohne Coordination
  - `AssetManager.swift:38, 64, 92, 105` — Direkte FileManager-Calls

  Bei iCloud-Sync kann dies zu Datenverlust, Konflikten oder korrupten Dateien führen.
- **Der Fix:** Alle File-Writes über den existierenden `coordinatedWrite()`-Pattern aus `FileSystemVaultProvider` leiten. Einen gemeinsamen `CoordinatedFileWriter` extrahieren:
```swift
public struct CoordinatedFileWriter: Sendable {
    public func write(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { actualURL in
            do { try data.write(to: actualURL, options: .atomic) }
            catch { writeError = error }
        }
        if let error = coordinatorError ?? writeError { throw error }
    }
}
```

### 🚨 [Error Handling] Silent Failures in DrawingStorageService
- **Schweregrad:** Hoch
- **Das Problem:** `DrawingStorageService.swift:65-70` — Thumbnail-Löschung fehlschlägt nur als Debug-Log. Zeile 83-86: `listDrawings()` gibt bei jedem Fehler leeres Array zurück — Caller kann "keine Zeichnungen" nicht von "Lesefehler" unterscheiden.
- **Der Fix:** `listDrawings()` sollte `throws` sein und Fehler propagieren.

### 🚨 [Error Handling] ShareCaptureUseCase liest Datei unkoordiniert
- **Schweregrad:** Hoch
- **Das Problem:** `ShareCaptureUseCase.swift:82` — `String(contentsOf: inboxURL)` liest ohne NSFileCoordinator. Wenn iCloud den File gerade synchronisiert, kann ein teilweise geschriebener File gelesen werden.
- **Der Fix:** Auch Reads über `NSFileCoordinator.coordinate(readingItemAt:)` leiten.

### 🚨 [Error Handling] DateFormatter ohne POSIX Locale in appendToInbox
- **Schweregrad:** Mittel
- **Das Problem:** `ShareCaptureUseCase.swift:73-74` — `ISO8601DateFormatter()` wird jedes Mal neu instanziiert (teuer). Und `timeFormatter` auf Zeile 74-77 nutzt `Locale.autoupdatingCurrent` für die Time-Anzeige, aber der ISO8601-Formatter auf Zeile 73 hat keine explizite Locale.
- **Der Fix:** Static lazy Formatter verwenden:
```swift
private static let iso8601Formatter = ISO8601DateFormatter()
private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()
```

### 🚨 [Error Handling] SpeakerDiarizationService K-Means ohne Konvergenz-Check
- **Schweregrad:** Mittel
- **Das Problem:** `SpeakerDiarizationService.swift:214-260` — K-Means Clustering läuft immer genau 20 Iterationen, ohne auf Konvergenz zu prüfen. Verschwendet CPU-Zyklen wenn Centroids nach 5 Iterationen stabil sind.
- **Der Fix:** Early stopping bei Centroid-Stabilität (delta < epsilon).

### 🚨 [Error Handling] Widgets geben nie echte Daten zurück
- **Schweregrad:** Kritisch
- **Das Problem:** `QuartzWidgets.swift:41-46` — `LatestNoteProvider.getTimeline()` gibt immer den Placeholder zurück. Widget zeigt nie echte Notiz-Daten. `PinnedNotesEntry.placeholder` enthält hardcodierte englische Strings ("Meeting Notes", "Shopping List") die nie lokalisiert werden.
- **Der Fix:** Timeline Provider muss Vault über App Group lesen und echte Daten liefern. `PinnedNotesEntry.placeholder` Strings lokalisieren.

---

## Säule 4: Apple Design Awards Level UI/UX & HIG

### 🚨 [HIG] StageManagerModifier.handleDeepLink ist leer
- **Schweregrad:** Hoch
- **Das Problem:** `AdaptiveLayoutView.swift:128-132` — `handleDeepLink()` hat einen leeren Body. Deep Links tun nichts. Jeder `quartz://` URL-Aufruf wird stillschweigend ignoriert.
- **Der Fix:** Deep Link Handler implementieren:
```swift
private func handleDeepLink(_ url: URL) {
    guard url.scheme == "quartz" else { return }
    switch url.host() {
    case "note":
        let path = url.pathComponents.dropFirst().joined(separator: "/")
        // Navigate to note via AppState
    case "new":
        // Trigger new note action
    case "daily":
        // Trigger daily note
    default:
        break
    }
}
```

### 🚨 [HIG] Shimmer-Animation nutzt easeInOut statt linear
- **Schweregrad:** UI-Polish
- **Das Problem:** `LiquidGlass.swift:371` — Shimmer-Effekt nutzt `.easeInOut(duration: 1.5).repeatForever(autoreverses: false)`. Shimmer-Effekte sollten `linear` verwenden für gleichmäßige Bewegung. `.easeInOut` erzeugt einen sichtbaren "Pause"-Effekt am Anfang und Ende jeder Iteration.
- **Der Fix:**
```swift
.onAppear {
    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
        phase = 2
    }
}
```
**Anmerkung:** Die PulseModifier-Änderung zu spring ist korrekt, aber der ShimmerModifier sollte bewusst linear bleiben — hier ist easeInOut der eigentliche Fehler, nicht linear.

### 🚨 [HIG] FormattingToolbar Buttons fehlen Accessibility Hints
- **Schweregrad:** Mittel
- **Das Problem:** `FormattingToolbar.swift:96-107` — Buttons haben `accessibilityLabel` aber keine `accessibilityHint`. VoiceOver-Nutzer wissen nicht, was passiert wenn sie den Button aktivieren.
- **Der Fix:**
```swift
.accessibilityLabel(action.label)
.accessibilityHint(String(localized: "Double tap to apply \(action.label) formatting", bundle: .module))
```

### 🚨 [HIG] NoteEditorView hat kein matchedGeometryEffect für Übergänge
- **Schweregrad:** UI-Polish
- **Das Problem:** Beim Wechsel zwischen Notizen gibt es keinen fließenden Übergang. Apple Notes nutzt Hero-Transitions. Quartz springt hart von einer Notiz zur nächsten.
- **Der Fix:** `matchedGeometryEffect(id:in:)` zwischen Sidebar-Item und Editor-Titel für fluide Übergänge.

### 🚨 [HIG] DrawingThumbnailView rendert synchron auf Main Thread
- **Schweregrad:** Hoch
- **Das Problem:** `DrawingCanvasView.swift:190-194` — `drawing.image(from:scale:)` ist eine synchrone Render-Operation die bei komplexen Zeichnungen den Main Thread blockiert und 120Hz-Scrolling zerstört.
- **Der Fix:**
```swift
// Async Thumbnail Rendering
.task(id: drawing.bounds) {
    let img = await Task.detached(priority: .userInitiated) {
        drawing.image(from: drawing.bounds, scale: 2.0)
    }.value
    renderedImage = img
}
```

---

## Säule 5: Lokalisation (L10n) & Internationalisierung (I18n)

### 🚨 [L10n] Widget-Strings nicht lokalisiert
- **Schweregrad:** Hoch
- **Das Problem:** `QuartzWidgets.swift:200-202` — Hardcodierte englische Strings in Placeholder-Daten:
  ```swift
  PinnedNote(title: "Meeting Notes", icon: "doc.text"),
  PinnedNote(title: "Shopping List", icon: "checklist"),
  PinnedNote(title: "Project Ideas", icon: "lightbulb"),
  ```
- **Der Fix:**
```swift
PinnedNote(title: String(localized: "Meeting Notes", bundle: .module), icon: "doc.text"),
PinnedNote(title: String(localized: "Shopping List", bundle: .module), icon: "checklist"),
PinnedNote(title: String(localized: "Project Ideas", bundle: .module), icon: "lightbulb"),
```

### 🚨 [L10n] AppIntents shortTitle nicht über String Catalogs
- **Schweregrad:** Hoch
- **Das Problem:** `QuartzAppIntents.swift:91, 101` — `shortTitle: "New Note"` und `shortTitle: "Daily Note"` sind bare Strings, nicht lokalisiert. AppShortcutsProvider-Strings müssen `LocalizedStringResource` sein.
- **Der Fix:**
```swift
shortTitle: LocalizedStringResource("New Note", bundle: .atURL(Bundle.module.bundleURL)),
```

### 🚨 [L10n] Kein RTL-Support
- **Schweregrad:** Mittel
- **Das Problem:** Kein einziger `layoutDirection`-Check in der gesamten Codebase. Kein `.flipsForRightToLeftLayoutDirection`. SwiftUI handhabt vieles automatisch, aber manuell gesetzte Paddings und HStack-Layouts mit festen leading/trailing-Werten können in RTL-Sprachen (Arabisch, Hebräisch) brechen.
- **Der Fix:** Alle hardkodierten `.padding(.leading, X)` zu `.padding(.leading, X)` sind OK in SwiftUI (werden automatisch geflippt), aber manuelle `CGFloat`-Offsets in Canvas-Code (OnboardingView MeshGradient) müssen geprüft werden. Test mit RTL-Pseudo-Language in Xcode Schema Settings.

### 🚨 [L10n] Kein Pluralisierungs-Support in String Catalogs
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorView.swift:110` referenziert Plural Rules für Word Count, aber die .xcstrings-Datei enthält keine `plural`-Einträge. Pluralisierung fehlt komplett.
- **Der Fix:** In `Localizable.xcstrings` Plural-Varianten für `%lld words` hinzufügen mit `one`/`other` Kategorien für jede Sprache.

### 🚨 [L10n] BiometricAuthService hardcodierter Default-Reason
- **Schweregrad:** Mittel
- **Das Problem:** `BiometricAuthService.swift:54` — `reason: String = "Unlock Quartz"` als Default-Parameter. Nicht lokalisiert. Wird dem System-Biometrie-Dialog angezeigt.
- **Der Fix:**
```swift
public func authenticate(
    reason: String = String(localized: "Unlock Quartz", bundle: .module)
) async -> AuthResult {
```

### 🚨 [L10n] VaultChatService hardcodierte Fallback-Strings
- **Schweregrad:** Mittel
- **Das Problem:** `VaultChatService.swift:61, 120` — `"Unknown Note"` und `"Unknown"` sind nicht lokalisiert.
- **Der Fix:** `String(localized: "Unknown Note", bundle: .module)`

---

## Säule 6: Performance & Device Capabilities

### 🚨 [Performance] VaultSearchIndex O(n) Suche über alle Notizen
- **Schweregrad:** Hoch
- **Das Problem:** `VaultSearchIndex.swift:62-112` — Jede Suchanfrage iteriert linear über alle Einträge mit `.lowercased().contains()`. Bei 50.000+ Notizen wird die Suche spürbar langsam. Zusätzlich wird `.lowercased()` bei jeder Abfrage für jeden Eintrag aufgerufen statt einmalig beim Indexieren.
- **Der Fix:** Pre-computed lowercase Felder im Index speichern. Für Production: Inverted Index oder Trie-Datenstruktur. Kurzfristig:
```swift
struct SearchEntry {
    let title: String
    let titleLower: String  // pre-computed
    let bodyPrefix: String
    let bodyPrefixLower: String  // pre-computed
    let tags: [String]
}
```

### 🚨 [Performance] VectorEmbeddingService serialisiert gesamten Index als JSON
- **Schweregrad:** Hoch
- **Das Problem:** `VectorEmbeddingService.swift:74-94` — Gesamter Vektor-Index wird als JSON geschrieben. Bei 100.000 Chunks × 512 Floats ≈ 200MB JSON. Deserialisierung blockiert.
- **Der Fix:** Binary-Format (Protobuf, FlatBuffers) oder Memory-Mapped File verwenden.

### 🚨 [Performance] SpeakerDiarizationService lädt gesamten Audio-Buffer
- **Schweregrad:** Hoch
- **Das Problem:** `SpeakerDiarizationService.swift:165-210` — Lädt gesamte Audio-Datei in `AVAudioPCMBuffer`. Bei 2-Stunden-Meeting = ~1GB RAM. Kann auf Geräten mit wenig RAM zu OOM-Crash führen.
- **Der Fix:** Streaming-Verarbeitung mit chunked Audio-Reads.

### 🚨 [Performance] NoteEditorViewModel Word Count auf Main Actor
- **Schweregrad:** Mittel
- **Das Problem:** `NoteEditorViewModel.swift:85-97` — Word Count berechnet `text.components(separatedBy:).filter { !$0.isEmpty }.count` auf dem Main Actor. Bei langen Notizen (100K+ Zeichen) kann das den Main Thread blockieren und 120Hz-Scrolling beeinträchtigen.
- **Der Fix:**
```swift
private func scheduleWordCountUpdate() {
    wordCountTask?.cancel()
    wordCountTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let self else { return }
        let text = self.content
        // Berechnung off-main-thread
        let count = await Task.detached(priority: .utility) {
            text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.count
        }.value
        guard !Task.isCancelled else { return }
        self.wordCount = count
    }
}
```

### 🚨 [Performance] MarkdownTextView re-rendert bei jedem Keystroke
- **Schweregrad:** Hoch
- **Das Problem:** `MarkdownTextView.swift:68-71` (iOS) — `textViewDidChange` ruft `onTextChange?(textView.text)` auf, was in der SwiftUI-Bridge `text = newText` setzt, was `updateUIView` triggert, was `setMarkdown()` aufruft, was den ganzen Text neu rendert. Re-render Loop bei jedem Tastendruck.
- **Der Fix:** Debounce einbauen oder nur sichtbare Paragraphen neu rendern. Kurzfristig: In `updateUIView` prüfen ob `rawMarkdown != text` verhindert die Loop (ist bereits implementiert Zeile 99). Aber `setMarkdown()` erstellt trotzdem ein vollständiges `NSAttributedString` — bei 10.000-Wort-Dokumenten teuer. Langfristig: Inkrementelles Rendering.

### 🚨 [Performance] CloudSyncService.startMonitoring potential Resource Leak
- **Schweregrad:** Mittel
- **Das Problem:** `CloudSyncService.swift:37-53` — `AsyncStream` mit NotificationCenter Observers erstellt. Wenn der Stream verworfen wird, werden die Observer nicht entfernt.
- **Der Fix:**
```swift
continuation.onTermination = { @Sendable _ in
    NotificationCenter.default.removeObserver(token1)
    NotificationCenter.default.removeObserver(token2)
}
```

---

## Zusätzliche Befunde

### 🚨 [Security] nonisolated(unsafe) auf statischen URLs
- **Schweregrad:** Mittel
- **Das Problem:** `AIProvider.swift:72, 120, 177, 281` — `nonisolated(unsafe) static let chatURL` umgeht Swift 6 Strict Concurrency. Diese URLs sind zwar immutable, aber der `nonisolated(unsafe)` Marker ist ein Code Smell und kann bei Reviews Sicherheitsbedenken auslösen.
- **Der Fix:** Computed property verwenden:
```swift
private var chatURL: URL { URL(string: "https://api.openai.com/v1/chat/completions")! }
```

### 🚨 [Architecture] BacklinkUseCase erzeugt WikiLinkExtractor intern
- **Schweregrad:** Mittel
- **Das Problem:** `BacklinkUseCase.swift:9` — Tight Coupling. `WikiLinkExtractor` wird intern erstellt statt injiziert. Nicht testbar.
- **Der Fix:** Constructor Injection.

### 🚨 [Architecture] OCRFrontmatterUseCase erzeugt Services intern
- **Schweregrad:** Mittel
- **Das Problem:** `OCRFrontmatterUseCase.swift:19-21` — `HandwritingOCRService` und `DrawingStorageService` intern erstellt. Nicht testbar, nicht austauschbar.
- **Der Fix:** Constructor Injection.

### 🚨 [Error Handling] AIProvider ohne URLSession Timeout
- **Schweregrad:** Hoch
- **Das Problem:** `AIProvider.swift:103, 160, 208, 264, 318` — Alle `URLSession.shared.data(for:)` Calls ohne Timeout-Konfiguration. Default-Timeout ist 60 Sekunden. Bei langsamen AI-Modellen (Ollama lokal) kann die UI minutenlang blockiert wirken.
- **Der Fix:**
```swift
private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 120
    return URLSession(configuration: config)
}()
```

### 🚨 [FileSystem] FileWatcher potentielles File Descriptor Leak
- **Schweregrad:** Mittel
- **Das Problem:** `FileWatcher.swift:8-9, 53` — File Descriptor wird via `open()` geholt. Nur via `close(fd)` im DispatchSource Cancel-Handler geschlossen. Wenn der Stream deallokiert wird ohne cancel, leakt der FD.
- **Der Fix:** `deinit` oder `onTermination` des Streams muss Cleanup garantieren.

---

## Gesamtnote

### 📊 C+ (befriedigend mit erheblichem Verbesserungspotential)

**Positiv:**
- Saubere Layer-Trennung (Data/Domain/Presentation) grundsätzlich vorhanden
- Modern Swift 6 mit `@Observable`, `Sendable`, structured concurrency
- Gute `#if os()` Guards für PencilKit, UIKit/AppKit
- Konsistente Lokalisierung via `String(localized:bundle:.module)` (245 Strings)
- 7 Sprachen vorbereitet (EN, DE, FR, ES, IT, ZH, JA)
- Gutes Accessibility-Grundgerüst (`reduceMotion`, semantic colors, haptics)
- Elegantes Design-System mit LiquidGlass-Komponenten
- 10 Test-Files vorhanden (FrontmatterParser, Renderer, Models, etc.)

**Kritisch:**
- Widgets sind komplett non-functional (nur Placeholder-Daten)
- 3 Services schreiben ohne NSFileCoordinator → iCloud-Datenverlust-Risiko
- Performance-Bottlenecks bei großen Vaults (lineare Suche, unbounded Tasks)
- Deep Link Handler ist leer implementiert
- Fehlende RTL-Tests und Pluralisierung
- Einige Domain-Klassen sind eigentlich ViewModels (Chat Sessions)

---

## Top 3 Architektur-Prioritäten

### 1. 🔴 File Coordination & iCloud Safety
NSFileCoordinator in MeetingMinutesService, VaultTemplateService und AssetManager einbauen. Einen gemeinsamen `CoordinatedFileWriter` extrahieren. **Risiko: Datenverlust bei iCloud-Sync.**

### 2. 🔴 Widget-Implementation fertigstellen
Timeline Provider müssen echte Daten aus dem Vault lesen (via App Group/UserDefaults). Deep Links auf Widget-Views aktivieren. Placeholder-Strings lokalisieren. **Risiko: App Store Review Rejection wegen non-functional Widgets.**

### 3. 🟡 Performance für große Vaults
VaultSearchIndex auf pre-computed lowercase und ggf. Inverted Index umstellen. VectorEmbeddingService auf Binary-Format umstellen. Task-Parallelität begrenzen. Word Count off-main-thread. **Risiko: 1-Stern-Reviews bei Power-Usern mit >1000 Notizen.**

---

## Nachtrag: Presentation Layer Detail-Befunde

### 🚨 [Accessibility] 8× fehlender reduceMotion-Check in Animationen
- **Schweregrad:** Hoch
- **Das Problem:** Folgende Animationen prüfen `accessibilityReduceMotion` NICHT:
  - `AppLockView.swift:41` — `.animation(.spring(...), value: isUnlocked)`
  - `AppearanceSettingsView.swift:72` — `.animation(.spring(...), value: editorFontScale)`
  - `OnboardingView.swift:67-87` — Alle `.slideUp()` Calls im Welcome Screen
  - `OnboardingView.swift:68` — `.symbolEffect(.breathe)` ohne reduceMotion Guard
  - `OnboardingView.swift:259` — `.bounceIn()` ohne Guard
  - `OnboardingView.swift:314` — `.spinIn()` ohne Guard
- **Der Fix:** Die Animation-Modifiers in LiquidGlass.swift prüfen `reduceMotion` intern korrekt. Das Problem sind die Views die `.animation()` direkt nutzen — diese brauchen einen eigenen Check:
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// ...
.animation(reduceMotion ? .default : .spring(response: 0.35), value: isUnlocked)
```

### 🚨 [Performance] SidebarView erstellt Array-Kopien bei jedem Render
- **Schweregrad:** Mittel
- **Das Problem:**
  - `SidebarView.swift:189` — `Array(viewModel.filteredTree.enumerated())` kopiert bei jedem View-Update
  - `SidebarView.swift:144` — `Array(viewModel.tagInfos.prefix(12).enumerated())` ebenfalls
  - `SidebarViewModel.swift:118-135` — `filteredTree` computed property berechnet bei jedem Zugriff neu; kein Debounce auf `searchText`
- **Der Fix:** Cached computed property oder `onChange(of: searchText)` mit Debounce für Filterung verwenden.

### 🚨 [Memory] NoteEditorViewModel weak self Guard unvollständig
- **Schweregrad:** Hoch
- **Das Problem:** `NoteEditorViewModel.swift:87-96` — Task nutzt `[weak self]`, prüft `guard let self` auf Zeile 89, greift aber danach ohne erneuten Guard zu. Korrekt, ABER: Zwischen `Task.sleep` (Zeile 88) und dem Guard (Zeile 89) gibt es ein Race Window. Dasselbe auf Zeile 103-106.
- **Der Fix:** Pattern ist korrekt in aktuellem Swift — `guard let self` bindet stark, kein Re-Check nötig. Kein Fix erforderlich, aber Dokumentation im Code wäre hilfreich.

### 🚨 [HIG] SearchView hat keinen Loading-Indikator
- **Schweregrad:** Mittel
- **Das Problem:** `SearchView.swift` — Wenn `isSearching` true ist, sieht der Nutzer nur die leere Liste. Kein ProgressView, kein Skeleton.
- **Der Fix:**
```swift
if isSearching && results.isEmpty {
    ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

### 🚨 [Navigation] Column-Visibility wird nicht persistiert
- **Schweregrad:** Mittel
- **Das Problem:** `AdaptiveLayoutView.swift:11` — `columnVisibility` ist `@State`, wird bei jedem App-Start auf `.all` zurückgesetzt. Nutzer-Präferenz (Sidebar eingeklappt) geht verloren.
- **Der Fix:** `@SceneStorage("columnVisibility")` verwenden oder in `AppStorage` persistieren.

### 🚨 [L10n] .textCase(.uppercase) kann in Türkisch/Griechisch brechen
- **Schweregrad:** Mittel
- **Das Problem:** `LiquidGlass.swift:538` — `.textCase(.uppercase)` auf Section Headers. In Türkisch wird `i` zu `İ` (nicht `I`), in Griechisch hat `Σ` zwei Kleinbuchstaben-Formen. SwiftUI's `.textCase` nutzt die System-Locale, sollte aber explizit getestet werden.
- **Der Fix:** Kein Code-Fix nötig — SwiftUI handhabt das korrekt via `Locale.current`. Aber: In den 7 Zielsprachen explizit testen.
