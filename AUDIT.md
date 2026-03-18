# Quartz Notes — Code Review Audit

**Auditor-Rolle:** Staff iOS/macOS Software Engineer · Apple Design Award Judge
**Datum:** 2026-03-18
**Codebase:** Quartz (SwiftUI Multi-Platform Notes App)
**Plattformen:** iOS 18+, iPadOS 18+, macOS 15+
**Swift Version:** 6.0 (strict concurrency)

---

## Säule 1: Cross-Platform & Compiler Compatibility

### 🚨 [Cross-Platform] `ProFeatureGate` uses `@unchecked Sendable` with `NSLock` statt Actor

- **Schweregrad:** Hoch
- **Das Problem:** `ProFeatureGate` (QuartzPro/ProFeatureGate.swift:15) und `DefaultFeatureGate` (DefaultFeatureGate.swift:8) verwenden `@unchecked Sendable` mit manuellem `NSLock`. Dies umgeht die Swift 6 Concurrency-Checks und ist fehleranfällig. Beide Typen greifen auf gemeinsamen Zustand zu — ein vergessenes `lock.withLock {}` erzeugt eine Data Race ohne Compiler-Warnung.
- **Der Fix (Code):**
```swift
// DefaultFeatureGate.swift — als Actor refactored
public actor DefaultFeatureGate: FeatureGating {
    private var tierMap: [Feature: FeatureTier] = [
        .markdownEditor: .free,
        .focusMode: .free,
        // ... alle Einträge
    ]
    private var _isProUnlocked: Bool = false

    public var isProUnlocked: Bool {
        get { _isProUnlocked }
        set { _isProUnlocked = newValue }
    }

    public func isEnabled(_ feature: Feature) -> Bool {
        switch tier(for: feature) {
        case .free: true
        case .pro: _isProUnlocked
        }
    }

    public func tier(for feature: Feature) -> FeatureTier {
        tierMap[feature] ?? .free
    }
}
```

---

### 🚨 [Cross-Platform] `VaultPickerView` Bookmark-Options nicht für visionOS vorbereitet

- **Schweregrad:** Mittel
- **Das Problem:** `VaultPickerView.swift:92-104` verwendet `#if os(macOS)` vs. Fallback. Wenn visionOS als Ziel dazukommt, greift der `#else`-Zweig mit `.minimalBookmark`, was für visionOS möglicherweise nicht korrekt ist. Außerdem fehlt ein `#if os(visionOS)` Guard.
- **Der Fix (Code):**
```swift
#if os(macOS)
let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
#elseif os(visionOS)
let bookmarkData = try url.bookmarkData(
    options: .minimalBookmark,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
#else // iOS, iPadOS
let bookmarkData = try url.bookmarkData(
    options: .minimalBookmark,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
#endif
```
Empfehlung: Abstraktes `BookmarkStrategy`-Protocol für plattformspezifische Bookmark-Logik.

---

### 🚨 [Cross-Platform] `QuartzApp.swift` — Discarded Task Return Value

- **Schweregrad:** Mittel
- **Das Problem:** `QuartzApp.swift:25`: `_ = proFeatureGate.observeTransactionUpdates()` — die Methode gibt `Void` zurück, der `_ =` ist unnötig. Aber wichtiger: der interne `Task.detached` in `observeTransactionUpdates()` startet eine unstrukturierte Task-Hierarchie, die bei Scene-Wechsel nicht gecancelled wird. Auf iPadOS mit Stage Manager kann die Scene mehrfach instanziiert werden → mehrere parallele Observer.
- **Der Fix (Code):**
```swift
// QuartzApp.swift — .task garantiert Cancellation bei Scene-Ende
.task {
    ServiceContainer.shared.bootstrap(featureGate: proFeatureGate)
    await proFeatureGate.checkPurchaseStatus()

    // Structured Task: wird automatisch gecancelled
    for await result in Transaction.updates {
        if case .verified(let transaction) = result {
            if transaction.productID == ProFeatureGate.proProductID {
                proFeatureGate.hasPurchasedPro = transaction.revocationDate == nil
            }
            await transaction.finish()
        }
    }
}
```

---

