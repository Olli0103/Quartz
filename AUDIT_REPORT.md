# Quartz Notes App — Vollständiges Code-Audit

**Rolle:** Staff iOS/macOS Software Engineer & Apple Design Award Judge
**Datum:** 2026-03-17
**Scope:** Gesamte Codebasis (QuartzKit SPM Package + Quartz App Target + QuartzPro)

---

## Säule 1: Cross-Platform & Compiler-Kompatibilität

### 🚨 [Cross-Platform] FileSystemVaultProvider: iOS-Trash ist nicht atomar
* **Schweregrad:** High
* **Das Problem:** Die iOS-Delete-Implementierung (`#if !os(macOS)`) erstellt einen `.trash`-Ordner, verschiebt Dateien dorthin — in 3 nicht-atomaren Schritten. Zwischen `createDirectory`, `removeItem` und `moveItem` kann ein anderer Prozess (iCloud Sync!) interferieren. macOS nutzt korrekt `trashItem(at:)`.
* **Der Fix (Code):**
```swift
// iOS: Atomic rename statt multi-step
#if os(iOS)
public func deleteNote(at url: URL) async throws {
    let trashFolder = vaultRoot.appending(path: ".trash")
    try writer.createDirectory(at: trashFolder)
    let dest = trashFolder.appending(path: url.lastPathComponent)
    // Single atomic coordinated move
    try writer.moveItem(from: url, to: dest)
}
#endif
```

### 🚨 [Cross-Platform] DrawingStorageService komplett hinter `#if canImport(PencilKit)` — kein Fallback-Protokoll
* **Schweregrad:** Medium
* **Das Problem:** Auf macOS (wo PencilKit seit macOS 14 verfügbar ist, aber eingeschränkt) kompiliert der gesamte Service. Auf hypothetischen Plattformen ohne PencilKit gibt es keinen Stub — Code, der `DrawingStorageService` referenziert, bricht.
* **Der Fix (Code):** Ein Protokoll `DrawingStoring` extrahieren und auf nicht-PencilKit-Plattformen einen `NoOpDrawingStorage` bereitstellen.

### 🚨 [Cross-Platform] VaultPickerView: Bookmark-Erstellung plattformspezifisch, aber Fehlerbehandlung identisch
* **Schweregrad:** Medium
* **Das Problem:** macOS verwendet `.withSecurityScope` für Bookmarks, iOS `.minimalBookmark`. Beide werfen bei Fehlern, aber die catch-Blöcke sind identisch und geben keine plattformspezifischen Hinweise (z.B. "Sandbox permission required" auf macOS).
* **Der Fix (Code):**
```swift
#if os(macOS)
} catch {
    errorMessage = "Sandbox permission denied. Grant Full Disk Access in System Settings."
}
#else
} catch {
    errorMessage = "Could not bookmark folder. Re-select from Files app."
}
#endif
```

### 🚨 [Cross-Platform] `nonisolated(unsafe)` in WikiLinkExtractor Regex-Pattern
* **Schweregrad:** Medium
* **Das Problem:** `WikiLinkExtractor.swift:10` — `nonisolated(unsafe) private static let pattern` umgeht Swift 6 Sendable-Prüfung. Swift Regex ist zwar intern thread-safe, aber `nonisolated(unsafe)` ist ein Code-Smell und wird bei zukünftigen Compiler-Versionen möglicherweise strenger geprüft.
* **Der Fix (Code):**
```swift
// Statt nonisolated(unsafe):
private static let pattern: Regex<(Substring, Substring)> = {
    try! Regex(#"\[\[([^\]]+)\]\]"#)
}()
```

---

## Säule 2: Architektur, Wiring & Memory Management

### 🚨 [Architecture] ServiceContainer ist @MainActor Singleton — keine Testbarkeit
* **Schweregrad:** High
* **Das Problem:** `ServiceContainer.shared` ist ein globaler Singleton. In Tests kann man keine Mock-Services injizieren. `AdaptiveLayoutView.swift` erstellt sogar einen eigenen `FileSystemVaultProvider` statt den Container zu nutzen — DI wird umgangen.
* **Der Fix (Code):**
```swift
protocol ServiceProviding: Sendable {
    func resolveVaultProvider() -> any VaultProviding
}
// In Tests: MockServiceContainer conforming to ServiceProviding
// In Views: @Environment(\.serviceProvider) var services
```

