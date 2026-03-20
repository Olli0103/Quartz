import SwiftUI
import UniformTypeIdentifiers
import CoreText
#if os(iOS)
import PhotosUI
#endif

/// Editor UI sizes – larger on macOS for better legibility.
private var editorBreadcrumbChevronSize: CGFloat {
    #if os(macOS)
    12
    #else
    10
    #endif
}

private var editorMetadataIconSize: CGFloat {
    #if os(macOS)
    14
    #else
    12
    #endif
}

private var editorStatusBarIconSize: CGFloat {
    #if os(macOS)
    12
    #else
    10
    #endif
}

private var editorStatusBarFontSize: CGFloat {
    #if os(macOS)
    12
    #else
    11
    #endif
}

private var editorTagBarIconSize: CGFloat {
    #if os(macOS)
    12
    #else
    11
    #endif
}

private var editorTagBarFontSize: CGFloat {
    #if os(macOS)
    12
    #else
    11
    #endif
}

private var editorTagRemoveIconSize: CGFloat {
    #if os(macOS)
    9
    #else
    8
    #endif
}

private var editorBacklinkFont: Font {
    #if os(macOS)
    .subheadline
    #else
    .caption
    #endif
}

private var editorMetadataFont: Font {
    #if os(macOS)
    .callout
    #else
    .subheadline
    #endif
}

