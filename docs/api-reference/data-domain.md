# Quartz Notes — Data & Domain Layer API Reference

> Auto-generated from source. Covers the file system, preview cache, backup, cloud sync, editor session, syntax highlighting, font factory, AI services, export pipeline, and command palette engine.

---

## Data Layer

---

## FileSystemVaultProvider

`public actor FileSystemVaultProvider: VaultProviding`

Primary file system interface for reading, writing, and organizing vault contents. Uses security-scoped URLs for sandbox compliance. All file I/O runs on a detached task with a 5-second timeout to prevent iCloud Drive hangs.

### Methods

#### `loadFileTree(at root: URL) async throws -> [FileNode]`
Recursively scans the vault directory and returns a hierarchical array of `FileNode` objects representing folders, notes (.md), assets, and canvases. Skips hidden files and the `.quartztrash` directory.

#### `readNote(at url: URL) async throws -> NoteDocument`
Reads a markdown file from disk, parses frontmatter via `FrontmatterParser`, and returns a `NoteDocument`. Uses `coordinatedRead` with 5-second timeout. Throws `FileSystemError.iCloudTimeout` if the file isn't downloaded.

#### `saveNote(_ note: NoteDocument) async throws`
Serializes frontmatter + body back to UTF-8 and writes to disk via coordinated write. Posts `.quartzNoteSaved` notification on success.

#### `createNote(named:in:) async throws -> NoteDocument`
Creates a new `.md` file with default frontmatter (title, created date). Returns the loaded document.

#### `createNote(named:in:initialContent:) async throws -> NoteDocument`
Same as above but with custom initial body content.

#### `deleteNote(at url: URL) async throws`
Moves the file to `.quartztrash/` (soft delete). Does not permanently remove.

#### `rename(at url: URL, to newName: String) async throws -> URL`
Renames a file or folder on disk. Returns the new URL.

#### `createFolder(named:in:) async throws -> URL`
Creates a new directory at the specified parent path.

### Error Types

#### `FileSystemError`
`public enum FileSystemError: LocalizedError, Sendable`

| Case | Description |
|------|-------------|
| `.encodingFailed(URL)` | File content couldn't be decoded as UTF-8 |
| `.fileAlreadyExists(URL)` | A file with that name already exists |
| `.fileNotFound(URL)` | File doesn't exist at the specified path |
| `.invalidName(String)` | Filename contains invalid characters |
| `.iCloudTimeout(URL)` | File read timed out after 5 seconds (iCloud not downloaded) |

---

## NotePreviewIndexer

`public actor NotePreviewIndexer`

Asynchronous indexer that builds the note preview cache by reading only the first 8KB of each file. Uses `TaskGroup` with bounded concurrency (16 parallel tasks) and fingerprint-based skip logic for unchanged files.

### Methods

#### `indexAll(from tree: [FileNode]) async`
Full reindex from a pre-loaded file tree. Processes all `.md` files in parallel, skipping unchanged ones (matching modification date + file size fingerprint). Persists cache after completion.

#### `indexFile(at url: URL) async`
Incrementally indexes a single file. Always re-extracts (no fingerprint skip). Called from `FileWatcher` events.

#### `removeFile(at url: URL) async`
Removes a file's preview from the cache. Called on deletion.

---

## NotePreviewRepository

`public actor NotePreviewRepository`

In-memory + disk-persisted cache of note previews (title, snippet, tags, dates). Stored as JSON in the vault's `.quartzindex/` directory.

### Nested Types

#### `CachedNotePreview`
`public struct CachedNotePreview: Codable, Sendable`

| Property | Type | Description |
|----------|------|-------------|
| `url` | `URL` | Absolute file URL |
| `title` | `String` | From frontmatter, first H1, or filename |
| `modifiedAt` | `Date` | File modification timestamp |
| `fileSize` | `Int64` | For fingerprint-based skip logic |
| `snippet` | `String` | 2-3 line plain text preview |
| `tags` | `[String]` | From frontmatter |

### Methods