### 🚨 [Cross-Platform] `CloudSyncService` nur unter `canImport(UIKit) || canImport(AppKit)` — fehlt für visionOS

- **Schweregrad:** Niedrig
- **Das Problem:** `CloudSyncService.swift:1` schließt visionOS ein (visionOS hat UIKit), aber `NSMetadataQuery` erfordert sorgfältige Tests auf visionOS. Kein Problem heute, aber beim Hinzufügen als Zielplattform könnte es stille Fehler geben.
- **Der Fix (Code):** Expliziten `#if os(visionOS)` Guard hinzufügen oder mit `@available(visionOS, unavailable)` markieren, bis getestet.

---

## Säule 2: Architecture, Wiring & Memory Management

### 🚨 [Architektur] `ServiceContainer` — Singleton ohne Testbarkeit

- **Schweregrad:** Hoch
- **Das Problem:** `ServiceContainer.swift:13` — `static let shared` macht Unit-Tests schwierig, da der Zustand zwischen Tests persistiert. Kein `reset()`-Methode. Zudem können Services nach `bootstrap()` jederzeit per `register()` überschrieben werden, was zu inkonsistenten Zuständen zur Laufzeit führen kann.
- **Der Fix (Code):**
```swift
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    #if DEBUG
    /// Resets all registrations. Only available in debug/test builds.
    public func reset() {
        vaultProvider = nil
        frontmatterParser = nil
        featureGate = nil
        isBootstrapped = false
    }
    #endif

    public func bootstrap(
        vaultProvider: (any VaultProviding)? = nil,
        frontmatterParser: (any FrontmatterParsing)? = nil,
        featureGate: (any FeatureGating)? = nil
    ) {
        precondition(!isBootstrapped, "ServiceContainer.bootstrap() must only be called once")
        // ... rest bleibt gleich
    }
}
```

---

### 🚨 [Memory] `NoteEditorViewModel` — Tasks werden nicht automatisch gecancelled

- **Schweregrad:** Hoch
- **Das Problem:** `NoteEditorViewModel.swift:143-146` enthält den Kommentar, dass `deinit` nicht implementiert werden kann wegen Swift 6 Actor Isolation. `cancelAllTasks()` muss manuell aufgerufen werden. Wenn dies vergessen wird (z.B. bei Navigation-Edge-Cases), laufen `autosaveTask` und `wordCountTask` weiter und halten über `[weak self]` indirekt Referenzen. Obwohl `weak self` kein Retain Cycle verursacht, laufen die Tasks unnötig weiter.
- **Der Fix (Code):**
```swift
// In der View-Ebene: .onDisappear statt nur bei openNote
// NoteEditorView.swift
.onDisappear {
    viewModel.cancelAllTasks()
}
// Zusätzlich: Task-Cancellation bei loadNote
public func loadNote(at url: URL) async {
    cancelAllTasks() // Cancel ausstehende Saves bevor neues Dokument geladen wird
    // ... bestehende Implementierung
}
```

---

### 🚨 [Concurrency] `VaultEncryptionService` — `encryptFile`/`decryptFile` blockieren Actor

- **Schweregrad:** Hoch
- **Das Problem:** `VaultEncryptionService.swift:121-159` — `encryptFile` und `decryptFile` sind Actor-isolated Methoden, die synchron `NSFileCoordinator.coordinate()` aufrufen. `NSFileCoordinator` kann blockieren (z.B. wenn ein anderer Prozess die Datei koordiniert). Da der gesamte `VaultEncryptionService` Actor blockiert wird, sind alle anderen Methoden des Actors ebenfalls gesperrt — potentieller Deadlock wenn `encrypt` + `decrypt` parallel auf dem gleichen Actor aufgerufen werden.
- **Der Fix (Code):**
```swift
public func encryptFile(at url: URL, with key: SymmetricKey) async throws {
    // Validierung auf dem Actor
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    if let size = attrs[.size] as? Int, size > Self.maxInMemoryFileSize {
        throw EncryptionError.encryptionFailed("File too large")
    }

    // NSFileCoordinator auf Background-Queue
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            var coordinatorError: NSError?
            var opError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { actualURL in
                do {
                    let plaintext = try Data(contentsOf: actualURL)
                    let encrypted = try self.encrypt(data: plaintext, with: key) // nonisolated, safe
                    try encrypted.write(to: actualURL, options: .atomic)
                } catch { opError = error }
            }
            if let error = coordinatorError ?? opError {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}
```

