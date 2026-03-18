# Quartz Code Review Audit Plan v5.0
## Staff iOS/macOS Engineer x Apple Design Award Judge

**Datum:** 18. Maerz 2026
**Scope:** ~95 Swift-Dateien (QuartzKit Framework + App Target)
**Swift Version:** 6.0 | **Platforms:** iOS 18+, macOS 15+
**Reviewer:** Staff Engineer - Vollstaendiges Code-Review aller Dateien

---

## Executive Summary

Quartz zeigt eine **solide architektonische Basis** mit klarer Schichttrennung (Data/Domain/Presentation), modernem Swift 6 (`@Observable`, actor isolation, `Sendable`), und einem durchdachten Design System. Die App hat **echtes Potenzial** fuer einen Apple Design Award.

Allerdings gibt es **kritische Luecken** in der iCloud-Integration, **architektonische Schwaechen** im Dependency Injection, **Performance-Risiken** beim Markdown-Rendering, und mehrere **UI-Polish-Issues**, die vor einem Release behoben werden muessen.

**Starken:**
- Durchgehend Spring-Animationen (keine `linear` ausser Shimmer)
- `accessibilityReduceMotion` in JEDEM AnimationModifier
- Korrekte 44x44pt Touch Targets
- 7 Sprachen mit korrekter Pluralisierung (`inflect: true`)
- Path-Traversal-Protection auf Security-Audit-Niveau
- Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Actor-isolierte File-I/O mit `NSFileCoordinator`

---

## Saule 1: Cross-Platform & Compiler-Kompatibilitaet (iOS, iPadOS, macOS)

---

### 1.1 DrawingCanvasView: Abweichende macOS-Fallback-Signatur

**Schweregrad: Mittel**

**Das Problem:** `DrawingCanvasView.swift` nutzt `#if canImport(PencilKit) && canImport(UIKit)` korrekt und liefert einen Fallback-View fuer macOS (Zeile 219-258). Allerdings hat der macOS-Fallback `DrawingBlockView` eine **abweichende Initialisierungs-Signatur** - er akzeptiert nur `drawingID` und `height`, waehrend die iOS-Variante (Zeile 92-103) auch `initialDrawing` und `onSave` akzeptiert. Wenn ein Aufrufer die iOS-Signatur nutzt, **kompiliert das auf macOS nicht**.

**Der Fix (Code):**
```swift
// DrawingCanvasView.swift - macOS Fallback (ab Zeile 219)
#else
import SwiftUI

public struct DrawingBlockView: View {
    let drawingID: String
    let height: CGFloat

    public init(
        drawingID: String,
        initialDrawing: Data? = nil,   // Akzeptiere, ignoriere
        height: CGFloat = 300,
        onSave: ((Data) -> Void)? = nil // Akzeptiere, ignoriere
    ) {
        self.drawingID = drawingID
        self.height = height
    }
    // body bleibt identisch
}
#endif
```

---

### 1.2 HandwritingOCRService: Toter AppKit-Import innerhalb PencilKit-Guard

**Schweregrad: UI-Polish**

**Das Problem:** `HandwritingOCRService.swift:7-9` importiert `#if canImport(AppKit) import AppKit #endif` innerhalb des `#if canImport(PencilKit)` Guards. Da PencilKit auf macOS **niemals** verfuegbar ist, wird dieser Code nie kompiliert. Es ist toter Code, der Verwirrung stiftet.

**Der Fix (Code):**
```swift
// HandwritingOCRService.swift - Entferne den toten AppKit-Import
#if canImport(Vision) && canImport(PencilKit)
import Foundation
import Vision
import PencilKit
import CoreGraphics
import os
// ENTFERNT: #if canImport(AppKit) import AppKit #endif
```

---

### 1.3 sensoryFeedback auf macOS: Fehlendes visuelles Aequivalent

**Schweregrad: Mittel**

**Das Problem:** `NoteEditorView.swift:44-45` und `SidebarView.swift:120-121` nutzen `.sensoryFeedback()`. Auf macOS ist das ein No-Op (keine Haptic Engine). Es fehlt ein **visuelles Feedback-Aequivalent** auf macOS. Beim manuellen Speichern bekommt der User auf dem Mac **keinerlei Bestaetigung** ausser der Status-Aenderung in der kleinen Status-Bar.