### 🚨 [Memory] NoteEditorViewModel: Unbegrenzte Task-Queue bei schnellem Tippen
* **Schweregrad:** High
* **Das Problem:** `content.didSet` erstellt bei jeder Änderung neue Tasks für Autosave und Word Count. Bei schnellem Tippen (120 WPM+) entstehen hunderte Tasks.
* **Der Fix (Code):**
```swift
var content: String {
    didSet {
        isDirty = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.updateWordCount()
        }
    }
}
```

### 🚨 [Memory] NoteEditorViewModel: Kein `deinit`-Cleanup für laufende Tasks
* **Schweregrad:** High
* **Das Problem:** `autosaveTask` und `wordCountTask` werden nie in einem `deinit` gecancelt.
* **Der Fix (Code):**
```swift
deinit {
    autosaveTask?.cancel()
    wordCountTask?.cancel()
}
```

### 🚨 [Architecture] NoteEditorViewModel.save(): Race Condition bei `isSaving`
* **Schweregrad:** High
* **Das Problem:** Die Guard-Prüfung `isDirty && !isSaving` und das Setzen von `isSaving = true` sind nicht atomar.
* **Der Fix (Code):**
```swift
func save() async {
    guard isDirty, !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    // ... rest of save logic
}
```

### 🚨 [Architecture] ProFeatureGate: `@unchecked Sendable` mit NSLock statt Actor
* **Schweregrad:** Medium
* **Das Problem:** Swift-5-Pattern in Swift-6-Projekt. `observeTransactionUpdates()` gibt einen `Task` zurück, der nie gespeichert wird — Memory Leak.
* **Der Fix (Code):**
```swift
@Observable
public actor ProFeatureGate: FeatureGating {
    private var transactionTask: Task<Void, Never>?
    deinit { transactionTask?.cancel() }
}
```

### 🚨 [Architecture] AIProvider.swift: UserDefaults Race in CustomModelStore
* **Schweregrad:** Critical
* **Das Problem:** `CustomModelStore` ist ein `actor`, ruft aber `UserDefaults.standard` auf, das nicht thread-safe ist bei gleichzeitigem Lesen/Schreiben.
* **Der Fix:** Alle UserDefaults-Zugriffe ausschließlich über den Actor serialisieren und verifizieren, dass keine `nonisolated` Zugriffe existieren.

### 🚨 [Architecture] CloudSyncService: Task-Leaks in Notification-Listening
* **Schweregrad:** High
* **Das Problem:** `gatherTask` und `updateTask` capturen `self`. Kein Cleanup-Mechanismus.
* **Der Fix (Code):**
```swift
public func stopMonitoring() {
    gatherTask?.cancel()
    updateTask?.cancel()
    query.stop()
}
```

---

## Säule 3: Exception Handling & Edge Cases

### 🚨 [Security] FileSystemVaultProvider: Path-Traversal nicht vollständig validiert
* **Schweregrad:** Critical
* **Das Problem:** `createFolder(named:)` sanitisiert den Namen, prüft aber nicht auf Unicode-Normalisierung die nach Sanitisierung `../` ergibt.
* **Der Fix (Code):**
```swift
func createFolder(named name: String, in parent: URL) async throws -> URL {
    let sanitized = name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .replacingOccurrences(of: "\0", with: "")
        .precomposedStringWithCanonicalMapping

    guard !sanitized.isEmpty,
          !sanitized.starts(with: "."),
          sanitized != "..",
          !sanitized.contains("..") else {
        throw FileSystemError.invalidName(name)
    }

    let folderURL = parent.appending(path: sanitized)
    guard folderURL.resolvingSymlinksInPath().path()
            .hasPrefix(parent.resolvingSymlinksInPath().path()) else {
        throw FileSystemError.invalidName(name)
    }
}
```