---

### 🚨 [Concurrency] `CloudSyncService.processQueryResults` — Actor-Isolation Verletzung

- **Schweregrad:** Mittel
- **Das Problem:** `CloudSyncService.swift:47,56` — `service.processQueryResults(metaQuery, continuation:)` wird innerhalb einer `Task` aufgerufen. Die Methode ist `nonisolated`, aber `metaQuery.disableUpdates()` und `metaQuery.enableUpdates()` werden auf einer unspezifischen Task aufgerufen. `NSMetadataQuery` ist nicht Thread-safe und muss auf dem Main Thread oder der Queue verwendet werden, auf der sie gestartet wurde.
- **Der Fix (Code):**
```swift
let gatherTask = Task { @MainActor in
    for await notification in center.notifications(named: .NSMetadataQueryDidFinishGathering, object: query) {
        guard let metaQuery = notification.object as? NSMetadataQuery else { continue }
        metaQuery.disableUpdates()
        service.processQueryResults(metaQuery, continuation: continuation)
        metaQuery.enableUpdates()
    }
}
```

---

### 🚨 [Architektur] `SidebarViewModel.delete` verwendet `vaultProvider.deleteNote` auch für Ordner

- **Schweregrad:** Mittel
- **Das Problem:** `SidebarViewModel.swift:99` — `delete(at:)` ruft `vaultProvider.deleteNote(at:)` auf, unabhängig davon ob die URL ein Ordner oder eine Note ist. Der Methodenname und die Semantik stimmen nicht überein. Falls `deleteNote` intern nur Dateien löscht, schlägt das Löschen von Ordnern still fehl.
- **Der Fix (Code):**
```swift
public func delete(at url: URL) async {
    do {
        try await vaultProvider.delete(at: url) // Generische Methode, die Dateien und Ordner behandelt
        await refresh()
    } catch {
        errorMessage = userFacingMessage(for: error)
    }
}
```
Falls `VaultProviding` keine generische `delete`-Methode hat: hinzufügen und im Provider `isDirectory` prüfen.

---

### 🚨 [Wiring] `ProFeatureGate.checkPurchaseStatus` — iteriert über gesamten `currentEntitlements` Stream

- **Schweregrad:** Mittel
- **Das Problem:** `ProFeatureGate.swift:57-65` — `for await result in Transaction.currentEntitlements` iteriert über **alle** Entitlements. Wenn der Pro-Kauf gefunden wird, kehrt die Methode zurück. Aber wenn kein Pro-Kauf existiert, muss der gesamte Stream durchlaufen werden. Das ist korrekt, aber: der `hasPurchasedPro = false` am Ende wird erst gesetzt, nachdem der gesamte Stream beendet ist. Bei vielen Transaktionen verursacht das eine spürbare Verzögerung beim App-Start.
- **Der Fix (Code):**
```swift
func checkPurchaseStatus() async {
    var foundPro = false
    for await result in Transaction.currentEntitlements {
        if case .verified(let transaction) = result,
           transaction.productID == Self.proProductID {
            foundPro = true
            break
        }
    }
    hasPurchasedPro = foundPro
}
```

---

## Säule 3: Exception Handling & Edge Cases

### 🚨 [Error Handling] Generische Fehlermeldungen verlieren Kontext

- **Schweregrad:** Hoch
- **Das Problem:** Mehrere ViewModels (z.B. `NoteEditorViewModel.swift:56,80`, `SidebarViewModel.swift:206-210`) fangen Fehler und zeigen generische Meldungen an. Der ursprüngliche Fehlertyp und -kontext geht verloren. Benutzer sehen "An unexpected error occurred" ohne Handlungsanweisung. Debugging wird in Production unmöglich.
- **Der Fix (Code):**
```swift
// Zentrales Error-Handling mit Logging
import os

private static let logger = Logger(subsystem: "com.quartz", category: "NoteEditor")

private func handleError(_ error: Error, context: String) {
    Self.logger.error("\(context): \(error.localizedDescription, privacy: .public)")

    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
        errorMessage = description
    } else if let fsError = error as? FileSystemError {
        errorMessage = fsError.errorDescription ?? fallbackMessage
    } else {
        errorMessage = String(localized: "An unexpected error occurred. Please try again.", bundle: .module)
    }
}
```