/// Markdown editor with liquid glass header, formatting toolbar, AI tools, and status bar.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel
    var embeddingService: VectorEmbeddingService?
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @State private var showFocusModeHint = false
    @State private var showAITools = false
    @State private var showChat = false
    @State private var showBacklinks = false
    @State private var showFrontmatter = false
    @State private var showLinkSuggestions = false
    @State private var showAudioRecording = false
    @State private var showKnowledgeGraph = false
    @State private var showImagePicker = false
    #if os(iOS)
    @State private var showImageSourceSheet = false
    @State private var selectedImageSource: ImageSourceOption?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var showDocumentScanner = false
    #endif
    @State private var backlinks: [Backlink] = []
    @State private var linkSuggestions: [LinkSuggestionService.Suggestion] = []
    @State private var editableTitle: String = ""
    @State private var isFavorite: Bool = false
    @State private var newTagText: String = ""
    @State private var pdfDocument: PDFFileDocument?
    @State private var showPDFExporter = false
    @State private var pdfExportFilename = "note.pdf"
    #if os(macOS)
    @State private var plainTextExportDocument: TextExportDocument?
    @State private var showPlainTextExporter = false
    @State private var plainTextExportFilename = "note.txt"
    @State private var markdownExportDocument: TextExportDocument?
    @State private var showMarkdownExporter = false
    @State private var markdownExportFilename = "note.md"
    #endif
    @State private var showSavedOverlay = false
    @State private var isPreviewMode = false
    @State private var showCommandPalette = false
    @State private var showExternalModificationSheet = false
    @State private var diskBodyForMerge = ""
    private let formatter = MarkdownFormatter()
    private static let favoritesKey = "quartz.favoriteNotes"

    /// Optional callbacks for global toolbar actions (Search Brain, New Note, Refresh).
    /// When provided, these appear after AI and Focus Mode, before Save and Share.
    var onSearch: (() -> Void)? = nil
    var onNewNote: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    var searchDisabled: Bool = false
    var newNoteDisabled: Bool = false
    var refreshDisabled: Bool = false

    public init(
        viewModel: NoteEditorViewModel,
        embeddingService: VectorEmbeddingService? = nil,
        onSearch: (() -> Void)? = nil,
        onNewNote: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        searchDisabled: Bool = false,
        newNoteDisabled: Bool = false,
        refreshDisabled: Bool = false
    ) {
        self.viewModel = viewModel
        self.embeddingService = embeddingService
        self.onSearch = onSearch
        self.onNewNote = onNewNote
        self.onRefresh = onRefresh
        self.searchDisabled = searchDisabled
        self.newNoteDisabled = newNoteDisabled
        self.refreshDisabled = refreshDisabled
    }

    @ViewBuilder
    private var mainEditorView: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            editorContent
            if let note = viewModel.note, !focusMode.isFocusModeActive {
                NoteMetadataPanelView(
                    note: note,
                    content: viewModel.content,
                    vaultRootURL: viewModel.vaultRootURL,
                    onUpdateFrontmatter: { viewModel.updateFrontmatter($0) },
                    onExportFormat: { prepareAndShowExport(format: $0) }
                )
            }
        }
        #else
        editorContent
        #endif
    }

    public var body: some View {
        editorWithOverlays
    }

    private var editorWithToolbars: some View {
        mainEditorView
        .onChange(of: viewModel.manualSaveCompleted) { _, _ in
            QuartzFeedback.success()
            withAnimation(.easeInOut(duration: 0.2)) { showSavedOverlay = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) { showSavedOverlay = false }
                }
            }
        }
        .navigationTitle(viewModel.note?.displayName ?? String(localized: "Note", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup(placement: .principal) {
                MacEditorToolbar(
                    isPreviewMode: isPreviewMode,
                    onPreviewToggle: {
                        QuartzFeedback.toggle()
                        withAnimation(.bouncy) { isPreviewMode.toggle() }
                    },
                    onFormatting: applyFormatting,
                    onImagePick: { showImagePicker = true }
                )
                .hidesInFocusMode()
            }
            #endif
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(String(localized: "EDITING", bundle: .module))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuartzColors.accent)
                        .textCase(.uppercase)
                    Text(viewModel.note?.displayName ?? String(localized: "Note", bundle: .module))
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                }
            }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .background {
            Button("") { showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
        .keyboardShortcut(for: .bold) { applyFormatting(.bold) }
        .keyboardShortcut(for: .italic) { applyFormatting(.italic) }
        .keyboardShortcut(for: .strikethrough) { applyFormatting(.strikethrough) }
        .keyboardShortcut(for: .heading) { applyFormatting(.heading) }
        .keyboardShortcut(for: .code) { applyFormatting(.code) }
        .keyboardShortcut(for: .link) { applyFormatting(.link) }
        .keyboardShortcut(for: .blockquote) { applyFormatting(.blockquote) }
        .onTapGesture(count: 3) {
            if focusMode.isFocusModeActive { focusMode.toggleFocusMode() }
        }
        .accessibilityAction(named: String(localized: "Exit focus mode", bundle: .module)) {
            if focusMode.isFocusModeActive { focusMode.toggleFocusMode() }
        }
    }

    private var editorWithOverlays: some View {
        editorWithToolbars
        #if os(iOS)
        .overlay(alignment: .bottom) {
            if !isPreviewMode {
                IosEditorToolbar(
                    isPreviewMode: isPreviewMode,
                    onPreviewToggle: {
                        QuartzFeedback.toggle()
                        withAnimation(.bouncy) { isPreviewMode.toggle() }
                    },
                    onFormatting: applyFormatting,
                    onImagePick: { showImageSourceSheet = true },
                    onSave: {
                        QuartzFeedback.primaryAction()
                        Task { await viewModel.manualSave() }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .hidesInFocusMode()
            }
        }
        #endif
        .overlay(alignment: .bottom) {
            if showFocusModeHint {
                Text(String(localized: "Triple-tap to exit focus mode", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .quartzMaterialBackground(cornerRadius: 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if showSavedOverlay {
                Label(String(localized: "Saved", bundle: .module), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .onChange(of: focusMode.isFocusModeActive) { _, isActive in
            if isActive {
                withAnimation(QuartzAnimation.standard) { showFocusModeHint = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(QuartzAnimation.standard) { showFocusModeHint = false }
                }
            } else {
                showFocusModeHint = false
            }
        }
        .sheet(isPresented: $showAITools) {
            let text = selectedOrFullText
            AIWritingToolsView(
                selectedText: text,
                embeddingService: embeddingService,
                currentNoteURL: viewModel.note?.fileURL,
                vaultRootURL: viewModel.vaultRootURL
            ) { [viewModel] processedText in
                Task { @MainActor in
                    let pos = viewModel.cursorPosition
                    if pos.length > 0 {
                        let nsText = viewModel.content as NSString
                        viewModel.content = nsText.replacingCharacters(in: pos, with: processedText)
                        viewModel.cursorPosition = NSRange(location: pos.location, length: processedText.count)
                    } else {
                        viewModel.content = processedText
                    }
                }
            }
        }
        .sheet(isPresented: $showChat) {
        NoteChatView(
            noteContent: viewModel.content,
            noteTitle: viewModel.note?.displayName ?? String(localized: "Note", bundle: .module)
        )
        }
        .sheet(isPresented: $showLinkSuggestions) {
            linkSuggestionSheet
        }
        .sheet(isPresented: $showAudioRecording) {
            AudioRecordingView(vaultURL: viewModel.vaultRootURL) { [viewModel] transcribedText in
                Task { @MainActor in
                    let insertion = "\n\n" + transcribedText
                    let pos = viewModel.cursorPosition
                    if pos.location < viewModel.content.count {
                        let nsContent = viewModel.content as NSString
                        viewModel.content = nsContent.replacingCharacters(
                            in: NSRange(location: pos.location + pos.length, length: 0),
                            with: insertion
                        )
                    } else {
                        viewModel.content += insertion
                    }
                }
            }
        }
        .sheet(isPresented: $showKnowledgeGraph) {
            NavigationStack {
                KnowledgeGraphView(
                    fileTree: viewModel.fileTree,
                    currentNoteURL: viewModel.note?.fileURL,
                    vaultRootURL: viewModel.vaultRootURL,
                    vaultProvider: FileSystemVaultProvider(frontmatterParser: FrontmatterParser()),
                    embeddingService: embeddingService,
                    onSelectNote: { [viewModel] url in
                        showKnowledgeGraph = false
                        Task { @MainActor in
                            await viewModel.loadNote(at: url)
                        }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Done", bundle: .module)) {
                            showKnowledgeGraph = false
                        }
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImagePickerResult(result)
        }
        #if os(iOS)
        .sheet(isPresented: $showImageSourceSheet) {
            ImageSourceSheet(
                isPresented: $showImageSourceSheet,
                selectedSource: $selectedImageSource,
                selectedPhotoItem: $selectedPhotoItem
            ) {
                handleImageSourceSelected()
            }
        }
        .onChange(of: selectedImageSource) { _, source in
            guard let source else { return }
            switch source {
            case .files:
                showImagePicker = true
            case .camera:
                showCameraPicker = true
            case .scan:
                showDocumentScanner = true
            case .photoLibrary:
                break // handled by selectedPhotoItem
            }
            selectedImageSource = nil
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraImagePicker(isPresented: $showCameraPicker) { image in
                Task { await viewModel.importImage(image) }
            }
        }
        .fullScreenCover(isPresented: $showDocumentScanner) {
            DocumentScannerView(isPresented: $showDocumentScanner) { images in
                Task { await handleScannedImages(images) }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await handlePhotoLibrarySelection(item)
            }
        }
        #endif
        .fileExporter(
            isPresented: $showPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: pdfExportFilename
        ) { _ in
            pdfDocument = nil
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $showPlainTextExporter,
            document: plainTextExportDocument,
            contentType: .plainText,
            defaultFilename: plainTextExportFilename
        ) { _ in
            plainTextExportDocument = nil
        }
        .fileExporter(
            isPresented: $showMarkdownExporter,
            document: markdownExportDocument,
            contentType: UTType(filenameExtension: "md") ?? .plainText,
            defaultFilename: markdownExportFilename
        ) { _ in
            markdownExportDocument = nil
        }
        #endif
        .task(id: viewModel.note?.fileURL) {
            await loadBacklinks()
        }
        .onChange(of: viewModel.note?.fileURL) { _, _ in
            isPreviewMode = false
        }
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    fileTree: viewModel.fileTree,
                    vaultRootURL: viewModel.vaultRootURL,
                    onSelectNote: { [viewModel] url in
                        Task { @MainActor in
                            await viewModel.loadNote(at: url)
                        }
                    },
                    onNewNote: onNewNote,
                    onSearch: onSearch
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(100)
            }
        }
        .animation(QuartzAnimation.content, value: showCommandPalette)
        .sheet(isPresented: $showExternalModificationSheet) {
            ExternalModificationMergeView(
                localText: viewModel.content,
                diskText: diskBodyForMerge,
                onMerge: { merged in
                    Task { await viewModel.applyMergedContentResolvingExternalEdit(merged) }
                },
                onReloadDisk: {
                    Task { await viewModel.reloadFromDisk() }
                },
                onDismissKeepEditing: {
                    viewModel.dismissExternalModificationWarning()
                }
            )
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 480)
            #endif
        }
        .onChange(of: viewModel.externalModificationDetected) { _, detected in
            if detected {
                Task {
                    let disk = await viewModel.diskBodySnapshot() ?? ""
                    await MainActor.run {
                        diskBodyForMerge = disk
                        showExternalModificationSheet = true
                    }
                }
            }
        }
        .onChange(of: viewModel.requestDocumentScannerPresentation) { _, shouldShow in
            #if os(iOS)
            if shouldShow, viewModel.note != nil {
                showDocumentScanner = true
                viewModel.requestDocumentScannerPresentation = false
            }
            #endif
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            editorHeader
                .hidesInFocusMode()

            if showFrontmatter, viewModel.note != nil {
                FrontmatterEditorView(
                    frontmatter: Binding(
                        get: { viewModel.note?.frontmatter ?? Frontmatter() },
                        set: { viewModel.updateFrontmatter($0) }
                    )
                )
                .hidesInFocusMode()
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isPreviewMode {
                MarkdownPreviewView(
                    markdown: viewModel.content,
                    baseURL: viewModel.note.map { $0.fileURL.deletingLastPathComponent() },
                    fontScale: appearance.editorFontScale
                )
            } else {
                MarkdownTextViewRepresentable(
                    text: $viewModel.content,
                    cursorPosition: $viewModel.cursorPosition,
                    editorFontScale: appearance.editorFontScale,
                    noteURL: viewModel.note?.fileURL
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.image], isTargeted: nil) { providers in
                    handleImageDrop(providers)
                }
            }

            if showBacklinks && !backlinks.isEmpty {
                backlinkBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            #if os(iOS)
            if viewModel.note != nil {
                tagBar
                    .hidesInFocusMode()
            }
            #endif

            statusBar
                .hidesInFocusMode()
        }
    }

    #if os(macOS)
    private func prepareAndShowExport(format: ExportFormat) {
        guard let note = viewModel.note else { return }
        let baseName = note.displayName.replacingOccurrences(of: ".md", with: "")

        switch format {
        case .pdf:
            pdfExportFilename = baseName + ".pdf"
            let data = viewModel.generatePDFData(title: note.displayName, body: viewModel.content)
            pdfDocument = PDFFileDocument(data: data)
            showPDFExporter = true
        case .plainText:
            plainTextExportFilename = baseName + ".txt"
            plainTextExportDocument = TextExportDocument(content: viewModel.content)
            showPlainTextExporter = true
        case .markdown:
            markdownExportFilename = baseName + ".md"
            markdownExportDocument = TextExportDocument(content: viewModel.content)
            showMarkdownExporter = true
        }
    }
    #endif

    private func loadBacklinks() async {
        guard let note = viewModel.note,
              let vaultRoot = viewModel.vaultRootURL else {
            backlinks = []
            return
        }
        let vaultProvider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let useCase = BacklinkUseCase(vaultProvider: vaultProvider)
        do {
            backlinks = try await useCase.findBacklinks(to: note.fileURL, in: vaultRoot)
        } catch {
            backlinks = []
        }
    }

    private func loadLinkSuggestions() {
        Task {
            linkSuggestions = await viewModel.computeLinkSuggestions()
        }
    }

    private func applyLinkSuggestion(_ suggestion: LinkSuggestionService.Suggestion) {
        QuartzFeedback.primaryAction()
        let wikiLink = "[[\(suggestion.noteName)]]"
        let nsContent = viewModel.content as NSString
        let nsRange = NSRange(suggestion.matchRange, in: viewModel.content)
        viewModel.content = nsContent.replacingCharacters(in: nsRange, with: wikiLink)
    }

    // MARK: - Link Suggestion Sheet

    private var linkSuggestionSheet: some View {
        NavigationStack {
            Group {
                if linkSuggestions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "link.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "No link suggestions found", bundle: .module))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Create more notes in your vault to see suggestions.", bundle: .module))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(linkSuggestions) { suggestion in
                            Button {
                                applyLinkSuggestion(suggestion)
                                loadLinkSuggestions()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "link")
                                        .font(.body)
                                        .foregroundStyle(QuartzColors.accent)
                                        .frame(minWidth: 44, minHeight: 44)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(suggestion.noteName)
                                            .font(.body.weight(.medium))
                                        let context = extractContext(
                                            for: suggestion.matchRange,
                                            in: viewModel.content
                                        )
                                        Text(context)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(QuartzColors.accent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Suggest Links", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) {
                        showLinkSuggestions = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func extractContext(for range: Range<String.Index>, in content: String) -> String {
        let lineRange = content.lineRange(for: range)
        let line = String(content[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.count <= 100 { return line }
        return String(line.prefix(100)) + "…"
    }

    private func applyFormatting(_ action: FormattingAction) {
        let (newText, newSelection) = formatter.apply(
            action, to: viewModel.content, selectedRange: viewModel.cursorPosition
        )
        viewModel.content = newText
        viewModel.cursorPosition = newSelection
    }

    // MARK: - Image Import

    #if os(iOS)
    private func handleImageSourceSelected() {
        // Sheet dismisses itself; onChange(of: selectedImageSource) opens the appropriate picker.
    }

    private func handlePhotoLibrarySelection(_ item: PhotosPickerItem) async {
        do {
            guard let loaded = try await item.loadTransferable(type: ImageDataTransferable.self) else {
                return
            }
            let ext = loaded.preferredExtension ?? "png"
            let tempURL = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).\(ext)")
            try loaded.data.write(to: tempURL)
            await viewModel.importImage(from: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
        await MainActor.run {
            selectedPhotoItem = nil
            showImageSourceSheet = false
        }
    }

    private func handleScannedImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        #if canImport(Vision) && canImport(PencilKit)
        let ocrService = HandwritingOCRService()
        var allOCRText: [String] = []
        for image in images {
            await viewModel.importImage(image)
            if let cgImage = image.cgImage,
               let result = try? await ocrService.recognizeText(in: cgImage),
               !result.fullText.isEmpty {
                allOCRText.append(result.fullText)
            }
        }
        if !allOCRText.isEmpty {
            let text = "\n\n" + allOCRText.joined(separator: "\n\n")
            viewModel.insertTextAtCursor(text)
        }
        #else
        for image in images {
            await viewModel.importImage(image)
        }
        #endif
    }
    #endif

    private func handleImagePickerResult(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                await viewModel.importImage(from: url)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { return false }

        let vm = viewModel
        Task {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data: Data? = await withCheckedContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
                guard let data else { return }
                let suggested = provider.suggestedName ?? "dropped-image"
                let name = URL(fileURLWithPath: suggested).pathExtension.isEmpty ? "\(suggested).png" : suggested
                let tempURL = FileManager.default.temporaryDirectory.appending(path: name)
                try? FileManager.default.removeItem(at: tempURL)
                try? data.write(to: tempURL)
                await vm.importImage(from: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        await vm.importImage(from: url)
                    }
                }
            }
        }
        return true
    }

    private var selectedOrFullText: String {
        let pos = viewModel.cursorPosition
        if pos.length > 0 {
            let nsText = viewModel.content as NSString
            let safeRange = NSRange(
                location: min(pos.location, nsText.length),
                length: min(pos.length, nsText.length - min(pos.location, nsText.length))
            )
            return nsText.substring(with: safeRange)
        }
        return viewModel.content
    }

    // MARK: - Editor Header (Liquid Glass)

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note = viewModel.note {
                // Breadcrumbs
                HStack(spacing: 6) {
                    let pathComponents = breadcrumbComponents(for: note)
                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: editorBreadcrumbChevronSize, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(component)
                            .font(.subheadline.weight(index == pathComponents.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == pathComponents.count - 1 ? QuartzColors.accent : .secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)

                // Editable title + favorite
                HStack(spacing: 12) {
                    TextField(
                        String(localized: "Note title", bundle: .module),
                        text: $editableTitle
                    )
                    .font(.title.bold())
                    .textFieldStyle(.plain)
                    .onAppear {
                        editableTitle = note.displayName
                        isFavorite = Self.checkFavorite(note.fileURL)
                    }
                    .onChange(of: viewModel.note?.fileURL) { _, _ in
                        editableTitle = viewModel.note?.displayName ?? ""
                        if let url = viewModel.note?.fileURL {
                            isFavorite = Self.checkFavorite(url)
                        }
                    }
                    .onSubmit {
                        viewModel.renameNote(to: editableTitle)
                    }

                    Button {
                        QuartzFeedback.selection()
                        toggleFavorite(for: note.fileURL)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite
                        ? String(localized: "Remove from Favorites", bundle: .module)
                        : String(localized: "Add to Favorites", bundle: .module))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }

            Divider()
                .overlay(QuartzColors.accent.opacity(0.1))
        }
        #if os(visionOS)
        .quartzMaterialBackground(cornerRadius: 0)
        #else
        .quartzAmbientGlassBackground(style: .editorChrome, cornerRadius: 0)
        #endif
    }

    private func breadcrumbComponents(for note: NoteDocument) -> [String] {
        let url = note.fileURL
        var components: [String] = []
        let parentName = url.deletingLastPathComponent().lastPathComponent
        if !parentName.isEmpty && parentName != "/" {
            components.append(parentName)
        }
        components.append(url.lastPathComponent)
        return components
    }

    // MARK: - Backlinks Bar

    private var backlinkBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(QuartzColors.accent.opacity(0.05))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(editorBacklinkFont)
                        .foregroundStyle(.secondary)

                    ForEach(backlinks) { backlink in
                        Text(backlink.sourceNoteName)
                            .font(editorBacklinkFont.weight(.medium))
                            .foregroundStyle(QuartzColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(QuartzColors.accent.opacity(0.1))
                            )
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 36)
            .quartzMaterialBackground(cornerRadius: 0)
        }
    }

    // MARK: - Favorites

    private static func checkFavorite(_ url: URL) -> Bool {
        let favs = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        return favs.contains(url.lastPathComponent)
    }

    private func toggleFavorite(for url: URL) {
        var favs = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        let key = url.lastPathComponent
        if favs.contains(key) {
            favs.removeAll { $0 == key }
            isFavorite = false
        } else {
            favs.append(key)
            isFavorite = true
        }
        UserDefaults.standard.set(favs, forKey: Self.favoritesKey)
        NotificationCenter.default.post(name: .quartzFavoritesDidChange, object: nil)
    }

    // MARK: - Tag Bar

    private var tagBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: editorTagBarIconSize))
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.note?.frontmatter.tags ?? [], id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text("#\(tag)")
                                .font(.system(size: editorTagBarFontSize, weight: .medium))
                                .foregroundStyle(QuartzColors.accent)

                            Button {
                                QuartzFeedback.selection()
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: editorTagRemoveIconSize, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(QuartzColors.accent.opacity(0.1))
                        )
                    }

                    TextField(String(localized: "Add tag…", bundle: .module), text: $newTagText)
                        .font(.system(size: editorTagBarFontSize))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 60, maxWidth: 120)
                        .onSubmit { addTag() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) {
                    Divider().overlay(QuartzColors.accent.opacity(0.05))
                }
        }
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !tag.isEmpty, !(viewModel.note?.frontmatter.tags.contains(tag) ?? false) else {
            newTagText = ""
            return
        }
        QuartzFeedback.selection()
        var fm = viewModel.note?.frontmatter ?? Frontmatter()
        fm.tags.append(tag)
        viewModel.updateFrontmatter(fm)
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        var fm = viewModel.note?.frontmatter ?? Frontmatter()
        fm.tags.removeAll { $0 == tag }
        viewModel.updateFrontmatter(fm)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: editorStatusBarIconSize))
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.wordCount) words")
                    .monospacedDigit()
            }

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: editorStatusBarIconSize))
                    .foregroundStyle(.tertiary)
                Text(readingTime)
            }

            Spacer()

            if let error = viewModel.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: statusIcon)
                        .font(.system(size: editorStatusBarIconSize))
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .foregroundStyle(statusColor == .green ? QuartzColors.accent : .secondary)
                }
            }
        }
        .font(.system(size: editorStatusBarFontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) {
                    Divider().overlay(QuartzColors.accent.opacity(0.05))
                }
        }
    }

    private var readingTime: String {
        let minutes = max(1, viewModel.wordCount / 200)
        return String(localized: "\(minutes) min read", bundle: .module)
    }

    private var statusColor: Color {
        if viewModel.errorMessage != nil { return .red }
        if viewModel.isSaving { return .orange }
        if viewModel.isDirty { return .yellow }
        return .green
    }

    private var statusIcon: String {
        if viewModel.isSaving { return "arrow.trianglehead.2.clockwise" }
        if viewModel.isDirty { return "pencil.circle" }
        return "checkmark.circle.fill"
    }

    private var statusText: String {
        if viewModel.isSaving { return String(localized: "Saving…", bundle: .module) }
        if viewModel.isDirty { return String(localized: "Edited", bundle: .module) }
        return String(localized: "Synced", bundle: .module)
    }

    private func exportAsPDF() {
        guard let note = viewModel.note else { return }
        QuartzFeedback.primaryAction()
        let data = viewModel.generatePDFData(title: note.displayName, body: viewModel.content)
        pdfDocument = PDFFileDocument(data: data)
        pdfExportFilename = note.displayName
            .replacingOccurrences(of: ".md", with: "") + ".pdf"
        showPDFExporter = true
    }

    // MARK: - Toolbar Actions

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    QuartzFeedback.primaryAction()
                    showAITools = true
                } label: {
                    Label(String(localized: "Writing Tools (Apple Intelligence)", bundle: .module), systemImage: "wand.and.stars")
                }
                Button {
                    QuartzFeedback.primaryAction()
                    showChat = true
                } label: {
                    Label(String(localized: "Chat with Note", bundle: .module), systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    QuartzFeedback.primaryAction()
                    showAudioRecording = true
                } label: {
                    Label(String(localized: "Record Audio", bundle: .module), systemImage: "mic.fill")
                }
                Button {
                    QuartzFeedback.primaryAction()
                    #if os(iOS)
                    showImageSourceSheet = true
                    #else
                    showImagePicker = true
                    #endif
                } label: {
                    Label(String(localized: "Insert Image", bundle: .module), systemImage: "photo.on.rectangle.angled")
                }
                Divider()
                Button {
                    QuartzFeedback.primaryAction()
                    loadLinkSuggestions()
                    showLinkSuggestions = true
                } label: {
                    Label(String(localized: "Suggest Links", bundle: .module), systemImage: "link.badge.plus")
                }
                Button {
                    QuartzFeedback.toggle()
                    withAnimation(QuartzAnimation.standard) { showFrontmatter.toggle() }
                } label: {
                    Label(
                        showFrontmatter
                            ? String(localized: "Hide Frontmatter", bundle: .module)
                            : String(localized: "Show Frontmatter", bundle: .module),
                        systemImage: "doc.badge.gearshape"
                    )
                }
            Button {
                QuartzFeedback.toggle()
                withAnimation(QuartzAnimation.standard) { showBacklinks.toggle() }
            } label: {
                Label(
                    showBacklinks
                        ? String(localized: "Hide Backlinks", bundle: .module)
                        : String(localized: "Show Backlinks", bundle: .module),
                    systemImage: "link"
                )
            }
            Button {
                QuartzFeedback.primaryAction()
                showKnowledgeGraph = true
            } label: {
                Label(String(localized: "Knowledge Graph", bundle: .module), systemImage: "circle.hexagongrid")
            }
            Divider()
            Button {
                exportAsPDF()
            } label: {
                Label(String(localized: "Export as PDF", bundle: .module), systemImage: "doc.richtext")
            }
        } label: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "AI & Tools", bundle: .module))
            .help(String(localized: "AI writing tools, link suggestions, frontmatter, backlinks, knowledge graph, PDF export", bundle: .module))

            Button {
                QuartzFeedback.toggle()
                withAnimation(.bouncy) {
                    focusMode.toggleFocusMode()
                }
            } label: {
                Image(systemName: focusMode.isFocusModeActive ? "eye.slash.fill" : "eye.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            #if os(macOS)
            .focusable()
            #endif
            .accessibilityLabel(focusMode.isFocusModeActive
                ? String(localized: "Exit focus mode", bundle: .module)
                : String(localized: "Enter focus mode", bundle: .module))
            .accessibilityHint(String(localized: "Double tap to toggle", bundle: .module))
            .help(focusMode.isFocusModeActive
                ? String(localized: "Exit focus mode", bundle: .module)
                : String(localized: "Enter focus mode", bundle: .module))

            Button {
                QuartzFeedback.toggle()
                withAnimation(.bouncy) { isPreviewMode.toggle() }
            } label: {
                Image(systemName: isPreviewMode ? "pencil" : "doc.richtext")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(isPreviewMode
                ? String(localized: "Edit mode", bundle: .module)
                : String(localized: "Preview", bundle: .module))
            .help(isPreviewMode
                ? String(localized: "Switch to edit mode", bundle: .module)
                : String(localized: "Preview rendered markdown", bundle: .module))

            // Global toolbar actions (Search Brain, etc.) – after AI and Focus Mode
            if let onSearch {
                Button {
                    QuartzFeedback.primaryAction()
                    onSearch()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                        Text(String(localized: "Search Brain…", bundle: .module))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .disabled(searchDisabled)
                .help(String(localized: "Search notes", bundle: .module))
            }
            if let onNewNote {
                Button {
                    QuartzFeedback.primaryAction()
                    onNewNote()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(newNoteDisabled)
            }
            if let onRefresh {
                Button {
                    QuartzFeedback.primaryAction()
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(refreshDisabled)
            }
            #if os(macOS)
            if onSearch != nil || onNewNote != nil || onRefresh != nil {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
            }
            #endif

            Button {
                QuartzFeedback.primaryAction()
                Task { await viewModel.manualSave() }
            } label: {
                Image(systemName: "externaldrive")
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(viewModel.note == nil)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityLabel(String(localized: "Save note", bundle: .module))
            .help(String(localized: "Save (⌘S)", bundle: .module))

            if let note = viewModel.note {
                ShareLink(
                    item: viewModel.content,
                    subject: Text(note.displayName),
                    preview: SharePreview(note.displayName)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: "Share note", bundle: .module))
                .help(String(localized: "Share note", bundle: .module))
            }
        }
    }
}

// MARK: - Keyboard Shortcut Helpers

private enum EditorShortcut {
    case bold, italic, strikethrough, heading, code, link, blockquote
}

private extension View {
    func keyboardShortcut(for shortcut: EditorShortcut, action: @escaping () -> Void) -> some View {
        self.background {
            switch shortcut {
            case .bold:
                Button("") { action() }.keyboardShortcut("b", modifiers: .command).hidden()
            case .italic:
                Button("") { action() }.keyboardShortcut("i", modifiers: .command).hidden()
            case .strikethrough:
                Button("") { action() }.keyboardShortcut("x", modifiers: [.command, .shift]).hidden()
            case .heading:
                Button("") { action() }.keyboardShortcut("h", modifiers: [.command, .shift]).hidden()
            case .code:
                Button("") { action() }.keyboardShortcut("e", modifiers: .command).hidden()
            case .link:
                Button("") { action() }.keyboardShortcut("l", modifiers: [.command, .shift]).hidden()
            case .blockquote:
                Button("") { action() }.keyboardShortcut("q", modifiers: [.command, .shift]).hidden()
            }
        }
    }
}

// MARK: - Image Data Transferable (iOS)

#if os(iOS)
private struct ImageDataTransferable: Transferable {
    let data: Data
    var preferredExtension: String? {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpgHeader = Data([0xFF, 0xD8])
        if data.prefix(8) == pngHeader { return "png" }
        if data.prefix(2) == jpgHeader { return "jpg" }
        return "png"
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImageDataTransferable(data: data)
        }
    }
}
#endif

// MARK: - Export Documents

private struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, UTType(filenameExtension: "md")!] }
    let content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        content = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// MARK: - Editor Format Button (hover + press feedback)

struct EditorFormatButton: View {
    let action: FormattingAction
    let icon: String
    let onTap: () -> Void
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isPressed ? appearance.accentColor : .primary)
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #else
            .frame(minWidth: 32, minHeight: 32)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityLabel(action.label)
            .help(action.shortcut.map { "\(action.label) (\($0))" } ?? action.label)
    }

    private var backgroundColor: Color {
        if isPressed { return appearance.accentColor.opacity(0.25) }
        #if os(macOS)
        if isHovered { return Color.primary.opacity(0.08) }
        #endif
        return .clear
    }
}