**Der Fix (Code):**
```swift
// NoteEditorView.swift - Nach sensoryFeedback
#if os(macOS)
.onChange(of: viewModel.manualSaveCompleted) { _, _ in
    NSHapticFeedbackManager.defaultPerformer
        .perform(.alignment, performanceTime: .now)
}
#endif
```

---

### 1.4 Korrekt implementierte Platform-Checks (Positiv)

**Status: OK** - Folgende sind korrekt:
- `MarkdownTextView.swift`: Separate `UIViewRepresentable` / `NSViewRepresentable` mit `#if canImport(UIKit)` / `#elseif canImport(AppKit)`
- `LiquidGlass.swift`: `adaptiveColor()` mit `#if canImport(UIKit)` / `#elseif canImport(AppKit)` und `QuartzColors` semantische Farben
- `FileNodeRow.swift:40-44`: `.hoverEffect(.highlight)` nur auf iOS, `.focusable()` auf macOS
- `OnboardingView.swift:334`: `.hoverEffect(.highlight)` hinter `#if os(iOS)`
- `QuartzApp.swift:38-48`: macOS `Settings` Scene und `.defaultSize`
- `FileSystemVaultProvider.deleteNote()`: `trashItem` auf macOS, manueller .trash-Ordner auf iOS
- `VaultPickerView.swift:88-100`: `.withSecurityScope` auf macOS, `.minimalBookmark` auf iOS

---

## Saule 2: Architektur, Verdrahtung & Memory Management

---

### 2.1 ServiceContainer: Singleton-Pattern verhindert Testbarkeit

**Schweregrad: Hoch**

**Das Problem:** `ServiceContainer.shared` (Zeile 12) ist ein Singleton mit `@MainActor`-Isolation. Unit-Tests koennen den globalen State nicht zuruecksetzen, da kein `reset()`-Mechanismus existiert. Auch: Preview-Support ist eingeschraenkt, weil Views den Singleton aufrufen statt DI via `@Environment`.

Die Basis fuer Environment-DI ist **bereits vorhanden** (`FeatureGating`, `AppearanceManager`, `FocusModeManager` nutzen alle `EnvironmentKey`). Nur `VaultProviding` und `FrontmatterParsing` werden noch ueber den Singleton aufgeloest.

**Der Fix (Code):**
```swift
// ServiceContainer.swift - Testbarkeit hinzufuegen
@MainActor
public final class ServiceContainer {
    public static let shared = ServiceContainer()

    #if DEBUG
    /// Resets all registrations for testing.
    public func reset() {
        vaultProvider = nil
        frontmatterParser = nil
        featureGate = nil
        isBootstrapped = false
    }
    #endif
    // ... Rest bleibt gleich
}
```

**Langfristig-Migration:** Ziehe `VaultProviding` in einen `EnvironmentKey`:
```swift
private struct VaultProviderKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: any VaultProviding =
        FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
}

extension EnvironmentValues {
    public var vaultProvider: any VaultProviding {
        get { self[VaultProviderKey.self] }
        set { self[VaultProviderKey.self] = newValue }
    }
}
```

---

### 2.2 ContentViewModel: Unkontrollierte Tasks ohne Cancellation

**Schweregrad: Hoch**

**Das Problem:** `ContentViewModel.loadVault()` (Zeile 35-39) erstellt einen `Task` ohne ihn zu speichern. Wenn der User schnell zwischen Vaults wechselt, laufen **mehrere Tasks parallel** und koennen sich gegenseitig ueberschreiben. Das ist ein Race Condition: der zuerst gestartete Task koennte nach dem zweiten fertig werden und veraltete Daten in `searchIndex` schreiben.