#### `loadCache()`
Loads the JSON cache from disk into memory. Called once on vault open.

#### `saveCache()`
Persists the in-memory cache to disk as JSON.

#### `cachedPreview(for:modifiedAt:fileSize:) -> CachedNotePreview?`
Returns the cached preview if the fingerprint (date + size) matches. Returns nil if stale.

#### `store(_ preview: CachedNotePreview)`
Inserts or updates a preview in the cache.

#### `remove(for url: URL)`
Removes a preview by URL.

#### `allPreviews() -> [CachedNotePreview]`
Returns all cached entries. Used by the note list and dashboard stats.

### Properties

- `count: Int` — Number of cached entries.

---

## VaultBackupService

`public actor VaultBackupService`

Manages vault backup creation, auto-backup scheduling, and restore. Backups are ZIP archives stored in `~/Library/Application Support/QuartzNotes/Backups/`.

### Methods

#### `estimateBackupSize(vaultRoot:) throws -> BackupSizeEstimate`
Calculates total size and file count without creating the backup.

#### `createBackup(vaultRoot:destination:progress:) async throws -> URL`
Creates a ZIP backup of the entire vault. Reports progress via callback. Returns the archive URL.

#### `runAutoBackup(vaultRoot:retainCount:) async throws`
Creates a backup and prunes old ones, keeping the most recent `retainCount` (default 7).

#### `listBackups(vaultRoot:) -> [BackupEntry]`
Returns all available backups sorted by date (newest first).

#### `restoreBackup(from:to:progress:) async throws`
Extracts a backup archive to the specified destination.

---

## CloudSyncService

`public actor CloudSyncService`

Monitors iCloud Drive sync status for the vault directory. Resolves the ubiquity container URL on a background thread to avoid blocking the main thread.

### Static Properties

- `containerIdentifier: String` — `"iCloud.olli.QuartzNotes"`
- `isAvailable: Bool` — Whether iCloud is signed in and available.

### Methods

#### `resolveContainerURL() async -> URL?`
Resolves the iCloud container URL on a background thread. Returns nil if iCloud is unavailable.

#### `startMonitoring(vaultRoot:) -> AsyncStream<CloudSyncStatus>`
Returns an async stream of sync status updates for the vault directory.

---

## Domain Layer

---

## EditorSession

`@Observable @MainActor public final class EditorSession`

The authoritative text buffer for the markdown editor. The native text view (UITextView/NSTextView) is the source of truth — SwiftUI never writes text back. All mutations flow through `applyExternalEdit` or delegate callbacks.

### Key Properties

| Property | Type | Description |
|----------|------|-------------|
| `note` | `NoteDocument?` | Currently loaded note |
| `currentText` | `String` | Live text content |
| `cursorPosition` | `NSRange` | Current selection/cursor |
| `isDirty` | `Bool` | Unsaved changes exist |
| `isSaving` | `Bool` | Save in progress |
| `errorMessage` | `String?` | Error to display in UI |
| `wordCount` | `Int` | Live word count |
| `formattingState` | `FormattingState` | Bold/italic/heading state at cursor |
| `vaultRootURL` | `URL?` | Root of the active vault |
| `fileTree` | `[FileNode]` | For link suggestions |
| `externalModificationDetected` | `Bool` | File changed on disk |
| `inspectorStore` | `InspectorStore` | Headings, stats for inspector |
| `highlighter` | `MarkdownASTHighlighter?` | AST-based syntax highlighter |
| `canUndo` | `Bool` | Undo stack has entries |
| `canRedo` | `Bool` | Redo stack has entries |

### Note Lifecycle

#### `loadNote(at url: URL) async`
Loads a note from disk into the session. Sets text on the native view, clears undo stack, triggers `highlightImmediately()` (hidden until spans applied), starts file watching.

#### `closeNote()`
Clears the current note without destroying the session. The editor view stays mounted.

#### `reloadFromDisk() async`
Reloads from disk, discarding local edits. Used after external modification detected.

### Text Synchronization