### 🚨 [Exception] TranscriptionService & HandwritingOCRService: Double-Resume-Protection prüfen
* **Schweregrad:** Critical
* **Das Problem:** Beide Services verwenden `OSAllocatedUnfairLock` für Double-Resume-Schutz. Verifizieren, dass `withLock` korrekt `inout` State mutiert.

### 🚨 [Exception] AIProvider: Force-Unwrapped URLs
* **Schweregrad:** High
* **Das Problem:** Mehrere `URL(string: "...")!` Force-Unwraps für API-Endpoints. Crash-Risiko bei ungültigen `modelID`.
* **Der Fix (Code):**
```swift
guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
    throw AIProviderError.invalidConfiguration("Invalid API URL")
}
```

### 🚨 [Exception] VaultEncryptionService: Keychain-Update nicht atomar
* **Schweregrad:** Medium
* **Das Problem:** `SecItemUpdate` gefolgt von `SecItemAdd` — Crash dazwischen = Key verloren.

### 🚨 [Exception] VectorEmbeddingService: Kein Schutz vor leeren/riesigen Dokumenten
* **Schweregrad:** Medium
* **Das Problem:** `indexNote()` chunked Text ohne Obergrenze. Ein 100MB-Dokument füllt den RAM.

### 🚨 [Exception] FileWatcher: `open()` ohne Fehlerbehandlung
* **Schweregrad:** High
* **Das Problem:** `open()` gibt `-1` zurück bei Fehlern. Der Code prüft das nicht.

### 🚨 [Exception] ContentView: Error-Banner Auto-Dismiss ohne Task-Cancellation
* **Schweregrad:** Medium
* **Das Problem:** `Task.sleep` für Auto-Dismiss läuft weiter wenn View dismissed wird.

---

## Säule 4: Apple Design Award Level UI/UX & HIG

### 🚨 [UI/UX] SidebarView: Kein Drag & Drop für Notizen/Ordner
* **Schweregrad:** High
* **Das Problem:** `FolderManagementUseCase.move()` existiert im Backend, aber die SidebarView bietet kein `.draggable()` / `.dropDestination()` an.

### 🚨 [UI/UX] Keine Swipe-Actions in der Sidebar
* **Schweregrad:** Medium
* **Das Problem:** Apple Notes bietet Swipe-to-Delete und Swipe-to-Pin. Quartz nutzt nur Kontextmenüs.

### 🚨 [UI/UX] SkeletonRow-Loading ohne Animation Limit
* **Schweregrad:** UI-Polish
* **Das Problem:** `ShimmerModifier` Endlos-Animation ohne Auto-Stop.

### 🚨 [UI/UX] Keine `.focusable()` / Focus-Ring auf macOS-Sidebar-Elementen
* **Schweregrad:** Medium
* **Das Problem:** macOS-Nutzer mit Tastatur-Navigation können nicht durch die Sidebar navigieren.

### 🚨 [UI/UX] Tag-ScrollView hat keine Accessibility-Container-Rolle
* **Schweregrad:** Medium
* **Das Problem:** Die horizontale Tag-ScrollView ist für VoiceOver ein flacher Container.

---

## Säule 5: Lokalisierung (L10n) & Internationalisierung (I18n)

### ✅ [L10n] Localization ist vorbildlich — 216 Keys, 100% Abdeckung in 7 Sprachen
Beide `.xcstrings`-Dateien sind vollständig übersetzt. Alle UI-Strings nutzen korrekt `String(localized:, bundle: .module)`.

### 🚨 [L10n] Keine Pluralisierung für zählbare Strings
* **Schweregrad:** Medium
* **Das Problem:** Strings wie "X notes found" verwenden einfache Interpolation statt Plural Rules.

### 🚨 [I18n] Keine explizite RTL-Unterstützung
* **Schweregrad:** Medium
* **Das Problem:** RTL sollte in der Test-Matrix stehen. SwiftUI mapped `.leading`/`.trailing` korrekt.

### 🚨 [L10n] Deutsche Code-Kommentare in Public API
* **Schweregrad:** UI-Polish
* **Das Problem:** Zahlreiche `///`-DocStrings sind auf Deutsch statt Englisch.

---

## Säule 6: Performance & Device-Capabilities