**Der Fix (Code):**
```swift
// ContentViewModel.swift
private var loadVaultTask: Task<Void, Never>?

public func loadVault(_ vault: VaultConfig) {
    loadVaultTask?.cancel() // Vorherigen Load abbrechen
    editorViewModel?.cancelAllTasks()
    editorViewModel = nil

    let provider = ServiceContainer.shared.resolveVaultProvider()
    let viewModel = SidebarViewModel(vaultProvider: provider)
    sidebarViewModel = viewModel
    let index = VaultSearchIndex(vaultProvider: provider)
    searchIndex = index

    loadVaultTask = Task {
        await viewModel.loadTree(at: vault.rootURL)
        guard !Task.isCancelled else { return }
        await index.indexFromPreloadedTree(viewModel.fileTree)
    }
}
```

---

### 2.3 ProFeatureGate: `@unchecked Sendable` mit NSLock statt OSAllocatedUnfairLock

**Schweregrad: Hoch**

**Das Problem:** `ProFeatureGate.swift:15` nutzt `@unchecked Sendable` mit manuellem `NSLock`. Der Rest der Codebasis nutzt konsequent `OSAllocatedUnfairLock` (z.B. `FileWatcher.swift:82`, `HandwritingOCRService.swift:94`, `TranscriptionService.swift:111`). Das ist inkonsistent und `NSLock` ist **langsamer** als `OSAllocatedUnfairLock`.

**Der Fix (Code):**
```swift
// ProFeatureGate.swift
final class ProFeatureGate: FeatureGating, @unchecked Sendable {
    static let proProductID = "olli.Quartz.pro"

    private let purchaseState = OSAllocatedUnfairLock(initialState: false)
    private var transactionTask: Task<Void, Never>?

    private var hasPurchasedPro: Bool {
        get { purchaseState.withLock { $0 } }
        set { purchaseState.withLock { $0 = newValue } }
    }

    private let base = DefaultFeatureGate()
    // ... Rest bleibt gleich
}
```

---

### 2.4 AppState.errorMessage: Anti-Pattern Computed Setter

**Schweregrad: Mittel**

**Das Problem:** `AppState.swift:37-46` implementiert `errorMessage` als computed property mit einem Setter, der bei `nil` den ersten Eintrag entfernt und bei einem String-Wert appendet. Das ist ein **Anti-Pattern**, weil:
1. `appState.errorMessage = "Fehler A"` gefolgt von `appState.errorMessage = "Fehler B"` setzt den Wert nicht auf "Fehler B", sondern fuegt "Fehler B" zur Queue hinzu - **ueberraschend** fuer den Caller.
2. `dismissCurrentError()` und `errorMessage = nil` haben **identisches Verhalten** - redundante API.

**Der Fix (Code):**
```swift
// AppState.swift - Explizite API
@Observable
@MainActor
public final class AppState {
    /// Aktuell angezeigte Fehlermeldung (read-only).
    public var errorMessage: String? { errorQueue.first }

    private var errorQueue: [String] = []

    /// Zeigt einen Fehler an.
    public func showError(_ message: String) {
        errorQueue.append(message)
    }

    /// Entfernt den aktuellen Fehler.
    public func dismissCurrentError() {
        guard !errorQueue.isEmpty else { return }
        errorQueue.removeFirst()
    }
    // ...
}
```

---

### 2.5 `_ = proFeatureGate.observeTransactionUpdates()` ist irrefuehrend

**Schweregrad: UI-Polish**

**Das Problem:** `QuartzApp.swift:26` schreibt `_ = proFeatureGate.observeTransactionUpdates()`. Die Methode gibt `Void` zurueck. `_ =` suggeriert, dass ein Wert verworfen wird. Das ist irrefuehrend.

**Der Fix:** Entferne `_ =`:
```swift
proFeatureGate.observeTransactionUpdates()
```

---

### 2.6 Architekturelle Staerken (Positiv)