---

### 🚨 [Edge Case] `VaultEncryptionService` — Keine Wiederherstellung bei fehlgeschlagener In-Place Verschlüsselung

- **Schweregrad:** Hoch
- **Das Problem:** `VaultEncryptionService.swift:129-137` — `encryptFile` schreibt die verschlüsselten Daten direkt in die Quelldatei (`.atomic`). Wenn die App zwischen Lesen und Schreiben abstürzt, ist die Datei verloren. `.atomic` schützt nur vor Schreibfehlern, nicht vor Crash während der Verschlüsselung im RAM.
- **Der Fix (Code):**
```swift
// 1. Backup erstellen vor Verschlüsselung
let backupURL = url.appendingPathExtension("quartz-backup")
try FileManager.default.copyItem(at: actualURL, to: backupURL)

// 2. Verschlüsseln und schreiben
let plaintext = try Data(contentsOf: actualURL)
let encrypted = try encrypt(data: plaintext, with: key)
try encrypted.write(to: actualURL, options: .atomic)

// 3. Backup entfernen nach erfolgreichem Schreiben
try? FileManager.default.removeItem(at: backupURL)
```

---

### 🚨 [Edge Case] `SidebarView` — Race Condition bei schnellem Ordner-Erstellen

- **Schweregrad:** Mittel
- **Das Problem:** `SidebarView.swift:72-76` — der "Create"-Button setzt `newItemName = ""` synchron, startet aber `Task { await viewModel.createFolder(...) }` asynchron. Wenn der Benutzer schnell hintereinander zwei Ordner erstellt, könnte der zweite `createFolder`-Aufruf mit dem leeren String des Resets starten, bevor der Dialog den neuen Namen gesetzt hat.
- **Der Fix (Code):**
```swift
Button(String(localized: "Create", bundle: .module)) {
    let name = newItemName  // Snapshot
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let parent = newItemParent else { return }
    newItemName = ""
    Task { await viewModel.createFolder(named: name, in: parent) }
}
```

---

### 🚨 [Edge Case] `CloudSyncService` — Konflikte werden still gelöst (Datenverlust)

- **Schweregrad:** Hoch
- **Das Problem:** `CloudSyncService.swift:151-171` — `resolveConflictKeepingCurrent` löscht **alle** Konfliktversionen ohne den Benutzer zu fragen. Bei iCloud Sync-Konflikten zwischen zwei Geräten gehen die Änderungen des anderen Geräts unwiederbringlich verloren.
- **Der Fix (Code):**
```swift
/// Presents conflict versions to the user for resolution.
public struct ConflictInfo: Sendable {
    public let url: URL
    public let localModificationDate: Date?
    public let conflictVersions: [(date: Date?, deviceName: String?)]
}

public nonisolated func conflictInfo(for url: URL) -> ConflictInfo? {
    let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    guard !versions.isEmpty else { return nil }
    return ConflictInfo(
        url: url,
        localModificationDate: try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
        conflictVersions: versions.map { ($0.modificationDate, $0.localizedNameOfSavingComputer) }
    )
}
```
Empfehlung: UI-Dialog zur Auswahl zwischen lokaler und Cloud-Version hinzufügen.

---

### 🚨 [Error Handling] `FolderManagementUseCase.move` — Symlink-Check aber kein Hardlink-Check

- **Schweregrad:** Mittel
- **Das Problem:** Der Move-UseCase prüft Symlinks zur Path-Traversal-Prevention, aber nicht Hardlinks. Ein Angreifer könnte einen Hardlink erstellen, der auf Dateien außerhalb des Vaults zeigt.
- **Der Fix (Code):**
```swift
// Nach dem Symlink-Check hinzufügen:
let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
if let linkCount = sourceAttributes[.referenceCount] as? Int, linkCount > 1 {
    throw FileSystemError.invalidPath("Hardlinks are not supported for security reasons")
}
```

---

## Säule 4: Apple Design Awards Level UI/UX & HIG

