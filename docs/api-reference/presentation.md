# Quartz Presentation Layer API Reference

Generated 2026-03-27. Covers every public type, property, and method in the Presentation layer of QuartzKit.

---

## Table of Contents

1. [App Layer](#app-layer)
   - [AppState](#appstate)
   - [CommandAction](#commandaction)
   - [AppCoordinator](#appcoordinator)
   - [AppSheet](#appsheet)
   - [AppAlert](#appalert)
   - [ContentViewModel](#contentviewmodel)
   - [AppearanceManager](#appearancemanager)
   - [AppearanceManager.Theme](#appearancemanagertheme)
   - [AppearanceManager.EditorFontFamily](#appearancemanageeditorfontfamily)
2. [Editor Layer](#editor-layer)
   - [MarkdownEditorRepresentable (iOS)](#markdowneditorrepresentable-ios)
   - [MarkdownEditorRepresentable (macOS)](#markdowneditorrepresentable-macos)
   - [EditorContainerView](#editorcontainerview)
   - [FocusModeManager](#focusmodemanager)
   - [FocusModeModifier](#focusmodemodifier)
3. [Dashboard](#dashboard)
   - [DashboardView](#dashboardview)
4. [Sidebar](#sidebar)
   - [SidebarView](#sidebarview)
   - [SidebarItemTransferable](#sidebaritemtransferable)
5. [Workspace](#workspace)
   - [WorkspaceView](#workspaceview)
   - [WorkspaceStore](#workspacestore)
   - [SourceSelection](#sourceselection)
6. [Design System](#design-system)
   - [QuartzColors](#quartzcolors)
   - [Color.init(hex:alpha:)](#coloinithexalpha)
   - [QuartzAmbientMeshStyle](#quartzambientmeshstyle)
   - [QuartzAmbientMeshBackground](#quartzambientmeshbackground)
   - [QuartzLiquidGlassModifier](#quartzliquidglassmodifier)
   - [QuartzMaterialBackgroundModifier](#quartzmaterialbackgroundmodifier)
   - [QuartzMaterialLayer](#quartzmateriallayer)
   - [QuartzMaterialCircleModifier](#quartzmaterialcirclemodifier)
   - [GlassBackground](#glassbackground)
   - [GlassCard](#glasscard)
   - [QuartzHIG](#quartzhig)
   - [QuartzTagBadge](#quartztagbadge)
   - [QuartzSectionHeader](#quartzsectionheader)
   - [QuartzButton](#quartzbutton)
   - [QuartzPressButtonStyle](#quartzpressbuttonstyle)
   - [QuartzCardButtonStyle](#quartzcardbuttonstyle)
   - [QuartzBounceButtonStyle](#quartzbouncebuttonstyle)
   - [FloatingButtonStyle](#floatingbuttonstyle)
   - [ShimmerModifier](#shimmermodifier)
   - [ParallaxModifier](#parallaxmodifier)
   - [SkeletonRow](#skeletonrow)
   - [QuartzEmptyState](#quartzemptystate)
   - [View Extensions (Design System)](#view-extensions-design-system)
7. [Settings](#settings)
   - [AppearanceSettingsView](#appearancesettingsview)
   - [EditorSettingsView](#editorsettingsview)

---

# App Layer

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/App/`

---

## AppState

**File:** `AppState.swift`

Global app state injected into all views via SwiftUI Environment. Manages the current vault, error queue, and pending keyboard-shortcut commands.

Decorators: `@Observable`, `@MainActor`

### Properties

- `currentVault: VaultConfig?` -- The currently opened vault. Use `switchVault(to:)` to change it so security-scoped resources are properly released.
- `errorMessage: String?` -- The first pending error message in the queue. Setting a non-nil value enqueues it; setting nil dequeues the current error.
- `pendingCommand: CommandAction` -- Pending command action triggered by keyboard shortcuts or menus. Consumers should reset to `.none` after handling.
- `pendingOpenDocumentScanner: Bool` -- Set by deep links (`quartz://scan`) to present the document scanner when a note is active.

### Methods

#### `init()`

Creates a new `AppState` with no vault and empty error queue.

#### `switchVault(to newVault: VaultConfig?) -> Void`

Switches to a new vault. Releases the security-scoped resource of the previous vault if the root URL differs, then sets `currentVault`.

**Parameters:**
- `newVault` -- The vault configuration to switch to, or `nil` to close the current vault.

#### `dismissCurrentError() -> Void`

Removes the first error from the queue so the next (if any) becomes visible.

#### `showError(_ message: String) -> Void`

Convenience method to enqueue an error message string.

**Parameters:**
- `message` -- The human-readable error text.

---

## CommandAction

**File:** `AppState.swift`

Single command action enum triggered by keyboard shortcuts or menus. Replaces multiple `Bool` toggles to avoid duplicate SwiftUI view updates.

Conforms to: `Equatable`, `Sendable`

### Cases

| Case | Description |
|------|-------------|
| `.none` | No pending action. |
| `.newNote` | Create a new note. |
| `.newFolder` | Create a new folder. |
| `.search` | Open in-app search. |
| `.globalSearch` | Open global search. |
| `.toggleSidebar` | Toggle sidebar visibility. |
| `.dailyNote` | Create or open today's daily note. |
| `.format(FormattingAction)` | Apply a markdown formatting action. |
| `.openVault` | Open an existing vault. |
| `.createVault` | Create a new vault. |

---

## AppCoordinator

**File:** `AppCoordinator.swift`

Centralized routing state for sheets, alerts, and app-level lifecycle. Replaces the scattered `@State` booleans that previously lived in `ContentView`.

Decorators: `@Observable`, `@MainActor`

### Properties

- `activeSheet: AppSheet?` -- The currently presented sheet, or `nil` if none is active. Only one sheet can be active at a time (SwiftUI constraint).
- `isCommandPaletteVisible: Bool` -- Whether the command palette overlay is visible. This is a ZStack overlay, not a modal sheet.
- `activeAlert: AppAlert?` -- The currently presented alert, or `nil`.
- `quickNoteManager: QuickNoteManager?` -- (macOS only) Global hotkey manager for the Quick Note feature.
- `availableUpdate: UpdateChecker.ReleaseInfo?` -- Available app update info fetched from GitHub Releases.

### Methods

#### `init()`

Creates a new coordinator with no active sheet, alert, or command palette.

#### `presentNewNote(in parent: URL) -> Void`

Presents the new-note alert pre-filled with a date-based default name (e.g., "Note 2026-03-27 14-30").

**Parameters:**
- `parent` -- The parent folder URL where the note will be created.

#### `presentNewFolder(in parent: URL) -> Void`

Presents the new-folder alert for the given parent directory.

**Parameters:**
- `parent` -- The parent folder URL.

---

## AppSheet

**File:** `AppCoordinator.swift`

Every sheet the app can present, modeled as a mutually exclusive `Identifiable` enum. Used with `.sheet(item:)` to guarantee only one sheet is active at a time.

Conforms to: `Identifiable`

### Cases

| Case | ID | Description |
|------|----|-------------|
| `.onboarding` | `"onboarding"` | First-launch onboarding flow. |
| `.vaultPicker` | `"vaultPicker"` | Vault selection/open dialog. |
| `.settings` | `"settings"` | App settings. |
| `.search` | `"search"` | Full-text search overlay. |
| `.knowledgeGraph` | `"knowledgeGraph"` | Knowledge graph visualization. |
| `.voiceNote` | `"voiceNote"` | Voice note recording. |
| `.meetingMinutes` | `"meetingMinutes"` | Meeting minutes recorder. |
| `.vaultChat(session:)` | `"vaultChat"` | Legacy vault chat (non-streaming). |
| `.vaultChat2(session:)` | `"vaultChat2"` | Streaming vault chat session. |
| `.conflictResolver` | `"conflictResolver"` | iCloud sync conflict resolution. |

### Properties

- `id: String` -- Stable string identifier for each case.

---

## AppAlert

**File:** `AppCoordinator.swift`

Every alert the app can present. Groups related state together to prevent desynchronization.

Conforms to: `Identifiable`

### Cases

| Case | Description |
|------|-------------|
| `.newNote(parent: URL, suggestedName: String)` | Alert to create a new note, with parent folder and a suggested name. |
| `.newFolder(parent: URL)` | Alert to create a new folder. |

### Properties

- `id: String` -- Stable string identifier (`"newNote"` or `"newFolder"`).

---

## ContentViewModel

**File:** `ContentViewModel.swift`

Coordinates vault loading, note opening, indexing, cloud sync, backup, and command routing. Extracts business logic from `ContentView` so the view remains a thin layout shell.

Decorators: `@Observable`, `@MainActor`

### Properties

- `sidebarViewModel: SidebarViewModel?` -- The active sidebar view model, created when a vault loads.
- `editorViewModel: NoteEditorViewModel?` -- Legacy editor view model (kept for backward compatibility).
- `editorSession: EditorSession?` -- Jitter-free editor session. Reused across note switches to prevent view destruction.
- `documentChatSession: DocumentChatSession?` -- AI chat session scoped to the currently open note.
- `inspectorStore: InspectorStore` -- (let) Inspector state shared across note switches.
- `searchIndex: VaultSearchIndex?` -- In-app full-text search index.
- `embeddingService: VectorEmbeddingService?` -- Vector embedding service for semantic vault search.
- `previewRepository: NotePreviewRepository?` -- Preview cache backing the middle-column note list.
- `previewIndexer: NotePreviewIndexer?` -- Indexer that reads 8KB prefix of each note for title/snippet/tags.
- `cloudSyncStatus: CloudSyncStatus` -- Current iCloud sync status. Default: `.notApplicable`.
- `conflictingFileURLs: [URL]` -- URLs of files with unresolved iCloud sync conflicts.
- `indexingProgress: (current: Int, total: Int)?` -- Current embedding indexing progress, or `nil` when idle.
- `backupService: VaultBackupService` -- (let) Manages export, auto-backup, and restore.
- `availableBackups: [BackupEntry]` -- List of available backups for the current vault.
- `isBackupInProgress: Bool` -- Whether a backup operation is currently running.
- `backupProgress: Double` -- Backup progress from 0.0 to 1.0.
- `lastSyncTimestamp: Date?` -- Last iCloud sync completion time, persisted to UserDefaults.
- `isVaultInICloud: Bool` -- Whether the current vault resides inside iCloud Drive.
- `isICloudAvailable: Bool` -- Whether iCloud is available on this device (resolved asynchronously).

### Methods

#### `init(appState: AppState)`

Creates a new view model backed by the given global app state.

**Parameters:**
- `appState` -- The shared `AppState` instance.

#### `loadVault(_ vault: VaultConfig, noteListStore: NoteListStore?) -> Void`

Loads a vault: creates the sidebar VM, search index, Spotlight indexer, embedding service, preview cache, and editor session. Wires the `NoteListStore` with preview data and indexes all notes.

**Parameters:**
- `vault` -- The vault configuration to load.
- `noteListStore` -- Optional note list store to populate with cached previews.

#### `openNote(at url: URL?) -> Void`

Opens a note by loading it into the existing `EditorSession`. Passing `nil` closes the current note.

**Parameters:**
- `url` -- The file URL of the markdown note, or `nil` to deselect.

#### `createDailyNote() -> Void`

Creates a daily note with today's date as the filename (ISO 8601 format, e.g., `2026-03-27.md`) in the vault root.

#### `createVaultChatSession2() async -> VaultChatSession2?`

Creates a new streaming vault chat session wired to the current embedding service. Performs just-in-time indexing: saves the active note and indexes its live text before creating the session. Returns `nil` if no embedding service or vault is available.

#### `createVaultChatSession() -> VaultChatSession?`

Legacy non-streaming vault chat session factory (kept for backward compatibility).

#### `urlForVaultNote(stableID: UUID) -> URL?`

Resolves a stable vault note ID (used by embeddings/vault chat sources) to the note's file URL.

**Parameters:**
- `stableID` -- The UUID stable ID assigned by `VectorEmbeddingService`.

**Returns:** The file URL of the matching note, or `nil`.

#### `reindexVault() -> Void`

Re-indexes every note in the vault via both the embedding service and Core Spotlight. Can be triggered from the UI (e.g., Settings).

#### `spotlightIndexNote(at url: URL) -> Void`

Indexes a single note in Core Spotlight after save.

**Parameters:**
- `url` -- The file URL of the saved note.

#### `spotlightRemoveNotes(at urls: [URL]) -> Void`

Removes Spotlight entries for deleted markdown files.

**Parameters:**
- `urls` -- Array of deleted note file URLs.

#### `spotlightRelocateNote(from oldURL: URL, to newURL: URL) -> Void`

Updates Spotlight when a note file moves on disk.

**Parameters:**
- `oldURL` -- The previous file URL.
- `newURL` -- The new file URL.

#### `updatePreviewForNote(at url: URL) -> Void`

Incrementally updates the preview cache for a single saved note and posts `.quartzPreviewCacheDidChange`.

**Parameters:**
- `url` -- The file URL of the note.

#### `removePreviewsForNotes(at urls: [URL]) -> Void`

Removes preview entries for deleted notes.

**Parameters:**
- `urls` -- Array of deleted note file URLs.

#### `relocatePreview(from oldURL: URL, to newURL: URL) -> Void`

Updates the preview entry when a note is renamed or moved.

**Parameters:**
- `oldURL` -- Previous file URL.
- `newURL` -- New file URL.

#### `updateEmbeddingForNote(at url: URL) -> Void`

Re-indexes a single note's embeddings after save. Uses live text from `EditorSession` for the active note to avoid stale disk reads.

**Parameters:**
- `url` -- The file URL of the note.

#### `removeEmbeddingsForNotes(at urls: [URL]) -> Void`

Removes embeddings for deleted notes.

**Parameters:**
- `urls` -- Array of deleted note file URLs.

#### `relocateEmbedding(from oldURL: URL, to newURL: URL) -> Void`

Updates embeddings when a note is renamed or moved.

**Parameters:**
- `oldURL` -- Previous file URL.
- `newURL` -- New file URL.

#### `triggerManualBackup() -> Void`

Triggers a manual backup of the current vault. Sets `isBackupInProgress` and updates `backupProgress` during the operation.

#### `restoreFromBackup(backupURL: URL, destination: URL) async throws -> Void`

Restores a backup to a user-chosen destination.

**Parameters:**
- `backupURL` -- The URL of the backup archive.
- `destination` -- The target directory for restoration.

#### `refreshAvailableBackups(vaultRoot: URL?) -> Void`

Refreshes the list of available backups for the current (or specified) vault root.

**Parameters:**
- `vaultRoot` -- Optional vault root URL. Falls back to the current vault if `nil`.

#### `stopCloudSync() -> Void`

Stops iCloud sync monitoring and resets sync status to `.notApplicable`.

#### `checkICloudAvailability() -> Void`

Checks iCloud availability by resolving the ubiquity container asynchronously. Sets `isICloudAvailable`.

#### `migrateVaultToICloud() async -> URL?`

Migrates the current local vault into the app's iCloud ubiquity container. Copies the entire vault directory, then switches the app to the iCloud copy. The original local copy is left untouched.

**Returns:** The new iCloud vault URL, or `nil` if migration failed.

#### `handleCommand(_ command: CommandAction, coordinator: AppCoordinator, workspaceStore: WorkspaceStore) -> Void`

Processes a keyboard shortcut command, routing UI actions through the coordinator. Layout commands (toggle sidebar) route through `WorkspaceStore`.

**Parameters:**
- `command` -- The `CommandAction` to handle.
- `coordinator` -- The `AppCoordinator` for sheet/alert presentation.
- `workspaceStore` -- The `WorkspaceStore` for column visibility changes.

---

## AppearanceManager

**File:** `AppearanceManager.swift`

Manages the app's visual appearance: theme, font, spacing, dark mode, accent color, and dashboard preference. Injected into views via `@Environment(\.appearanceManager)` and persists all settings in `UserDefaults`.

Decorators: `@Observable`, `@MainActor`

### Properties

- `theme: Theme` -- Current color scheme preference (system, light, or dark). Persisted on change.
- `editorFontFamily: EditorFontFamily` -- Editor font family (System/SF Pro, Serif/New York, Monospaced/SF Mono, Rounded/SF Rounded). Persisted on change.
- `editorFontSize: CGFloat` -- Editor font size in points, clamped to 12-24. Persisted on change.
- `editorFontScale: Double` -- Computed font scale derived from `editorFontSize` (`size / 16.0`). Setting it updates `editorFontSize`.
- `editorLineSpacing: CGFloat` -- Line height multiplier, clamped to 1.0-2.5. Default: 1.5.
- `editorMaxWidth: CGFloat` -- Maximum text column width in points, clamped to 400-1200. Default: 720.
- `pureDarkMode: Bool` -- True black background in dark mode for OLED displays.
- `vibrantTransparency: Bool` -- Glass effect on sidebar/title bar. Default: `true`.
- `accentColorHex: UInt` -- Accent color as a hex integer (e.g., `0xF2994A` for orange).
- `showDashboardOnLaunch: Bool` -- Whether to show the dashboard when no note is selected (macOS). Default: `true`.
- `accentColor: Color` -- (computed, read-only) Resolved SwiftUI `Color` from `accentColorHex`.

### Methods

#### `init(defaults: UserDefaults)`

Loads all settings from the given `UserDefaults` store (defaults to `.standard`). Performs migration from legacy `editorFontScale` key if `editorFontSize` was never set.

**Parameters:**
- `defaults` -- The `UserDefaults` store to read from and write to.

### Environment Key

Access via `@Environment(\.appearanceManager)`:

```swift
@Environment(\.appearanceManager) private var appearance
```

---

## AppearanceManager.Theme

**File:** `AppearanceManager.swift`

Color scheme preference enum.

Conforms to: `String` (raw value), `CaseIterable`, `Codable`, `Sendable`

### Cases

| Case | Display Name | Color Scheme |
|------|--------------|--------------|
| `.system` | "System" | `nil` (follows system) |
| `.light` | "Light" | `.light` |
| `.dark` | "Dark" | `.dark` |

### Properties

- `displayName: String` -- Localized display name.
- `colorScheme: ColorScheme?` -- The SwiftUI `ColorScheme`, or `nil` for system default.

---

## AppearanceManager.EditorFontFamily

**File:** `AppearanceManager.swift`

Editor font family enum.

Conforms to: `String` (raw value), `CaseIterable`, `Codable`, `Sendable`

### Cases

| Case | Display Name | Typeface |
|------|--------------|----------|
| `.system` | "System" | SF Pro |
| `.serif` | "Serif" | New York |
| `.monospaced` | "Monospaced" | SF Mono |
| `.rounded` | "Rounded" | SF Rounded |

### Properties

- `displayName: String` -- Localized display name.

---

# Editor Layer

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/Editor/`

---

## MarkdownEditorRepresentable (iOS)

**File:** `MarkdownEditorRepresentable.swift`

Native `UITextView` bridge for the `EditorSession`-based editor. Implements `UIViewRepresentable`.

**Critical design:** No `@Binding var text`. The native text view is the source of truth. `updateUIView` never writes text to the view, eliminating the SwiftUI-to-TextKit feedback cycle that caused cursor jitter.

### Properties

- `session: EditorSession` -- The editor session that owns all text state.
- `editorFontScale: CGFloat` -- Font scale multiplier (default: 1.0).
- `editorFontFamily: AppearanceManager.EditorFontFamily` -- Font family (default: `.system`).
- `editorLineSpacing: CGFloat` -- Line spacing multiplier (default: 1.5).
- `editorMaxWidth: CGFloat` -- Maximum text column width in points (default: 720).

### Methods

#### `init(session:editorFontScale:editorFontFamily:editorLineSpacing:editorMaxWidth:)`

Creates the representable with the given editor session and appearance settings.

#### `makeCoordinator() -> Coordinator`

Creates a `Coordinator` that acts as the `UITextViewDelegate`.

#### `makeUIView(context:) -> UITextView`

Builds and configures the `UITextView` with TextKit 2 stack, sets up the highlighter, wires the session, enables Writing Tools (iOS 18.1+), and performs the one-time initial text load.

#### `updateUIView(_ uiView:context:) -> Void`

Handles font/line-spacing changes (triggers rehighlight) and dynamic max-width inset calculation. Never writes text to the view.

### Coordinator (iOS)

`@MainActor public final class Coordinator: NSObject, UITextViewDelegate`

Manages text view delegate callbacks, list continuation on newline, scroll tracking, and selection changes.

#### Delegate Methods

- `scrollViewDidScroll(_:)` -- Throttled (100ms) scroll tracking; reports top character offset to `EditorSession.viewportDidScroll`.
- `textView(_:shouldChangeTextIn:replacementText:) -> Bool` -- Intercepts newline for markdown list continuation via `MarkdownListContinuation`. Uses surgical insert through `EditorSession.applyExternalEdit`.
- `textViewDidChange(_:)` -- Forwards text snapshot to `EditorSession.textDidChange`.
- `textViewDidChangeSelection(_:)` -- Forwards selection range to `EditorSession.selectionDidChange`.

---

## MarkdownEditorRepresentable (macOS)

**File:** `MarkdownEditorRepresentable.swift`

Native `NSTextView` bridge for the `EditorSession`-based editor. Implements `NSViewRepresentable`. Same architectural principles as the iOS variant.

### Properties

Same as iOS variant: `session`, `editorFontScale`, `editorFontFamily`, `editorLineSpacing`, `editorMaxWidth`.

### Methods

#### `init(session:editorFontScale:editorFontFamily:editorLineSpacing:editorMaxWidth:)`

Creates the representable with the given editor session and appearance settings.

#### `makeCoordinator() -> Coordinator`

Creates a `Coordinator` that acts as the `NSTextViewDelegate`.

#### `makeNSView(context:) -> NSScrollView`

Builds the `NSScrollView` + `NSTextView` with TextKit 2 stack, configures the text view (undo support, insertion point color, Writing Tools on macOS 15.1+), wires the session, and sets up scroll position observation via `NSView.boundsDidChangeNotification`.

#### `updateNSView(_ nsView:context:) -> Void`

Handles font/line-spacing changes (triggers rehighlight) and dynamic max-width inset calculation. Never writes text to the view.

### Coordinator (macOS)

`@MainActor public final class Coordinator: NSObject, NSTextViewDelegate`

Manages text view delegate callbacks for macOS.

#### Delegate Methods

- `scrollViewDidScroll(_:)` -- Throttled scroll tracking via `NSView.boundsDidChangeNotification`; reports top character offset.
- `textView(_:shouldChangeTextIn:replacementString:) -> Bool` -- Intercepts newline for markdown list continuation.
- `textDidChange(_:)` -- Forwards text snapshot to `EditorSession.textDidChange`.
- `textViewDidChangeSelection(_:)` -- Forwards selection range to `EditorSession.selectionDidChange`.

---

## EditorContainerView

**File:** `EditorContainerView.swift`

SwiftUI host for the markdown editor. Owns no text state -- all editing flows through `EditorSession`. Provides the formatting toolbar, status bar, inspector panel, conflict/external-modification banners, AI writing tools sheet, and document chat sheet.

### Properties

- `session: EditorSession` -- The editor session (required).
- `workspaceStore: WorkspaceStore?` -- Optional workspace store for layout coordination.
- `documentChatSession: DocumentChatSession?` -- Optional AI chat session for the current document.
- `onVoiceNote: (() -> Void)?` -- Callback to record a voice note.
- `conflictedNoteURLs: Set<URL>` -- URLs of notes with unresolved iCloud sync conflicts.
- `onResolveConflict: ((URL) -> Void)?` -- Callback when user taps a conflict resolution action.

### Methods

#### `init(session:workspaceStore:documentChatSession:onVoiceNote:conflictedNoteURLs:onResolveConflict:)`

Creates an editor container with all required and optional dependencies.

### Body Structure

The view is composed of:

1. **Editor header** -- Note title with unsaved-changes indicator dot.
2. **MarkdownEditorRepresentable** -- The native text view bridge.
3. **Status bar** -- Word count, reading time, and save progress indicator.
4. **Overlays:**
   - Sync conflict banner (when the current note has an unresolved conflict).
   - External modification banner (reload / keep editing options).
5. **Toolbar items:**
   - iOS: Floating `IosEditorToolbar` with formatting, save, and AI assist.
   - macOS: `MacEditorToolbar` in the principal placement.
   - Voice note, share/export, focus mode toggle, document chat, and inspector toggle buttons.
6. **Inspector** (macOS only): `InspectorSidebar` with table of contents, stats, and metadata.
7. **Sheets:**
   - AI Writing Tools (`AIWritingToolsView`) -- presented via `Identifiable` item binding.
   - Document Chat (`DocumentChatView`).

---

## FocusModeManager

**File:** `FocusModeManager.swift`

Manages focus mode and typewriter mode. Injected via `@Environment(\.focusModeManager)`.

- **Focus Mode:** Hides all UI elements (sidebar, toolbar, status bar).
- **Typewriter Mode:** The active line stays vertically centered; surrounding lines are dimmed.

Decorators: `@Observable`, `@MainActor`

### Properties

- `isFocusModeActive: Bool` -- Focus mode toggle. Always starts `false` on launch (session-only state). Persisted to UserDefaults for reads only.
- `isTypewriterModeActive: Bool` -- Typewriter mode toggle. Persisted across launches.
- `dimmedLineOpacity: Double` -- Opacity for inactive lines in typewriter mode. Default: `0.3`.

### Methods

#### `init()`

Creates the manager. Focus mode always starts OFF; typewriter mode state is restored from UserDefaults.

#### `toggleFocusMode() -> Void`

Toggles focus mode with a `QuartzAnimation.content` animation.

#### `toggleTypewriterMode() -> Void`

Toggles typewriter mode with a `QuartzAnimation.content` animation.

### Environment Key

```swift
@Environment(\.focusModeManager) private var focusMode
```

---

## FocusModeModifier

**File:** `FocusModeManager.swift`

`ViewModifier` that hides the modified view when focus mode is active (opacity 0, hit-testing disabled).

### Usage

```swift
someView.hidesInFocusMode()
```

The `hidesInFocusMode()` extension on `View` applies this modifier.

---

# Dashboard

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/Dashboard/`

---

## DashboardView

**File:** `DashboardView.swift`

Premium macOS vault dashboard using Liquid Glass (regularMaterial) containers. Features: Quick Capture, AI Briefing, Serendipity ("On This Day"), Recent Notes, Action Items, and a 26-week Activity Heatmap.

### Properties

- `sidebarViewModel: SidebarViewModel?` -- The sidebar view model, used to access the file tree.
- `vaultProvider: (any VaultProviding)?` -- Vault provider for reading note contents.
- `onSelectNote: (URL) -> Void` -- Callback when a note is tapped.
- `onNewNote: () -> Void` -- Callback to create a new note.
- `onExploreGraph: () -> Void` -- Callback to open the knowledge graph.
- `onRecordVoiceNote: (() -> Void)?` -- Optional callback for voice note recording.
- `onRecordMeetingMinutes: (() -> Void)?` -- Optional callback for meeting minutes recording.
- `onQuickCapture: ((String) -> Void)?` -- Optional callback for quick capture text submission.

### Methods

#### `init(sidebarViewModel:vaultProvider:onSelectNote:onNewNote:onExploreGraph:onRecordVoiceNote:onRecordMeetingMinutes:onQuickCapture:)`

Creates the dashboard view with all required and optional dependencies.

### Body Structure

The view renders a scrollable layout:

1. **Header row** -- Time-based greeting ("Good Morning/Afternoon/Evening"), current date, and a `ControlGroup` with New Note, Graph, Voice, and Meeting buttons.
2. **Stats row** -- Note count, folder count, and open task count.
3. **Quick Capture bar** -- Text field that appends to the daily note on Enter.
4. **Briefing and Serendipity row:**
   - AI Briefing pane -- Weekly summary generated from recent notes (requires AI provider).
   - Serendipity pane -- Random note suggestion, preferring "on this day" (1 year ago).
5. **Content columns:**
   - Recent Notes pane -- Up to 8 most recently modified notes.
   - Action Items pane -- Up to 10 open `- [ ]` tasks parsed from recent notes, with toggle-to-complete.
6. **Momentum heatmap** -- 26-week (182-day) activity grid showing note edit frequency with hover tooltips.

---

# Sidebar

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/Sidebar/`

---

## SidebarView

**File:** `SidebarView.swift`

Native sidebar using Apple's recommended patterns: `List(selection:)` for selection, `OutlineGroup` for hierarchical file tree, `.tag()` for note selection binding, and `.draggable`/`.dropDestination` for drag-and-drop.

### Properties

- `viewModel: SidebarViewModel` -- (Bindable) The sidebar view model providing file tree, tags, and operations.
- `selectedNoteURL: Binding<URL?>` -- Two-way binding to the currently selected note URL.
- `onMapViewTap: (() -> Void)?` -- Callback to open the knowledge graph map view.
- `onDoubleClick: ((URL) -> Void)?` -- Callback for double-clicking a note (macOS: open in new window).
- `onSourceChanged: ((SourceSelection) -> Void)?` -- Callback when the user changes the source filter.
- `onVaultChat: (() -> Void)?` -- Callback to open vault chat.
- `onSearchChanged: ((String) -> Void)?` -- Callback when the search query changes (200ms debounce).
- `onDashboard: (() -> Void)?` -- Callback to show the dashboard.
- `onSwitchVault: (() -> Void)?` -- Callback to switch vaults.

### Methods

#### `init(viewModel:selectedNoteURL:onMapViewTap:onDoubleClick:onSourceChanged:onVaultChat:onSearchChanged:onDashboard:onSwitchVault:)`

Creates the sidebar view with all dependencies and callbacks.

### Body Structure

1. **Quick Access section** -- Dashboard (macOS), All Notes, Favorites, Recent, Vault Chat buttons.
2. **Tags section** -- Horizontal scrolling tag chip row (up to 12 tags) with `QuartzTagBadge`.
3. **Folders section** -- `OutlineGroup`-based file tree with:
   - Notes: selectable via `List(selection:)`, draggable, context menu (Open, Open in New Window, Favorite, Move, Delete), swipe actions (iOS).
   - Folders: draggable/droppable, context menu (New Note, New Folder, Move, Delete).
4. **Map View and Trash section** (macOS only) -- Links to knowledge graph and vault trash.
5. **Floating search bar** -- Capsule-shaped search field at the bottom.
6. **Indexing status bar** -- Progress indicator shown during embedding indexing.
7. **Alerts/Dialogs** -- New Note, New Folder, Delete Confirmation, Move to Folder sheet, Error alert.

---

## SidebarItemTransferable

**File:** `SidebarView.swift`

Transferable wrapper for sidebar drag-and-drop. Encodes/decodes a URL as plain text.

Conforms to: `Transferable`, `Sendable`

### Properties

- `url: URL` -- The file URL being transferred.

### Methods

#### `init(url: URL)`

Creates a transferable item for the given URL.

### Transfer Representation

Uses `DataRepresentation(contentType: .plainText)`. Exports the URL as a UTF-8 string; imports by parsing the string back to a URL.

---

# Workspace

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/Workspace/`

---

## WorkspaceView

**File:** `WorkspaceView.swift`

Three-pane workspace shell. Pure layout container using `NavigationSplitView`. All state flows through `WorkspaceStore`.

### Properties

- `store: WorkspaceStore` -- (Bindable) The workspace state store.
- `noteListStore: NoteListStore` -- The note list data source for the middle column.
- `sidebarViewModel: SidebarViewModel?` -- Optional sidebar view model.
- `editorSession: EditorSession?` -- Optional editor session for the detail column.
- `documentChatSession: DocumentChatSession?` -- Optional document chat session.
- `onMapViewTap: (() -> Void)?` -- Knowledge graph callback.
- `onDoubleClick: ((URL) -> Void)?` -- Double-click note callback (macOS new window).
- `onNewNote: (() -> Void)?` -- New note callback.
- `onVoiceNote: (() -> Void)?` -- Voice note callback.
- `onMeetingMinutes: (() -> Void)?` -- Meeting minutes callback.
- `onVaultChat: (() -> Void)?` -- Vault chat callback.
- `onDashboard: (() -> Void)?` -- Dashboard callback.
- `onSwitchVault: (() -> Void)?` -- Switch vault callback.

### Methods

#### `init(store:noteListStore:sidebarViewModel:editorSession:documentChatSession:onMapViewTap:onDoubleClick:onNewNote:onVoiceNote:onMeetingMinutes:onVaultChat:onDashboard:onSwitchVault:)`

Creates the workspace view with all dependencies and callbacks.

### Body Structure

Three-column `NavigationSplitView` (`.balanced` style):

1. **Sidebar column** -- `SidebarView` or empty state ("No Vault Open"). Width: 200-320pt (macOS), 180-300pt (iOS).
2. **Content column** -- `NoteListSidebar` driven by `NoteListStore`. Width: 220-400pt (macOS), 200-380pt (iOS).
3. **Detail column** -- Conditionally renders:
   - `DashboardView` when `store.showDashboard` is true.
   - `EditorContainerView` when a note is loaded in the session.
   - iCloud error view with retry button when the session has an error.
   - `QuartzEmptyState` ("No Note Selected") otherwise.

Responds to focus mode changes via `FocusModeManager` environment.

---

## WorkspaceStore

**File:** `WorkspaceStore.swift`

Owns the three-pane workspace state: source selection, note selection, column visibility, and focus mode bridge. Canonical source of truth for `NavigationSplitView` bindings.

Decorators: `@Observable`, `@MainActor`

### Properties

- `selectedSource: SourceSelection` -- Currently selected source in the left sidebar. Changing it resets `selectedNoteURL` to `nil`. Default: `.allNotes`.
- `selectedNoteURL: URL?` -- Currently selected note URL. Setting a non-nil value sets `showDashboard` to `false`.
- `showDashboard: Bool` -- Whether the detail pane shows the Dashboard instead of an editor. Default: `true`.
- `columnVisibility: NavigationSplitViewVisibility` -- Which columns are visible. Default: `.all`.
- `preferredCompactColumn: NavigationSplitViewColumn` -- Preferred column in compact (iPhone) width class. Default: `.sidebar`.

### Methods

#### `init()`

Creates a workspace store with default state (all columns visible, dashboard shown).

#### `applyFocusMode(_ isActive: Bool) -> Void`

Toggles focus mode. When activated, stashes the current `columnVisibility` and sets it to `.detailOnly`. When deactivated, restores the previous visibility.

**Parameters:**
- `isActive` -- Whether focus mode should be active.

---

## SourceSelection

**File:** `WorkspaceStore.swift`

Represents what the user has selected in the left sidebar. Each case maps to a distinct note-list filter in the middle column.

Conforms to: `Hashable`, `Sendable`

### Cases

| Case | Description |
|------|-------------|
| `.allNotes` | Show all notes in the vault. |
| `.favorites` | Show favorited notes only. |
| `.recent` | Show recently modified notes. |
| `.folder(URL)` | Show notes in a specific folder. |
| `.tag(String)` | Show notes with a specific tag. |

---

# Design System

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/DesignSystem/`

---

## QuartzColors

**File:** `LiquidGlass.swift`

Central color palette for Quartz, inspired by Apple Notes and Liquid Glass. All colors adapt between light and dark mode.

### Static Properties

- `accentGradient: LinearGradient` -- Primary brand gradient (yellow to orange).
- `warmGradient: LinearGradient` -- Warm gradient (golden to coral).
- `coolGradient: LinearGradient` -- Cool gradient (blue to purple).
- `sidebarBackground: Color` -- Platform-native sidebar background.
- `cardBackground: Color` -- Platform-native card background.
- `subtleText: Color` -- Platform-native tertiary label color.
- `accent: Color` -- Primary accent color (orange, adapts to dark mode).
- `folderYellow: Color` -- Folder icon color.
- `noteBlue: Color` -- Note icon color.
- `assetOrange: Color` -- Asset icon color.
- `canvasPurple: Color` -- Canvas icon color.
- `tagPalette: [Color]` -- Array of 8 tag colors for variety.

### Static Methods

#### `tagColor(for tag: String) -> Color`

Returns a deterministic color for a tag name using a djb2 hash into `tagPalette`.

**Parameters:**
- `tag` -- The tag string.

**Returns:** A consistent `Color` from the palette.

---

## Color.init(hex:alpha:)

**File:** `LiquidGlass.swift`

Extension on `Color` for hex initialization.

```swift
Color(hex: 0xF2994A, alpha: 1.0)
```

**Parameters:**
- `hex: UInt` -- RGB hex value (e.g., `0xFF3B30`).
- `alpha: Double` -- Opacity (default: 1.0).

---

## QuartzAmbientMeshStyle

**File:** `LiquidGlass.swift`

Preset intensity for `QuartzAmbientMeshBackground`.

Conforms to: `Sendable`

### Cases

| Case | Description |
|------|-------------|
| `.onboarding` | Rich intensity for onboarding hero. |
| `.shell` | Subtle depth behind the main `NavigationSplitView`. |
| `.editorChrome` | Very subtle depth for editor title/breadcrumb strip. |

---

## QuartzAmbientMeshBackground

**File:** `LiquidGlass.swift`

Reusable mesh-backed ambient depth view. Uses a calm linear gradient when Reduce Motion is on or on visionOS. On other platforms, renders a 3x3 `MeshGradient`.

### Properties

- `style: QuartzAmbientMeshStyle` -- The intensity preset.

### Methods

#### `init(style: QuartzAmbientMeshStyle)`

Creates the background with the given intensity style.

---

## QuartzLiquidGlassModifier

**File:** `LiquidGlass.swift`

ADA-quality glass effect using real iOS 18/macOS 15 materials. On visionOS, uses `.regularMaterial` + `glassBackgroundEffect()`. Respects Reduce Transparency.

### Properties

- `enabled: Bool` -- Whether the glass effect is applied.
- `cornerRadius: CGFloat` -- Corner radius of the glass shape (default: 20).

### Methods

#### `init(enabled:cornerRadius:)`

Creates the modifier.

---

## QuartzMaterialBackgroundModifier

**File:** `LiquidGlass.swift`

Production-ready material background using `.ultraThinMaterial`, `.thinMaterial`, or `.regularMaterial` depending on the layer and preference. Respects Reduce Transparency and adds shadow when specified.

### Properties

- `cornerRadius: CGFloat` -- Corner radius (default: 16).
- `shadowRadius: CGFloat` -- Shadow radius (default: 0, no shadow).
- `preferRegularMaterial: Bool` -- Use `.regularMaterial` even for sidebar layer (default: false).
- `layer: QuartzMaterialLayer` -- Material layer (`.sidebar` or `.floating`).

### Methods

#### `init(cornerRadius:shadowRadius:preferRegularMaterial:layer:)`

Creates the modifier with specified visual parameters.

---

## QuartzMaterialLayer

**File:** `LiquidGlass.swift`

Layered depth for Liquid Glass: floating elements get stronger blur and higher z-index.

Conforms to: `Sendable`

### Cases

| Case | Description |
|------|-------------|
| `.sidebar` | Standard sidebar depth (`.thinMaterial`). |
| `.floating` | Elevated floating chrome (`.regularMaterial`, z-index 10). |

---

## QuartzMaterialCircleModifier

**File:** `LiquidGlass.swift`

Circular material background for icon buttons (44x44pt HIG compliant). On visionOS, adds `glassBackgroundEffect()`.

### Methods

#### `init()`

Creates the modifier.

---

## GlassBackground

**File:** `LiquidGlass.swift`

Legacy glass background `ViewModifier`. Uses `.ultraThinMaterial` (or `.regularMaterial` on visionOS with `glassBackgroundEffect()`).

### Properties

- `cornerRadius: CGFloat` -- Corner radius.
- `opacity: Double` -- Material opacity.
- `shadowRadius: CGFloat` -- Shadow radius.

---

## GlassCard

**File:** `LiquidGlass.swift`

Glass card `ViewModifier` with `.regularMaterial` background, shadow, and a subtle gradient stroke border.

### Properties

- `cornerRadius: CGFloat` -- Corner radius.

---

## QuartzHIG

**File:** `LiquidGlass.swift`

Human Interface Guidelines constants.

### Static Properties

- `minTouchTarget: CGFloat` -- Minimum touch target size per Apple HIG: 44pt.

---

## QuartzTagBadge

**File:** `LiquidGlass.swift`

Tag badge component with deterministic color, selected/deselected states, and Dynamic Type support via `@ScaledMetric`.

### Properties

- `text: String` -- The tag name.
- `isSelected: Bool` -- Whether the tag is in selected state (default: false).
- `showHash: Bool` -- Whether to show the `#` prefix (default: true).

### Methods

#### `init(text:isSelected:showHash:)`

Creates a tag badge.

---

## QuartzSectionHeader

**File:** `LiquidGlass.swift`

Uppercase section header with optional SF Symbol icon.

### Properties

- `title: String` -- The section title text.
- `icon: String?` -- Optional SF Symbol name.

### Methods

#### `init(_ title:icon:)`

Creates a section header.

---

## QuartzButton

**File:** `LiquidGlass.swift`

Full-width accent-colored button with optional icon. Uses `QuartzPressButtonStyle` and triggers haptic feedback on tap.

### Properties

- `title: String` -- Button label text.
- `icon: String?` -- Optional SF Symbol name.
- `action: () -> Void` -- Closure invoked on tap.

### Methods

#### `init(_ title:icon:action:)`

Creates an accent button.

---

## QuartzPressButtonStyle

**File:** `LiquidGlass.swift`

`ButtonStyle` with scale-down (0.97), reduced opacity, and shadow shift on press. Respects Reduce Motion.

---

## QuartzCardButtonStyle

**File:** `LiquidGlass.swift`

`ButtonStyle` with subtle scale-down (0.98) and opacity reduction on press. Respects Reduce Motion.

---

## QuartzBounceButtonStyle

**File:** `LiquidGlass.swift`

`ButtonStyle` with pronounced scale-down (0.85) on press. Respects Reduce Motion.

---

## FloatingButtonStyle

**File:** `LiquidGlass.swift`

`ButtonStyle` for circular floating action buttons (52x52pt). Applies a gradient fill, shadow, and scale-down on press.

### Properties

- `color: Color` -- The button fill color.

---

## ShimmerModifier

**File:** `LiquidGlass.swift`

Animated shimmer overlay that sweeps a light gradient across content. Auto-disables after 30 seconds to reduce GPU usage. Respects Reduce Motion.

---

## ParallaxModifier

**File:** `LiquidGlass.swift`

Parallax scrolling effect based on vertical position in the global coordinate space. Respects Reduce Motion.

### Properties

- `strength: CGFloat` -- Parallax intensity (default: 40).

---

## SkeletonRow

**File:** `LiquidGlass.swift`

Placeholder loading row with randomized title/subtitle widths and a shimmer animation.

---

## QuartzEmptyState

**File:** `LiquidGlass.swift`

Empty state component with an SF Symbol icon, title, and subtitle. Combines children for accessibility.

### Properties

- `icon: String` -- SF Symbol name.
- `title: String` -- Primary text.
- `subtitle: String` -- Secondary descriptive text.

### Methods

#### `init(icon:title:subtitle:)`

Creates an empty state view.

---

## View Extensions (Design System)

**File:** `LiquidGlass.swift`

Convenience modifiers available on all `View` types:

| Method | Description |
|--------|-------------|
| `.quartzAmbientShellBackground()` | Ambient mesh/gradient behind content (or true black in Pure Dark Mode). |
| `.quartzAmbientGlassBackground(style:cornerRadius:)` | Mesh under material for chrome strips. |
| `.quartzFloatingUltraThinSurface(cornerRadius:)` | Ultra-thin material (regular material + glass on visionOS). |
| `.quartzLiquidGlass(enabled:cornerRadius:)` | Applies `QuartzLiquidGlassModifier`. |
| `.quartzMaterialBackground(cornerRadius:shadowRadius:preferRegularMaterial:layer:)` | Applies `QuartzMaterialBackgroundModifier`. |
| `.quartzMaterialCircle()` | Applies `QuartzMaterialCircleModifier`. |
| `.glassBackground(cornerRadius:opacity:shadowRadius:)` | Legacy glass background. |
| `.glassCard(cornerRadius:)` | Legacy glass card. |
| `.fadeIn(delay:)` | Fade-in appearance animation. |
| `.slideUp(delay:)` | Slide-up with fade appearance animation. |
| `.staggered(index:baseDelay:)` | Staggered appearance for lists. |
| `.scaleIn(delay:)` | Scale-in from 0.6 appearance animation. |
| `.shimmer()` | Shimmer overlay (auto-stops after 30s). |
| `.pulse()` | Pulsing scale/opacity animation. |
| `.bounceIn(delay:)` | Bounce-in from 0.3 scale appearance animation. |
| `.spinIn(delay:)` | Spin-in from -90 degrees appearance animation. |
| `.parallax(strength:)` | Parallax scrolling effect. |

All animation modifiers respect `accessibilityReduceMotion` (instant transition when enabled).

---

# Settings

Source directory: `QuartzKit/Sources/QuartzKit/Presentation/Settings/`

---

## AppearanceSettingsView

**File:** `AppearanceSettingsView.swift`

Settings view for visual appearance: theme picker, accent color swatches, editor font size slider with live preview, vibrant transparency toggle, pure dark mode toggle, and dashboard toggle (macOS).

### Methods

#### `init()`

Creates the appearance settings view.

### Body Structure

Grouped `Form` with sections:

1. **Theme** -- Inline picker with light/dark/system swatches.
2. **Accent Color** -- Row of 7 color circles (Blue, Red, Green, Orange, Purple, Pink, Gray) with checkmark selection.
3. **Editor** -- Font size slider (12-24pt) with live preview sentence.
4. **Visual Effects** -- Vibrant Transparency and Pure Dark Mode toggles.
5. **Dashboard** (macOS only) -- Show Dashboard toggle.

---

## EditorSettingsView

**File:** `EditorSettingsView.swift`

Settings view for editor configuration: focus mode, typewriter mode, autosave, spell check, and typography (font family, size, line spacing, text width) with live preview.

### Methods

#### `init()`

Creates the editor settings view.

### Body Structure

Grouped `Form` with sections:

1. **Writing** -- Focus Mode toggle and Typewriter Mode toggle with descriptions.
2. **Behavior** -- Autosave and Spell Check toggles (backed by `@AppStorage`).
3. **Typography** -- Font family picker, font size slider (12-24pt), line spacing slider (1.0-2.5x), text width slider (400-1200pt), and live typography preview paragraph.