Die folgenden Patterns sind **exzellent** implementiert:
- **@Observable + @MainActor**: `AppState`, `ContentViewModel`, `SidebarViewModel`, `NoteEditorViewModel`, `AppearanceManager`, `FocusModeManager` - alle konsistent
- **Actor-isolierte Services**: `FileSystemVaultProvider`, `CloudSyncService`, `FileWatcher`, `VaultSearchIndex`, `HandwritingOCRService`, `TranscriptionService`, `BiometricAuthService`, `KeychainHelper`, `CustomModelStore`
- **Protocol-basierte Abstraction**: `VaultProviding`, `FrontmatterParsing`, `FeatureGating`, `AIProvider`
- **Clean Architecture Layers**: Data (FileSystem/, Markdown/, FeatureConfig/) -> Domain (Models/, Protocols/, UseCases/, AI/, OCR/, Audio/, Security/) -> Presentation (App/, Editor/, Sidebar/, Settings/, Onboarding/, Chat/, DesignSystem/, Widgets/, QuickNote/, ShareExtension/)
- **Environment-basiertes DI**: FeatureGating, AppearanceManager, FocusModeManager

---

## Saule 3: Exception Handling & Edge Cases

---

### 3.1 CloudSyncService existiert, wird aber nicht integriert

**Schweregrad: Kritisch**

**Das Problem:** `CloudSyncService.swift` implementiert:
- `startMonitoring()` fuer Sync-Status-Updates via `NSMetadataQuery`
- `coordinatedRead/Write` fuer iCloud-sichere Dateioperationen
- `conflictVersions()` und `resolveConflictKeepingCurrent()` fuer Konflikt-Handling
- `startDownloading()` fuer On-Demand-Downloads

**Nichts davon wird in der App tatsaechlich aufgerufen.** `FileSystemVaultProvider` hat seine **eigene** `coordinatedRead/Write`-Implementierung, die `CloudSyncService` **nicht** nutzt. Wenn ein User eine Datei oeffnet, die nur in iCloud liegt (`notDownloaded`), wird ein kryptischer Fehler geworfen.

**Der Fix (Code):**
```swift
// FileSystemVaultProvider.swift - readNote()
public func readNote(at url: URL) async throws -> NoteDocument {
    // Pruefe iCloud-Download-Status VOR dem Lesen
    if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
       let status = resourceValues.ubiquitousItemDownloadingStatus,
       status == URLUbiquitousItemDownloadingStatus.notDownloaded {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        throw FileSystemError.fileNotDownloaded(url)
    }

    let data = try await coordinatedRead(at: url)
    // ... Rest bleibt gleich
}

// FileSystemError - Neuer Case:
case fileNotDownloaded(URL)

public var errorDescription: String? {
    // ...
    case .fileNotDownloaded(let url):
        String(localized: "Downloading \"\(url.lastPathComponent)\" from iCloud...", bundle: .module)
}
```

---

### 3.2 VaultPickerView: Bookmark-Fehler ist ein Silent Failure

**Schweregrad: Hoch**

**Das Problem:** `VaultPickerView.swift:87-104` persistiert den Bookmark. Wenn `url.bookmarkData()` fehlschlaegt (Zeile 102-104), wird der Fehler nur **geloggt**, nicht dem User angezeigt. Der Vault wird trotzdem geoeffnet. Beim naechsten App-Start kann der Bookmark nicht aufgeloest werden -> der User verliert den Zugriff auf seinen Vault **ohne Warnung**.

**Der Fix (Code):**
```swift
// VaultPickerView.swift - handleFileImport
case .success(let urls):
    guard let url = urls.first else { return }
    guard url.startAccessingSecurityScopedResource() else {
        errorMessage = String(localized: "Unable to access the selected folder. Please try again.")
        return
    }

    do {
        #if os(macOS)
        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, ...)
        #else
        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, ...)
        #endif

        let vault = VaultConfig(name: url.lastPathComponent, rootURL: url)
        UserDefaults.standard.set(bookmarkData, forKey: "quartz.vault.bookmark.\(vault.id.uuidString)")
        onVaultSelected(vault)
        dismiss()
    } catch {
        url.stopAccessingSecurityScopedResource()
        errorMessage = String(localized: "Could not save access to this folder. Please try again.")
    }
```

---

### 3.3 Fehlende Speicherplatz-Erkennung beim Schreiben

**Schweregrad: Hoch**