#### `textDidChange(_ newText: String)`
Called by the text view delegate on every keystroke. Updates `currentText`, schedules autosave, word count, analysis, and debounced highlight.

#### `selectionDidChange(_ range: NSRange)`
Called when cursor/selection changes. Updates `cursorPosition` and `formattingState`.

### Editing

#### `applyFormatting(_ action: FormattingAction)`
Applies markdown formatting (bold, italic, heading, list, etc.) at the current selection.

#### `applyExternalEdit(replacement:range:cursorAfter:)`
Surgical text replacement via the native text storage. Used for list continuation, AI insertions, and programmatic edits.

#### `undo()` / `redo()`
Forwards to the native text view's undo manager.

### Persistence

#### `save(force:) async`
Saves the current text to disk. Skips if not dirty unless `force` is true. Posts `.quartzNoteSaved` notification.

#### `manualSave() async`
Force-saves regardless of dirty state. Triggered by Cmd+S.

### Highlighting

#### `scheduleHighlight()`
Debounced (80ms) AST parse + attribute application. Used during typing.

#### `highlightImmediately()`
Non-debounced highlight with hidden-until-ready pattern. Hides the text view (`alphaValue = 0`), parses, applies spans, then reveals (`alphaValue = 1`). Prevents flash of unstyled text on note load.

### Inspector & Navigation

#### `viewportDidScroll(topCharacterOffset:)`
Updates the inspector's active heading based on scroll position.

#### `scrollToHeading(_ heading: HeadingItem)`
Scrolls the editor to a specific heading offset. Used when tapping ToC items.

#### `cancelAllTasks()`
Cancels all in-flight async tasks (autosave, highlight, file watch, word count, analysis).

---

## MarkdownASTHighlighter

`public actor MarkdownASTHighlighter`

Background AST parser using `swift-markdown`. Converts markdown source into `HighlightSpan` arrays that describe per-range font, color, and style attributes. Debouncing and async parsing keep the main thread free for 120fps.

### Properties

- `baseFontSize: CGFloat` — Base body font size in points.
- `fontFamily: AppearanceManager.EditorFontFamily` — Current font family (.system, .serif, .monospaced, .rounded).
- `lineSpacing: CGFloat` — Line height multiplier.

### Methods

#### `updateSettings(fontFamily:lineSpacing:)`
Updates font family and line spacing from the main actor. Called via `Task { await ... }` from the representable.

#### `parse(_ markdown: String) async -> [HighlightSpan]`
Immediate (non-debounced) parse. Cancels any in-flight task. Skips documents > 500K characters.

#### `parseDebounced(_ markdown: String) async -> [HighlightSpan]`
Waits 80ms (160ms for large docs > 50K chars) before parsing. Used during typing.

### Nested Types

#### `HighlightSpan`
| Property | Type | Description |
|----------|------|-------------|
| `range` | `NSRange` | Character range in source |
| `font` | `PlatformFont` | Resolved font for this span |
| `color` | `PlatformColor?` | Foreground color override |
| `traits` | `FontTraits` | Bold/italic flags |
| `backgroundColor` | `PlatformColor?` | Background highlight |
| `strikethrough` | `Bool` | Strikethrough decoration |
| `isOverlay` | `Bool` | When true, only color is applied (for muting syntax delimiters) |

---

## EditorFontFactory

`public enum EditorFontFactory`

Cross-platform font factory that maps `EditorFontFamily` to concrete platform fonts (SF Pro, New York, SF Mono, SF Rounded).

### Static Methods

#### `makeFont(family:size:weight:italic:) -> PlatformFont`
Creates a font for the specified family, size, weight, and italic flag. Uses `UIFontDescriptor.withDesign()` / `NSFontDescriptor` for serif (.serif → New York) and rounded (.rounded → SF Rounded).

#### `makeCodeFont(size:weight:) -> PlatformFont`
Always returns a monospaced font (SF Mono / Menlo fallback). Used for inline code and code blocks.

---

## VaultChatService

`public actor VaultChatService`

Vault-wide Q&A service using RAG (Retrieval-Augmented Generation). Searches the vector embedding index for relevant chunks, builds a context prompt, and streams the response from the configured AI provider.

