import SwiftUI
#if os(iOS)
import PhotosUI
#endif

/// SwiftUI host for the markdown editor.
///
/// Owns no text state — all editing flows through `EditorSession`.
/// Provides the formatting toolbar, status bar, inspector panel, and error overlays
/// around the native `MarkdownEditorRepresentable`.
public struct EditorContainerView: View {
    let session: EditorSession
    let workspaceStore: WorkspaceStore?
    var documentChatSession: DocumentChatSession?
    var onVoiceNote: (() -> Void)?
    /// URLs of notes with unresolved iCloud sync conflicts — used to show the conflict banner.
    var conflictedNoteURLs: Set<URL> = []
    var onResolveConflict: ((URL) -> Void)?
    /// Set when the current note is in the trash — enables restore/delete actions.
    var isInTrash: Bool = false
    var onRestoreFromTrash: (() -> Void)?
    var onPermanentlyDelete: (() -> Void)?
    var onNavigateToNoteRequest: ((WikiLinkNavigationRequest) -> Void)?
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// AI Writing Tools state — uses an Identifiable item for `.sheet(item:)` to guarantee
    /// the captured text is available when the sheet renders (prevents blank popover).
    @State private var aiToolsRequest: AIToolsRequest?
    @State private var showChat = false
    @State private var showImageSourceSheet = false
    #if os(macOS)
    @State private var isMacOverflowPalettePresented = false
    #endif
    #if os(iOS)
    @State private var selectedImageSource: ImageSourceOption?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var showDocumentScanner = false
    @State private var showFilePicker = false
    #endif

    struct AIToolsRequest: Identifiable {
        let id = UUID()
        let selectedText: String
        let selectionRange: NSRange
    }

    public init(
        session: EditorSession,
        workspaceStore: WorkspaceStore? = nil,
        documentChatSession: DocumentChatSession? = nil,
        onVoiceNote: (() -> Void)? = nil,
        conflictedNoteURLs: Set<URL> = [],
        onResolveConflict: ((URL) -> Void)? = nil,
        isInTrash: Bool = false,
        onRestoreFromTrash: (() -> Void)? = nil,
        onPermanentlyDelete: (() -> Void)? = nil,
        onNavigateToNoteRequest: ((WikiLinkNavigationRequest) -> Void)? = nil
    ) {
        self.session = session
        self.workspaceStore = workspaceStore
        self.documentChatSession = documentChatSession
        self.onVoiceNote = onVoiceNote
        self.conflictedNoteURLs = conflictedNoteURLs
        self.onResolveConflict = onResolveConflict
        self.isInTrash = isInTrash
        self.onRestoreFromTrash = onRestoreFromTrash
        self.onPermanentlyDelete = onPermanentlyDelete
        self.onNavigateToNoteRequest = onNavigateToNoteRequest
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let note = session.note {
                editorHeader(for: note)
            }

            if session.note != nil, session.inNoteSearch.isPresented {
                FindReplaceBar(session: session)
            }

            if session.note != nil, session.linkInsertion.isPresented {
                NoteLinkPicker(session: session)
            }

            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: appearance.editorFontScale,
                editorFontFamily: appearance.editorFontFamily,
                editorLineSpacing: appearance.editorLineSpacing,
                editorMaxWidth: appearance.editorMaxWidth,
                syntaxVisibilityMode: appearance.syntaxVisibilityMode
            )
            .accessibilityIdentifier("editor-text-view")
            .disabled(isInTrash) // Read-only when viewing a trashed note