**Das Problem:** `coordinatedWrite` in `FileSystemVaultProvider.swift:178-200` nutzt `.atomic` Writing. Bei vollem Speicher wirft `.write(to:options:.atomic)` einen generischen Cocoa-Fehler. Der User sieht "An unexpected error occurred." statt einer hilfreichen Meldung.

**Der Fix (Code):**
```swift
// NoteEditorViewModel.swift - save() catch-Block
} catch {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain,
       nsError.code == NSFileWriteOutOfSpaceError {
        errorMessage = String(localized: "Not enough storage space. Free up space and try again.", bundle: .module)
    } else if nsError.domain == NSCocoaErrorDomain,
              nsError.code == NSFileWriteVolumeReadOnlyError {
        errorMessage = String(localized: "This folder is read-only.", bundle: .module)
    } else {
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? String(localized: "An unexpected error occurred.", bundle: .module)
    }
    scheduleAutosave()
}
```

---

### 3.4 FrontmatterParser: Multiline-YAML nicht unterstuetzt

**Schweregrad: Mittel**

**Das Problem:** `FrontmatterParser.parseYAML()` (Zeile 78-127) parst Zeile fuer Zeile mit `components(separatedBy: .newlines)`. Multiline-YAML-Werte (z.B. `ocr_text` ueber mehrere Zeilen, oder Block-Scalars mit `|` oder `>`) werden **abgeschnitten**. Nur die erste Zeile wird erfasst - das ist **stiller Datenverlust**.

**Der Fix:** Fuer v1.0 akzeptabel mit klarer Dokumentation. Fuer spaeter: Implementiere YAML-Block-Scalar-Support oder nutze eine YAML-Bibliothek (Yams).

---

### 3.5 Positiv: Korrekte Error-Handling-Patterns

- `FileSystemError` implementiert `LocalizedError` mit benutzerfreundlichen Fehlermeldungen
- `CloudSyncError` und `AIProviderError` ebenfalls mit `LocalizedError`
- `TranscriptionService` und `HandwritingOCRService` haben dedizierte Error-Enums
- `BiometricAuthService` unterscheidet `success/cancelled/failed` sauber
- HTTP-Response-Validierung in `AIProvider.swift:559-574` mit spezifischen Fehlercodes (401, 429, 5xx)
- `NoteEditorViewModel.save()` snapshot content VOR async gap, prueft danach ob content sich geaendert hat

---

## Saule 4: Apple Design Award Level UI/UX & HIG

---

### 4.1 Animationen: Spring-basiert, Accessibility-respektierend (Exzellent)

**Status: A+**

`QuartzAnimation.swift` definiert **17 benannte Spring-Animationen** mit sorgfaeltig abgestimmten `response`/`dampingFraction`-Werten. Jeder einzelne ViewModifier in `LiquidGlass.swift` prueft `@Environment(\.accessibilityReduceMotion)`. Das Design System bietet:
- `FadeInModifier`, `SlideUpModifier`, `StaggeredAppearModifier` - mit Reduce-Motion-Fallback
- `ScaleInModifier`, `BounceInModifier`, `SpinInModifier` - mit Reduce-Motion-Fallback
- `ShimmerModifier`, `PulseModifier` - mit vollstaendigem Reduce-Motion-Bypass
- `ParallaxModifier` - mit Reduce-Motion-Bypass

**Das ist Apple Design Award-Niveau fuer Animationen.**

---

### 4.2 Touch Targets: 44x44pt konsequent (HIG-konform)

**Status: A**

- `FormattingToolbar.swift:101,125`: `.frame(minWidth: 44, minHeight: 44)`
- `FrontmatterEditorView.swift:85,103,162`: `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())`
- `FloatingButtonStyle` (LiquidGlass.swift:183): `.frame(width: 52, height: 52)` - ueber Minimum

---

### 4.3 Dynamic Type: Font-Scaling mit `editorFontScale` bricht UIFontMetrics

**Schweregrad: Hoch**

**Das Problem:** `MarkdownTextView.swift:95-99` berechnet die Schriftgroesse als `baseSize * editorFontScale`, wobei `baseSize` von `UIFont.preferredFont(forTextStyle: .body).pointSize` kommt. Das Ergebnis wird aber mit `UIFont.systemFont(ofSize:)` erstellt, **nicht** mit `UIFontMetrics.scaledFont(for:)`. Dadurch wird bei Accessibility-Textgroessen (z.B. XXXL) die **System-Skalierung nicht angewendet**.