### 🚨 [HIG] `QuickNoteView` — Keyboard-Shortcut als visueller Text statt Accessibility Hint

- **Schweregrad:** Mittel
- **Das Problem:** `QuickNoteView` zeigt "⌘↩ to save" als visuellen Text. VoiceOver liest die Unicode-Symbole falsch vor ("Unicode mathematical symbol left parenthesis..."). Kein `.accessibilityHint` vorhanden.
- **Der Fix (Code):**
```swift
Text(String(localized: "⌘↩ to save", bundle: .module))
    .font(.caption)
    .foregroundStyle(.tertiary)
    .accessibilityLabel(String(localized: "Press Command Return to save", bundle: .module))
```

---

### 🚨 [HIG] `SettingsView` — Fehlende Accessibility Labels auf Navigation Links

- **Schweregrad:** Mittel
- **Das Problem:** Settings-Einträge verwenden `Label(String, systemImage:)`, aber ohne explizite Accessibility Labels. Screen Reader könnten den System-Image-Namen statt einer verständlichen Beschreibung vorlesen.
- **Der Fix (Code):**
```swift
NavigationLink {
    AppearanceSettingsView()
} label: {
    Label(String(localized: "Appearance", bundle: .module), systemImage: "paintbrush")
}
.accessibilityLabel(String(localized: "Appearance settings", bundle: .module))
```

---

### 🚨 [Animation] `SidebarView` — Tags-ScrollView ohne Scroll-Indikator-Feedback

- **Schweregrad:** UI-Polish
- **Das Problem:** `SidebarView.swift:153` — `showsIndicators: false` entfernt den Scroll-Indikator. Bei >12 Tags (die Maximum-Grenze) hat der Benutzer keinen visuellen Hinweis, dass mehr Tags existieren. Die Begrenzung auf 12 Tags (`.prefix(12)`) wird dem Benutzer nicht kommuniziert.
- **Der Fix (Code):**
```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        ForEach(Array(viewModel.tagInfos.prefix(12).enumerated()), id: \.element.id) { index, tag in
            // ... bestehende TagBadges
        }
        if viewModel.tagInfos.count > 12 {
            Button {
                // Show all tags in overlay/sheet
            } label: {
                Text("+\(viewModel.tagInfos.count - 12)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
// Fade-Effekt am rechten Rand als Scroll-Hinweis
.mask {
    HStack(spacing: 0) {
        Color.black
        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 20)
    }
}
```

---

### 🚨 [HIG] `QuickNotePanel` — macOS Panel ohne Accessibility-Announcement

- **Schweregrad:** Mittel
- **Das Problem:** `QuickNotePanel` (macOS-only) ist ein `NSPanel` mit `nonactivatingPanel` Stil. Wenn es erscheint, gibt es kein VoiceOver-Announcement. Screen Reader-Nutzer wissen nicht, dass ein neues Eingabefeld erschienen ist.
- **Der Fix (Code):**
```swift
// Nach Panel-Anzeige:
NSAccessibility.post(element: panel, notification: .created)
// Und Focus auf das Textfeld setzen:
NSAccessibility.post(element: textField, notification: .focusedUIElementChanged)
```

---

### 🚨 [HIG] `OnboardingView` — MeshGradient ohne reduceTransparency-Check

- **Schweregrad:** UI-Polish
- **Das Problem:** Der `MeshGradient`-Hintergrund im Onboarding prüft `reduceMotion`, aber nicht `accessibilityReduceTransparency`. Benutzer mit aktivierter Transparenzreduktion sollten einen soliden Hintergrund erhalten.
- **Der Fix (Code):**
```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

// Im Body:
.background {
    if reduceTransparency {
        Color(.systemBackground)
    } else {
        MeshGradient(/* ... */)
    }
}
```

---

## Säule 5: Localization (L10n) & Internationalization (I18n)

### 🚨 [L10n] Hardcodierte Strings in `SpeakerDiarizationService`