            editorStatusBar
        }
        .overlay(alignment: .top) {
            if isInTrash {
                trashBanner
            } else if isCurrentNoteConflicted {
                SyncConflictBanner(
                    onKeepMine: {
                        if let url = session.note?.fileURL {
                            onResolveConflict?(url)
                        }
                    },
                    onKeepTheirs: {
                        if let url = session.note?.fileURL {
                            onResolveConflict?(url)
                        }
                    },
                    onViewDiff: {
                        if let url = session.note?.fileURL {
                            onResolveConflict?(url)
                        }
                    }
                )
                .animation(QuartzAnimation.status, value: isCurrentNoteConflicted)
            } else if session.externalModificationDetected {
                externalModificationBanner
            }
        }
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            if isMacOverflowPalettePresented {
                macOverflowPalette
                    .padding(.top, 12)
                    .padding(.trailing, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        #endif
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 72)
        }
        .overlay(alignment: .bottom) {
            IosEditorToolbar(
                onFormatting: { action in
                    session.handleFormattingAction(action, source: .toolbar)
                },
                onSave: { Task { await session.manualSave() } },
                formattingState: session.formattingState,
                isComposing: session.isComposing,
                hasSelection: session.cursorPosition.length > 0,
                onAIAssist: { triggerAIAssist() },
                onInsertImage: { showImageSourceSheet = true }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        #endif
        .toolbar {
            #if os(macOS)
            MacEditorToolbarContent(
                onFormatting: { action in
                    session.handleFormattingAction(action, source: .toolbar)
                },
                formattingState: session.formattingState,
                isComposing: session.isComposing,
                onUndo: { session.undo() },
                onRedo: { session.redo() },
                onOverflowToggle: { isMacOverflowPalettePresented.toggle() },
                isOverflowPresented: isMacOverflowPalettePresented
            )
            #endif

            ToolbarItemGroup(placement: .primaryAction) {
                Group {
                    if let onVoiceNote {
                        Button {
                            QuartzFeedback.primaryAction()
                            onVoiceNote()
                        } label: {
                            Image(systemName: "mic")
                        }
                        .accessibilityIdentifier("editor-toolbar-voice-note")
                        .accessibilityLabel(String(localized: "Record Voice Note", bundle: .module))
                    }

                    if session.note != nil {
                        ShareMenuView(
                            markdownText: session.currentText,
                            noteTitle: session.note?.displayName ?? "Note"
                        )

                        Button {
                            session.presentInNoteSearch()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityIdentifier("editor-find-button")
                        .accessibilityLabel(String(localized: "Find in Note", bundle: .module))
                    }

                    Button {
                        focusMode.isFocusModeActive.toggle()
                    } label: {
                        Image(systemName: focusMode.isFocusModeActive
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityIdentifier("editor-toolbar-focus-mode")
                    .accessibilityLabel(
                        focusMode.isFocusModeActive
                            ? String(localized: "Exit Focus Mode", bundle: .module)
                            : String(localized: "Enter Focus Mode", bundle: .module)
                    )

                    if documentChatSession != nil {
                        Button {
                            QuartzFeedback.primaryAction()
                            showChat = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityIdentifier("editor-toolbar-chat")
                        .accessibilityLabel(String(localized: "Chat about this note", bundle: .module))
                    }

                    Button {
                        QuartzFeedback.primaryAction()
                        triggerAIAssist()
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .disabled(session.isComposing || session.cursorPosition.length == 0)
                    .accessibilityIdentifier("editor-toolbar-ai-assistant")
                    .accessibilityLabel(String(localized: "AI Assistant", bundle: .module))

                    Button {
                        withAnimation(QuartzAnimation.content) {
                            session.inspectorStore.isVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityIdentifier("editor-toolbar-inspector")
                    .accessibilityLabel(
                        session.inspectorStore.isVisible
                            ? String(localized: "Hide Inspector", bundle: .module)
                            : String(localized: "Show Inspector", bundle: .module)
                    )
                }
                .tint(.primary)
            }
        }
        #if os(macOS)
        .inspector(isPresented: Binding(
            get: { session.inspectorStore.isVisible },
            set: { session.inspectorStore.isVisible = $0 }
        )) {
            inspectorContent
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        #elseif os(iOS)
        .modifier(IOSInspectorModifier(
            session: session,
            isCompact: horizontalSizeClass == .compact,
            content: { inspectorContent }
        ))
        #endif
        .sheet(item: $aiToolsRequest) { request in
            AIWritingToolsView(
                selectedText: request.selectedText,
                embeddingService: nil,
                currentNoteURL: session.note?.fileURL,
                vaultRootURL: session.vaultRootURL
            ) { processedText in
                let range = request.selectionRange
                Task { @MainActor in
                    session.applyExternalEdit(
                        replacement: processedText,
                        range: range,
                        cursorAfter: NSRange(
                            location: range.location + (processedText as NSString).length,
                            length: 0
                        ),
                        origin: .aiInsert
                    )
                }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #else
            .frame(minWidth: 400, minHeight: 350)
            #endif
        }
        .sheet(isPresented: $showChat) {
            if let chatSession = documentChatSession {
                DocumentChatView(session: chatSession)
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
        .sheet(isPresented: Binding(
            get: { session.inspectorStore.showVersionHistory },
            set: { session.inspectorStore.showVersionHistory = $0 }
        )) {
            if let noteURL = session.note?.fileURL, let vaultRoot = session.vaultRootURL {
                VersionHistoryView(
                    noteURL: noteURL,
                    noteTitle: session.note?.displayName ?? "Note",
                    vaultRoot: vaultRoot
                ) {
                    // Use version-restore-aware reload to prevent file watcher spurious warnings
                    Task { await session.reloadAfterVersionRestore() }
                }
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
        // Dismiss competing sheets when version history opens (iOS only supports one sheet at a time)
        .onChange(of: session.inspectorStore.showVersionHistory) { _, showVersion in
            if showVersion {
                showChat = false
                aiToolsRequest = nil
                #if os(iOS)
                showImageSourceSheet = false
                #endif
            }
        }
        #if os(iOS)
        // Image source picker sheet
        .sheet(isPresented: $showImageSourceSheet) {
            ImageSourceSheet(
                isPresented: $showImageSourceSheet,
                selectedSource: $selectedImageSource,
                selectedPhotoItem: $selectedPhotoItem
            ) {
                handleImageSourceSelected()
            }
            .presentationDetents([.medium])
        }
        .onChange(of: selectedImageSource) { _, source in
            guard let source else { return }
            selectedImageSource = nil
            switch source {
            case .files:
                showFilePicker = true
            case .camera:
                showCameraPicker = true
            case .scan:
                showDocumentScanner = true
            case .photoLibrary:
                break // handled by selectedPhotoItem
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await handlePhotoLibrarySelection(item) }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraImagePicker(isPresented: $showCameraPicker) { image in
                Task { await importCameraImage(image) }
            }
        }
        .fullScreenCover(isPresented: $showDocumentScanner) {
            DocumentScannerView(isPresented: $showDocumentScanner) { images in
                Task { await handleScannedImages(images) }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                Task { await importImageFromURL(url) }
            }
        }
        #endif
        // Cmd+S keyboard shortcut for manual save
        .background {
            Button("") {
                Task { await session.manualSave() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
        }
    }

    // MARK: - AI Assist Trigger

    /// Captures the current selection and presents the AI tools sheet.
    private func triggerAIAssist() {
        let range = session.cursorPosition
        guard range.length > 0 else { return }

        let nsText = session.currentText as NSString
        guard range.location + range.length <= nsText.length else { return }

        let selectedText = nsText.substring(with: range)
        guard !selectedText.isEmpty else { return }

        aiToolsRequest = AIToolsRequest(selectedText: selectedText, selectionRange: range)
    }

    // MARK: - Image Capture Handlers (iOS)

    #if os(iOS)
    private func handleImageSourceSelected() {
        // Sheet dismisses itself; onChange(of: selectedImageSource) opens the appropriate picker.
    }

    private func handlePhotoLibrarySelection(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let ext = detectImageExtension(data)
            let tempURL = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).\(ext)")
            try data.write(to: tempURL)
            await importImageFromURL(tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func importCameraImage(_ image: UIImage) async {
        guard let vaultRoot = session.vaultRootURL,
              let noteURL = session.note?.fileURL else {
            session.errorMessage = String(localized: "No active note or vault.", bundle: .module)
            return
        }
        let assetManager = AssetManager()
        do {
            let markdownLink = try await assetManager.importImage(
                image,
                vaultRoot: vaultRoot,
                noteURL: noteURL
            )
            insertMarkdownAtCursor("\n" + markdownLink + "\n")
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func importImageFromURL(_ url: URL) async {
        guard let vaultRoot = session.vaultRootURL,
              let noteURL = session.note?.fileURL else {
            session.errorMessage = String(localized: "No active note or vault.", bundle: .module)
            return
        }
        let assetManager = AssetManager()
        do {
            let markdownLink = try await assetManager.importImage(
                from: url,
                vaultRoot: vaultRoot,
                noteURL: noteURL
            )
            insertMarkdownAtCursor("\n" + markdownLink + "\n")
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    /// Handles scanned document images: imports each as an asset and runs OCR to extract text.
    private func handleScannedImages(_ images: [UIImage]) async {
        guard !images.isEmpty,
              let vaultRoot = session.vaultRootURL,
              let noteURL = session.note?.fileURL else { return }

        let assetManager = AssetManager()
        #if canImport(Vision)
        let ocrService = HandwritingOCRService()
        #endif

        for image in images {
            // 1. Import the scanned image as an asset
            do {
                let markdownLink = try await assetManager.importImage(
                    image,
                    vaultRoot: vaultRoot,
                    noteURL: noteURL
                )
                insertMarkdownAtCursor("\n" + markdownLink + "\n")
            } catch {
                session.errorMessage = error.localizedDescription
                continue
            }

            // 2. Run OCR on the scanned page and append extracted text
            #if canImport(Vision)
            if let cgImage = image.cgImage {
                do {
                    let result = try await ocrService.recognizeText(in: cgImage)
                    if !result.fullText.isEmpty {
                        let ocrBlock = "\n> **Extracted Text:**\n> \(result.fullText.replacingOccurrences(of: "\n", with: "\n> "))\n"
                        insertMarkdownAtCursor(ocrBlock)
                    }
                } catch {
                    // OCR failure is non-fatal — the image is already imported
                }
            }
            #endif
        }
    }

    /// Inserts markdown text at the current cursor position via EditorSession.
    private func insertMarkdownAtCursor(_ text: String) {
        let cursorPos = session.cursorPosition.location
        let nsContent = session.currentText as NSString
        let insertLocation = min(cursorPos, nsContent.length)
        session.applyExternalEdit(
            replacement: text,
            range: NSRange(location: insertLocation, length: 0),
            cursorAfter: NSRange(location: insertLocation + (text as NSString).length, length: 0),
            origin: .pasteOrDrop
        )
    }

    /// Detects image format from data header bytes.
    private func detectImageExtension(_ data: Data) -> String {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        let jpgHeader = Data([0xFF, 0xD8])
        if data.prefix(4) == pngHeader { return "png" }
        if data.prefix(2) == jpgHeader { return "jpg" }
        return "png"
    }
    #endif

    // MARK: - Editor Header

    private func editorHeader(for note: NoteDocument) -> some View {
        HStack {
            Text(note.displayName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if session.isDirty {
                Circle()
                    .fill(appearance.accentColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(String(localized: "Unsaved changes", bundle: .module))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Status Bar

    private var editorStatusBar: some View {
        HStack(spacing: 8) {
            Text("\(session.inspectorStore.stats.wordCount) \(session.inspectorStore.stats.wordCount == 1 ? "word" : "words")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.quaternary)

            Text("~\(session.inspectorStore.stats.readingTimeMinutes) min")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if session.isSaving {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: - Conflict Detection

    private var isCurrentNoteConflicted: Bool {
        guard let url = session.note?.fileURL else { return false }
        return conflictedNoteURLs.contains(url)
    }

    // MARK: - Trash Banner

    private var trashBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text(String(localized: "This note is in Recently Deleted.", bundle: .module))
                .font(.callout)
            Spacer()
            Button(String(localized: "Restore", bundle: .module)) {
                QuartzFeedback.success()
                onRestoreFromTrash?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(String(localized: "Delete Permanently", bundle: .module), role: .destructive) {
                QuartzFeedback.destructive()
                onPermanentlyDelete?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 12, shadowRadius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "This note is in Recently Deleted", bundle: .module))
    }

    // MARK: - External Modification Banner

    private var externalModificationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
            Text(String(localized: "This note was modified externally.", bundle: .module))
                .font(.callout)
            Spacer()
            Button(String(localized: "Reload", bundle: .module)) {
                Task { await session.reloadFromDisk() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(String(localized: "Keep Editing", bundle: .module)) {
                session.externalModificationDetected = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 12, shadowRadius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(QuartzAnimation.status, value: session.externalModificationDetected)
    }

    // MARK: - Inspector Content (shared between macOS inspector and iOS sheet)

    private var inspectorContent: some View {
        InspectorSidebar(
            store: session.inspectorStore,
            note: session.note,
            vaultRootURL: session.vaultRootURL,
            graphEdgeStore: session.graphEdgeStore,
            onScrollToHeading: { heading in
                session.scrollToHeading(heading)
            },
            onUpdateTags: { newTags in
                session.updateTags(newTags)
            },
            onNavigateToNote: { url in
                navigateToInspectorNote(
                    WikiLinkNavigationRequest(
                        title: url.deletingPathExtension().lastPathComponent,
                        url: url
                    )
                )
            },
            onNavigateToBacklink: { backlink in
                navigateToInspectorNote(
                    WikiLinkNavigationRequest(
                        title: backlink.sourceNoteName,
                        url: backlink.sourceNoteURL,
                        selectionRange: backlink.referenceRange
                    )
                )
            },
            onLinkSuggestedMention: { suggestion in
                session.linkSuggestedMention(suggestion)
            }
        )
    }

    #if os(macOS)
    private var macOverflowPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(macOverflowPaletteActions, id: \.self) { action in
                Button {
                    session.handleFormattingAction(action, source: .toolbar)
                    isMacOverflowPalettePresented = false
                } label: {
                    Label(action.label, systemImage: action.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(session.isComposing)
                .accessibilityIdentifier("editor-toolbar-\(action.rawValue)")
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.clear)
                )
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
        .accessibilityIdentifier("editor-toolbar-overflow-panel")
    }

    private var macOverflowPaletteActions: [FormattingAction] {
        [.codeBlock, .blockquote, .table, .image, .math, .mermaid]
    }
    #endif

    private func navigateToInspectorNote(_ request: WikiLinkNavigationRequest) {
        QuartzFeedback.primaryAction()

        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: request.url)
        if CanonicalNoteIdentity.canonicalFileURL(for: session.note?.fileURL ?? canonicalURL) == canonicalURL {
            if let selectionRange = request.selectionRange {
                session.revealNavigationRange(selectionRange)
            }
            return
        }

        session.prepareNoteNavigation(request)

        if let workspaceStore {
            workspaceStore.selectedNoteURL = canonicalURL
            return
        }

        if let onNavigateToNoteRequest {
            onNavigateToNoteRequest(request)
            return
        }

        NotificationCenter.default.post(
            name: .quartzWikiLinkNavigation,
            object: nil,
            userInfo: request.notificationUserInfo
        )
    }
}

// MARK: - iOS Inspector Modifier

/// On iPhone (compact), presents the inspector as a bottom sheet with detents.
/// On iPad (regular), uses the native `.inspector` side panel.
/// This prevents layout issues from `.inspector` on compact widths.
#if os(iOS)
private struct IOSInspectorModifier<InspectorContent: View>: ViewModifier {
    let session: EditorSession
    let isCompact: Bool
    @ViewBuilder let content: () -> InspectorContent

    func body(content mainContent: Content) -> some View {
        if isCompact {
            // iPhone: bottom sheet with drag indicator
            mainContent
                .sheet(isPresented: Binding(
                    get: { session.inspectorStore.isVisible },
                    set: { session.inspectorStore.isVisible = $0 }
                )) {
                    NavigationStack {
                        content()
                            .navigationTitle(String(localized: "Inspector", bundle: .module))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(String(localized: "Done", bundle: .module)) {
                                        session.inspectorStore.isVisible = false
                                    }
                                    .fontWeight(.semibold)
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
        } else {
            // iPad: native inspector side panel
            mainContent
                .inspector(isPresented: Binding(
                    get: { session.inspectorStore.isVisible },
                    set: { session.inspectorStore.isVisible = $0 }
                )) {
                    content()
                        .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
                }
        }
    }
}
#endif