**Der Fix (Code):**
```swift
// MarkdownTextView.swift - updateUIView
public func updateUIView(_ uiView: MarkdownUITextView, context: Context) {
    let metrics = UIFontMetrics(forTextStyle: .body)
    let baseSize = UIFont.preferredFont(forTextStyle: .body).pointSize
    let customFont = UIFont.systemFont(ofSize: baseSize * editorFontScale)
    let scaledFont = metrics.scaledFont(for: customFont)

    if uiView.font?.pointSize != scaledFont.pointSize {
        uiView.font = scaledFont
    }
    // ...
}
```

---

### 4.4 Focus States auf macOS: Unsichtbar bei Custom ButtonStyles

**Schweregrad: Hoch**

**Das Problem:** `QuartzButton` (LiquidGlass.swift:582) hat `.focusable()` auf macOS, aber `QuartzPressButtonStyle` unterdrueckt den System-Focus-Ring. Der User kann mit Tab navigieren, sieht aber **keinen Focus-Indikator**. Das bricht die HIG fuer Keyboard-Navigation auf macOS.

**Der Fix (Code):**
```swift
// LiquidGlass.swift - QuartzPressButtonStyle
public struct QuartzPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .shadow(/* ... */)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                }
            }
            .animation(reduceMotion ? .default : QuartzAnimation.buttonPress, value: configuration.isPressed)
    }
}
```

---

### 4.5 matchedGeometryEffect in List: Performance-Risiko

**Schweregrad: Mittel**

**Das Problem:** `ContentView.swift:158` setzt `.matchedGeometryEffect(id: node.url, in: noteTransition)` auf **jeden Note-Eintrag** in der Mittelspalte. Das erzeugt bei 500+ Notizen hunderte Geometry-Preferences, die SwiftUI bei jedem Layout-Pass berechnet. `matchedGeometryEffect` ist fuer **View-Transitionen** gedacht, nicht fuer statische Listen.

**Der Fix:** Entferne `matchedGeometryEffect` aus der Liste. Falls eine Notiz-zu-Editor-Transition gewuenscht ist, nutze es **nur auf dem selektierten Item**.

---

### 4.6 `.id()` auf NoteEditorView verhindert Animationen

**Schweregrad: Mittel**

**Das Problem:** `ContentView.swift:198` setzt `.id(editorVM.note?.fileURL)`. Das erzwingt einen **vollstaendigen View-Rebuild** bei jedem Notiswechsel. Die `.transition()` auf Zeile 199-204 wird dadurch **nie sichtbar**, weil `.id()` den View zerstoert und neu erstellt statt zu animieren.

**Der Fix:** Entferne `.id()` und nutze `.contentTransition(.opacity)` oder `animation(_:value:)` mit dem fileURL als Value.

---

### 4.7 Empty State ohne Action-Button

**Schweregrad: UI-Polish**

**Das Problem:** `ContentView.swift:176-180` zeigt "Create a note to get started." ohne einen Button. HIG empfiehlt bei Empty States eine **direkte Handlungsmoeglichkeit**.

**Der Fix:** Fuege einen "New Note"-Button unter dem Empty State hinzu.

---

### 4.8 Design System: Hervorragend (Positiv)

- `QuartzTagBadge`: Pill-Shape, DJB2-Hash fuer deterministische Farben, Selected-State mit Shadow
- `QuartzEmptyState`: Unified empty states mit `symbolEffect(.pulse)`
- `QuartzSectionHeader`: Consistent section styling mit Uppercase/Tracking
- `QuartzButton`: Press-Animation, Gradient-Background, Accessibility
- `GlassBackground`, `GlassCard`: Glassmorphism mit `.ultraThinMaterial` und `.regularMaterial`
- `FloatingButtonStyle`: FAB mit Gradient und Shadow
- `SkeletonRow`: Shimmer-Loading mit `.fill.tertiary`