- **Schweregrad:** Hoch
- **Das Problem:** `SpeakerDiarizationService` verwendet hardcodierte englische Strings: `"Speaker A"`, `"Speaker B"`, `"Speaker C"`, `"Speaker D"`. Diese werden in der UI angezeigt, sind aber nicht lokalisiert.
- **Der Fix (Code):**
```swift
private static let speakerLabels: [String] = [
    String(localized: "Speaker A", bundle: .module),
    String(localized: "Speaker B", bundle: .module),
    String(localized: "Speaker C", bundle: .module),
    String(localized: "Speaker D", bundle: .module),
]
```

---

### 🚨 [L10n] `MeetingMinutesService` — Hardcodierter "Meeting – " Prefix

- **Schweregrad:** Mittel
- **Das Problem:** `MeetingMinutesService` generiert Titel mit `"Meeting – "` Prefix. Nicht lokalisiert.
- **Der Fix (Code):**
```swift
let title = String(localized: "Meeting – \(dateString)", bundle: .module)
```

---

### 🚨 [L10n] `VaultPickerView` — Strings ohne Bundle-Angabe

- **Schweregrad:** Hoch
- **Das Problem:** `VaultPickerView.swift:26-33,47,54,57` — Alle `String(localized:)` Aufrufe verwenden **kein** `bundle: .module`. Da `VaultPickerView` im App-Target liegt (nicht in `QuartzKit`), zeigt `.module` auf das falsche Bundle. Aber: die Strings werden dann nur im App-Target-Xcstrings gesucht, nicht im QuartzKit-Xcstrings. Wenn die Strings nur im QuartzKit-Katalog existieren, werden sie nicht gefunden.
- **Der Fix (Code):**
```swift
// VaultPickerView liegt im App-Target → String(localized:) ohne bundle ist korrekt,
// ABER: sicherstellen, dass Quartz/Localizable.xcstrings alle Strings enthält.
// Alternativ: VaultPickerView nach QuartzKit verschieben für konsistentes Bundle.
```
Empfehlung: Alle UI-Views in `QuartzKit` verschieben für einheitliches `bundle: .module`.

---

### 🚨 [I18n] Kein RTL-Layout-Test — ScrollView-Tags könnten gespiegelt werden

- **Schweregrad:** Mittel
- **Das Problem:** `SidebarView.swift:153` — `ScrollView(.horizontal)` mit `HStack` funktioniert automatisch mit RTL dank SwiftUI. Aber die Fade-Maske und die Scroll-Position starten links, was in RTL-Sprachen (Arabisch, Hebräisch) unnatürlich wirkt. Zudem: die Tags-Section hat keinen `.environment(\.layoutDirection, ...)` Test.
- **Der Fix (Code):**
```swift
// Fade-Maske RTL-aware machen:
@Environment(\.layoutDirection) private var layoutDirection

.mask {
    HStack(spacing: 0) {
        if layoutDirection == .rightToLeft {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
        }
        Color.black
        if layoutDirection == .leftToRight {
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 20)
        }
    }
}
```

---

### 🚨 [L10n] String-Interpolation in `CloudSyncError` — nicht übersetzbar für alle Sprachen

- **Schweregrad:** Mittel
- **Das Problem:** `CloudSyncService.swift:238` — `String(localized: "Failed to read from iCloud: \(url.lastPathComponent)")` verwendet Interpolation. In manchen Sprachen steht der Dateiname an einer anderen Stelle im Satz. Swift `String(localized:)` mit Interpolation unterstützt das zwar, aber Übersetzer müssen den Interpolations-Marker in der `.xcstrings`-Datei korrekt positionieren.
- **Der Fix (Code):** Dies ist korrekt implementiert — `String(localized:)` mit Interpolation erzeugt korrekte `.xcstrings`-Einträge. Sicherstellen, dass Übersetzer Zugang zu Kontextkommentaren haben:
```swift
String(localized: "Failed to read from iCloud: \(url.lastPathComponent)",
       bundle: .module,
       comment: "Error message when iCloud file read fails. Parameter is the file name.")
```

---

## Säule 6: Performance & Device Capabilities

### 🚨 [Performance] `VaultEncryptionService.encryptFile` — Synchrones I/O auf Actor