### 🚨 [Performance] VectorEmbeddingService: Gesamter Index in Memory geladen
* **Schweregrad:** High
* **Das Problem:** Bei 10.000+ Notizen: ~20MB+ reine Vektordaten im RAM. Kein Memory-Mapping.

### 🚨 [Performance] FileSystemVaultProvider: Rekursiver Tree-Build
* **Schweregrad:** High
* **Das Problem:** Rekursiver `contentsOfDirectory` mit Tiefenlimit 50 ohne Caching.

### 🚨 [Performance] VaultSearchIndex: In-Memory-Suche ohne Limit
* **Schweregrad:** Medium
* **Das Problem:** Kein Paging, kein Result-Limit für Search-Ergebnisse.

### 🚨 [Performance] CloudSyncService: `processQueryResults` blockiert synchron
* **Schweregrad:** Medium
* **Das Problem:** Alle NSMetadataQuery-Ergebnisse synchron iteriert.

### 🚨 [Performance] NoteEditorViewModel: Word Count per Task.detached ohne Throttling
* **Schweregrad:** Medium
* **Das Problem:** Jede Textänderung triggert neuen Word Count über gesamten Text.

### 🚨 [Performance] LiquidGlass: Endlos-Animationen ohne Cleanup
* **Schweregrad:** Medium
* **Das Problem:** `ShimmerModifier`, `PulseModifier` laufen auch off-screen weiter.

---

## Test-Coverage-Analyse

**157 Tests** in 14 Test-Dateien.

| Layer | Tests | Abdeckung |
|-------|-------|-----------|
| Domain Models | 33 | ✅ Gut |
| Frontmatter Parser | 7 | ✅ Gut |
| Markdown Renderer | 11 | ✅ Gut |
| Markdown Formatter | 19 | ✅ Gut |
| Wiki/Tag Extractor | 23 | ✅ Gut |
| Search Index | 15 | ✅ Gut |
| ViewModel | 17 | ⚠️ Nur Sidebar + Editor |
| FileWatcher | 4 | ⚠️ Minimal |
| Cloud Sync | 6 | ⚠️ Minimal |
| Vector Embedding | 9 | ⚠️ Nur Binary Format |
| Feature Gate | 8 | ✅ Gut |
| Biometric Auth | 4 | ⚠️ Nur Types |
| **AI Provider** | **0** | ❌ Keine Tests |
| **Encryption** | **0** | ❌ Keine Tests |
| **Audio Services** | **0** | ❌ Keine Tests |
| **OCR Service** | **0** | ❌ Keine Tests |
| **Drawing Storage** | **0** | ❌ Keine Tests |
| **Asset Manager** | **0** | ❌ Keine Tests |

---

## Gesamtbewertung: B- (7.2/10)

**Stärken:**
- Exzellente Lokalisierung (100%, 7 Sprachen)
- Saubere SwiftUI-Architektur mit @Observable
- Durchdachtes Design-System mit Motion-Accessibility
- Gute #if canImport() Plattform-Abstraktion
- Solide Domain-Model-Tests

**Schwächen:**
- Sicherheitskritische Services ohne Tests
- Mehrere Race Conditions in Concurrency-Code
- Path-Traversal-Schwachstelle
- Memory-Management-Lücken
- Fehlende Drag & Drop / Swipe-Actions

---

## Top 3 Architektur-Prioritäten

### 1. 🔴 Security Hardening (Woche 1-2)
Path-Traversal-Fix, Keychain-Atomarität, Force-Unwrap-Eliminierung. Tests für Encryption und Biometric. Ein Path-Traversal-Exploit gefährdet den App-Store-Review.

### 2. 🟠 Concurrency Correctness (Woche 2-3)
Task-Lifecycle-Management (deinit-Cancellation), FileWatcher-Validierung, CloudSync Task-Leaks, nonisolated(unsafe) eliminieren. Swift 6 wird diese Fehler als Compiler-Errors behandeln.

### 3. 🟡 Scalability & UX Parity (Woche 3-4)
Memory-Mapped Embedding Index, Search-Limits, Drag & Drop, Swipe-Actions. Ohne diese Fixes wird die App bei >1000 Notizen spürbar langsamer.