---

## Saule 5: Lokalisation (L10n) & Internationalisierung (I18n)

---

### 5.1 String Catalogs: Vollstaendig fuer 7 Sprachen

**Status: A**

- Zwei `.xcstrings`: `QuartzKit/Resources/Localizable.xcstrings` (Framework-Strings) und `Quartz/Localizable.xcstrings` (App-Strings)
- Sprachen: EN, DE, FR, ES, IT, ZH-Hans, JA
- Alle UI-Strings nutzen `String(localized:bundle:.module)` korrekt
- Markenname "Quartz" korrekt mit `Text(verbatim:)` (nicht uebersetzt)

---

### 5.2 Pluralisierung: Foundation Automatic Grammar (Exzellent)

**Status: A+**

- `NoteEditorView.swift:133`: `^[\(viewModel.wordCount) word](inflect: true)`
- `FrontmatterEditorView.swift:185`: `^[\(frontmatter.tags.count) tag](inflect: true)`
- Foundation's `inflect` unterstuetzt automatisch alle 7 Zielsprachen

---

### 5.3 RTL-Support: Automatisch durch SwiftUI

**Status: A** - SwiftUI handhabt RTL automatisch. `HStack`, `List`, `NavigationSplitView` spiegeln korrekt.

---

### 5.4 Datums-/Zeitformate: Locale-korrekt

**Status: A**

- `Text(_:style: .date)` und `Text(_:style: .relative)` in FrontmatterEditorView und FileNodeRow
- `en_US_POSIX` fuer Dateinamen in ContentViewModel.createDailyNote() (korrekt)
- `ISO8601DateFormatter` in FrontmatterParser und TranscriptionService

---

## Saule 6: Performance & Device Capabilities

---

### 6.1 File-Tree-Loading: Korrekt auf Background Thread (Exzellent)

**Status: A**

- `FileSystemVaultProvider.loadFileTree()`: `Task.detached(priority: .userInitiated)` fuer rekursives Scanning
- `VaultSearchIndex.indexNodes()`: `withTaskGroup` mit `maxConcurrency = 16`
- Depth-Limit von 50 gegen Stack Overflow
- Symlink-Erkennung gegen Endlosschleifen

---

### 6.2 MarkdownRenderer: Synchrones Parsing auf Main Thread

**Schweregrad: Hoch**

**Das Problem:** `MarkdownUITextView.setMarkdown()` (Zeile 43) ruft `markdownRenderer.render(markdown)` **synchron** auf dem Main Thread auf. `MarkdownRenderer` parst den gesamten Markdown-AST via `swift-markdown` und traversiert ihn mit `AttributedStringVisitor`. Bei langen Dokumenten (5.000+ Zeilen) kann das **16ms+ dauern** und Frame-Drops bei 120Hz ProMotion verursachen.

**Der Fix (Code):**
```swift
// MarkdownTextView.swift - MarkdownUITextView
private var renderTask: Task<Void, Never>?

public func setMarkdown(_ markdown: String) {
    guard !isUpdating else { return }
    renderTask?.cancel()

    renderTask = Task.detached(priority: .userInitiated) {
        let renderer = MarkdownRenderer()
        let attributed = renderer.render(markdown)
        let nsAttributed = try? NSAttributedString(attributed, including: MarkdownAttributes.self)

        await MainActor.run { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.isUpdating = true
            defer { self.isUpdating = false }

            guard let nsAttributed else {
                self.text = markdown
                return
            }
            let selectedRange = self.selectedRange
            self.attributedText = nsAttributed
            if selectedRange.location + selectedRange.length <= nsAttributed.length {
                self.selectedRange = selectedRange
            }
        }
    }
}
```

---

### 6.3 Staggered Animations: Unbegrenzter Delay bei grossen Listen

**Schweregrad: Mittel**

**Das Problem:** `SidebarView.swift:201-203` wendet `.staggered(index: index)` auf jeden FileNode an. Bei 200 Items: 200 * 0.04s = **8 Sekunden** bis das letzte Item erscheint.

**Der Fix:** Cap den Index auf maximal 8-10:
```swift
.staggered(index: min(index, 8))
```