- **Schweregrad:** Kritisch
- **Das Problem:** `VaultEncryptionService.swift:121-139` — `encryptFile` liest die gesamte Datei synchron in den Speicher (`Data(contentsOf:)`), verschlüsselt sie, und schreibt sie zurück. Bei Dateien nahe dem 50MB-Limit verbraucht dies >100MB RAM (Original + verschlüsselt). Zudem blockiert `NSFileCoordinator.coordinate()` den Actor synchron.
- **Der Fix (Code):** Siehe Säule 2, `encryptFile` Async-Refactoring. Zusätzlich für große Dateien:
```swift
// Streaming-Verschlüsselung für Dateien > 1MB
private static let streamingThreshold: Int = 1_000_000

public func encryptFile(at url: URL, with key: SymmetricKey) async throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    let size = (attrs[.size] as? Int) ?? 0

    guard size <= Self.maxInMemoryFileSize else {
        throw EncryptionError.encryptionFailed("File too large (\(size) bytes)")
    }

    // Delegate to background queue to avoid blocking actor
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // ... NSFileCoordinator logic from above
        }
    }
}
```

---

### 🚨 [Performance] `SidebarViewModel.filteredTree` — O(n) Rekursion bei jedem Zugriff ohne Change-Detection

- **Schweregrad:** Mittel
- **Das Problem:** `SidebarViewModel.swift:130-147` — `filteredTree` wird gecacht, aber das Cache wird bei **jeder** Änderung von `fileTree`, `searchText` oder `selectedTag` invalidiert. Bei einem Vault mit 1000+ Notes wird der gesamte Baum bei jedem Tastendruck (trotz 200ms Debounce) neu gefiltert. `compactMap` erzeugt neue Arrays und kopiert Structs.
- **Der Fix (Code):**
```swift
// Änderung: searchText-Didset triggert nicht sofort die Invalidierung,
// sondern erst wenn der nächste Zugriff kommt (lazy invalidation).
// Zusätzlich: Bloom-Filter für Tag-Filterung bei großen Vaults.
public var searchText: String = "" {
    didSet {
        guard searchText != oldValue else { return }
        invalidateFilterCache()
    }
}
```
Das ist bereits so implementiert — gut. Empfehlung für große Vaults: `filteredTree` in Background-Task berechnen und nur das Ergebnis zuweisen.

---

### 🚨 [Performance] `VectorEmbeddingService` — Cosine Similarity ohne SIMD-Batching

- **Schweregrad:** Mittel
- **Das Problem:** Die Cosine-Similarity-Berechnung mit `vDSP` ist gut, aber bei einer Suche über 10.000+ Vektoren wird jeder Vektor einzeln verglichen. Matrix-Multiplikation (`cblas_sgemv`) wäre 5-10x schneller für Batch-Vergleiche.
- **Der Fix (Code):**
```swift
import Accelerate

/// Batch cosine similarity: query vs. matrix of stored embeddings
func batchCosineSimilarity(query: [Float], matrix: [[Float]]) -> [Float] {
    let dim = query.count
    let count = matrix.count
    // Flatten matrix for BLAS
    let flat = matrix.flatMap { $0 }
    var results = [Float](repeating: 0, count: count)

    flat.withUnsafeBufferPointer { matPtr in
        query.withUnsafeBufferPointer { qPtr in
            results.withUnsafeMutableBufferPointer { resPtr in
                cblas_sgemv(
                    CblasRowMajor, CblasNoTrans,
                    Int32(count), Int32(dim),
                    1.0, matPtr.baseAddress!, Int32(dim),
                    qPtr.baseAddress!, 1,
                    0.0, resPtr.baseAddress!, 1
                )
            }
        }
    }
    // Normalize by norms
    // ...
    return results
}
```

---

### 🚨 [Performance] `AudioRecordingService` — Timer-basiertes Metering ohne Display Link

- **Schweregrad:** UI-Polish
- **Das Problem:** Die Audio-Metering-Anzeige verwendet einen `Timer` mit fester Rate. Auf ProMotion-Displays (120Hz) erzeugt dies entweder zu viele oder zu wenige Updates. Ein `CADisplayLink` (iOS) bzw. `CVDisplayLink` (macOS) wäre frame-synchron.
- **Der Fix (Code):**
```swift
#if canImport(UIKit)
// iOS: CADisplayLink für frame-synchrone Updates
private var displayLink: CADisplayLink?

func startMetering() {
    displayLink = CADisplayLink(target: self, selector: #selector(updateMeters))
    displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
    displayLink?.add(to: .main, forMode: .common)
}
#endif
```