### Methods

#### `ask(_ question:chatHistory:noteResolver:) async throws -> VaultAnswer`
Synchronous (non-streaming) vault Q&A. Returns a complete answer with citations.

#### `streamAsk(question:chatHistory:noteResolver:) -> AsyncThrowingStream<StreamToken, Error>`
Streaming vault Q&A with SSE-style token delivery at 30fps. Each `StreamToken` is either `.text(String)` or `.done(citations: [Citation])`.

---

## VectorEmbeddingService

`public actor VectorEmbeddingService`

On-device vector embedding service using `NLEmbedding` (512-dimensional). Chunks note content, generates embeddings, and provides cosine similarity search. Persists the index as binary data in `.quartzindex/`.

### Properties

- `embeddingDimension: Int` — Always 512 (NLEmbedding sentence dimension).
- `entryCount: Int` — Total chunks in the index.
- `indexedNoteCount: Int` — Unique notes indexed.
- `indexedNoteIDs: Set<UUID>` — All indexed note IDs.

### Methods

#### `loadIndex() throws`
Loads the binary index from disk.

#### `saveIndex() throws`
Persists the index to disk.

#### `indexNote(noteID:content:) throws`
Chunks the note content (~500 chars per chunk with overlap), generates embeddings, and stores them.

#### `removeNote(_ noteID: UUID)`
Removes all chunks for a note from the index.

#### `search(query:limit:threshold:) -> [SearchResult]`
Cosine similarity search. Returns up to `limit` results above `threshold`.

#### `stableNoteID(for url: URL, vaultRoot: URL) -> UUID` *(static)*
Generates a deterministic UUID from the note's relative path. Stable across app launches.

---

## NoteExportService

`public struct NoteExportService: Sendable`

Export pipeline supporting four output formats. PDF uses CoreText `CTFramesetter` for native pagination (no WKWebView). HTML uses a custom `MarkupVisitor` AST walker.

### Methods

#### `exportToMarkdown(text:title:metadata:) -> Data`
Returns the raw markdown as UTF-8 data with optional frontmatter.

#### `exportToHTML(text:title:metadata:) -> Data`
Converts markdown to semantic HTML using `HTMLExportVisitor` with the `HTMLStylesheet` for styling.

#### `exportToRTF(text:title:metadata:) -> Data`
Converts markdown to attributed string via `RichAttributedStringBuilder`, then serializes as RTF.

#### `exportToPDF(text:title:metadata:) -> Data`
Renders paginated PDF using `CTFramesetter`. Handles multi-page documents with proper margins and page breaks.

---

## CommandPaletteEngine

`@Observable @MainActor public final class CommandPaletteEngine`

Fuzzy search engine for the Cmd+K command palette. Searches both vault notes (via `NotePreviewRepository`) and registered commands simultaneously.

### Properties

- `searchText: String` — Current search query. Triggers search on change.
- `results: [PaletteItem]` — Sorted results (notes + commands mixed by relevance).
- `selectedIndex: Int` — Currently highlighted result for keyboard navigation.

### Methods

#### `moveSelectionUp()` / `moveSelectionDown()`
Moves the keyboard selection cursor. Wraps around at boundaries.

#### `executeSelected() -> URL?`
Executes the currently selected item. Returns a URL if it was a note (for navigation), nil if it was a command (already executed via closure).

### Supporting Types

#### `PaletteCommand`
`public struct PaletteCommand: Identifiable, Sendable`
- `id: String`, `title: String`, `icon: String` (SF Symbol), `shortcutLabel: String?`, `keywords: [String]`, `action: @MainActor @Sendable () -> Void`

#### `NoteResult`
`public struct NoteResult: Sendable`
- `url: URL`, `title: String`, `folderPath: String`, `modifiedAt: Date`, `snippet: String?`, `matchScore: Int`

#### `PaletteItem`
`public enum PaletteItem: Identifiable` — `.note(NoteResult)` | `.command(PaletteCommand)`