---

### 6.4 Search: O(n) ist akzeptabel fuer v1.0

**Status: B+** - `VaultSearchIndex.search()` iteriert ueber alle Entries. Pre-computed lowercased Strings und 250ms Debounce machen das fuer <5.000 Notizen performant genug. Fuer spaeter: invertierter Index.

---

### 6.5 Word Count und DrawingThumbnail: Korrekt off-thread (Positiv)

- Word Count: `Task.detached(priority: .utility)` mit 300ms Debounce
- DrawingThumbnail: `Task.detached(priority: .userInitiated)` fuer Image-Rendering

---

### 6.6 Haptics: HIG-konform eingesetzt

**Status: B+** - `.sensoryFeedback(.success)` beim Speichern, `.sensoryFeedback(.selection)` bei Tag-Auswahl, `.sensoryFeedback(.warning)` beim Loeschen. Fehlend: Haptic beim Note-Erstellen und Onboarding-Abschluss.

---

## Saule 7 (Bonus): Security

---

### 7.1 Path Traversal Protection (Exzellent)

- Unicode-Normalisierung (`precomposedStringWithCanonicalMapping`)
- Symlink-Aufloesung (`resolvingSymlinksInPath()`)
- Path-Prefix-Validierung in `createFolder`, `rename`, `handleDeepLink`
- Erlaubte Zeichensaetze in `createFolder`

### 7.2 Keychain Best Practices (Exzellent)

- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - strengste Stufe
- API-Keys nicht in Backups

### 7.3 Deep Link Validation (Korrekt)

- `StageManagerModifier.handleDeepLink()` validiert URL-Prefix
- `FileManager.fileExists` Check vor Zugriff

---

## Gesamtnote

### Note: B+ (Sehr Gut - nahe an Apple Design Award, aber Luecken bei iCloud und Performance)

| Saule | Note | Kommentar |
|-------|------|-----------|
| 1. Cross-Platform | B+ | Grundlegend korrekt, kleiner toter Code, fehlendes Mac-Feedback |
| 2. Architektur | A- | Saubere Schichttrennung, Swift 6, DI-Singleton-Schwaeche |
| 3. Exception Handling | B- | iCloud nicht integriert, Bookmark Silent Failure, kein Speicherplatz-Check |
| 4. UI/UX & HIG | A- | Exzellente Animationen, fehlende Focus-States, Performance-Risiken |
| 5. Lokalisation | A | 7 Sprachen, korrekte Pluralisierung, Locale-Formate |
| 6. Performance | B+ | Background-Threading gut, Markdown-Main-Thread ist ein Blocker |
| 7. Security | A | Path Traversal, Keychain, Deep Link Validation |

---

## Top 3 Architektur-Prioritaeten

### Prioritaet 1: iCloud Sync in Vault-Operationen integrieren (Kritisch)
`CloudSyncService` existiert als vollstaendiger Service, wird aber **nirgendwo in der App aufgerufen**. `notDownloaded`-Dateien werfen kryptische Fehler. Sync-Konflikte werden nicht in der UI angezeigt. **Das muss vor Release geloest werden**, da iCloud Drive die Standard-Speichermethode auf Apple-Geraeten ist.

### Prioritaet 2: Markdown-Rendering asynchron (Hoch)
`MarkdownRenderer.render()` blockiert den Main Thread synchron. Bei grossen Dokumenten fuehrt das zu Frame-Drops und zerstoert die 120Hz-ProMotion-Experience auf iPhone Pro und iPad Pro. Migriere zu `Task.detached` Rendering.

### Prioritaet 3: ServiceContainer -> Environment-DI (Hoch)
Der `ServiceContainer.shared` Singleton verhindert Unit-Tests und SwiftUI-Previews. Die Grundlage fuer Environment-DI ist bereits da. Migriere `VaultProviding` und `FrontmatterParsing` in `EnvironmentKey`s fuer eine vollstaendig testbare und preview-faehige Architektur.

---

*Ende des Audit Plans v5.0. Alle Fixes sind Swift 6-kompatibel und HIG 2025-konform.*