---

### 🚨 [Performance] `BacklinkUseCase` — Parallel Scanning ohne Throttling

- **Schweregrad:** Mittel
- **Das Problem:** `BacklinkUseCase` verwendet `withThrowingTaskGroup` für paralleles Scanning aller Notes. Bei einem Vault mit 5000+ Notes werden 5000+ gleichzeitige File-I/O Operationen gestartet, was den File-Descriptor-Limit überschreiten kann.
- **Der Fix (Code):**
```swift
public func findBacklinks(to noteURL: URL, in tree: [FileNode]) async throws -> [FileNode] {
    let targetName = noteURL.deletingPathExtension().lastPathComponent
    let allNotes = flattenNotes(tree).filter { $0.url != noteURL }
    let maxConcurrency = 16

    return try await withThrowingTaskGroup(of: FileNode?.self) { group in
        var results: [FileNode] = []
        var iterator = allNotes.makeIterator()

        // Seed initial batch
        for _ in 0..<maxConcurrency {
            guard let note = iterator.next() else { break }
            group.addTask { /* scan note */ }
        }

        // Process results, add new tasks
        for try await result in group {
            if let node = result { results.append(node) }
            if let note = iterator.next() {
                group.addTask { /* scan note */ }
            }
        }
        return results
    }
}
```

---

## Gesamtnote

### B+ (Gut mit Verbesserungspotential)

**Stärken:**
- Saubere Clean-Architecture-Schichtung (Data / Domain / Presentation)
- Konsequente Nutzung von Swift 6 `@Observable` und Actor-Isolation
- Durchgehende Lokalisierung mit `String(localized:bundle:.module)` in 7 Sprachen
- Exzellentes Design-System (`LiquidGlass.swift`) mit `reduceMotion`-Support
- Korrekte `NSFileCoordinator`-Nutzung für iCloud-Safety
- Vorbildliche `Sendable`-Conformance in Domain Models
- Gute Accessibility-Grundlagen mit `.accessibilityLabel`/`.accessibilityHint`

**Schwächen:**
- `@unchecked Sendable` umgeht Swift 6 Checks an kritischen Stellen
- Keine Benutzer-Interaktion bei iCloud Sync-Konflikten (stiller Datenverlust)
- Generische Fehlermeldungen ohne Logging/Diagnostics
- Potentielle Actor-Blockaden durch synchrones `NSFileCoordinator` I/O
- Fehlende Testbarkeit des Singleton-ServiceContainers

---

## Top 3 Architektur-Prioritäten

### 1. `@unchecked Sendable` → Actors/structured concurrency migrieren
**Warum:** `DefaultFeatureGate` und `ProFeatureGate` umgehen Swift 6 Concurrency-Checks. Ein vergessener Lock erzeugt Data Races ohne Compiler-Warnung. Migration zu Actor eliminiert diese Klasse von Bugs vollständig.
**Aufwand:** ~2 Tage
**Impact:** Eliminiert potentielle Crashes in Production

### 2. iCloud Conflict Resolution mit User-Facing UI
**Warum:** Stille Konfliktlösung (`resolveConflictKeepingCurrent`) löscht Benutzerarbeit. Für eine Notes-App ist Datenverlust der gravierendste Fehler. Eine Merge/Choose-UI ist essentiell.
**Aufwand:** ~3-5 Tage
**Impact:** Verhindert unwiederbringlichen Datenverlust bei Multi-Geräte-Nutzung

### 3. NSFileCoordinator-Aufrufe auf Background-Queue verlagern
**Warum:** Synchrones `NSFileCoordinator.coordinate()` auf Actors blockiert den gesamten Actor. Bei gleichzeitigem Zugriff (Autosave + Verschlüsselung + Sync) entstehen Deadlocks. Alle `coordinate()`-Aufrufe müssen in `withCheckedThrowingContinuation` + `DispatchQueue.global()` gewrappt werden.
**Aufwand:** ~1-2 Tage
**Impact:** Eliminiert Freezes und potentielle Deadlocks
