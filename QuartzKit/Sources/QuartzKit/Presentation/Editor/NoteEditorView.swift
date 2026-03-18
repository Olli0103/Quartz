import SwiftUI
import UniformTypeIdentifiers
import CoreText

/// Markdown editor with liquid glass header, formatting toolbar, AI tools, and status bar.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.featureGate) private var featureGate
    @State private var showFocusModeHint = false
    @State private var showAITools = false
    @State private var showChat = false
    @State private var showBacklinks = false
    @State private var showFrontmatter = false
    @State private var showLinkSuggestions = false
    @State private var showAudioRecording = false
    @State private var showKnowledgeGraph = false
    @State private var showImagePicker = false
    @State private var backlinks: [Backlink] = []
    @State private var linkSuggestions: [LinkSuggestionService.Suggestion] = []
    @State private var editableTitle: String = ""
    @State private var isFavorite: Bool = false
    @State private var newTagText: String = ""
    @State private var pdfDocument: PDFFileDocument?
    @State private var showPDFExporter = false
    @State private var pdfExportFilename = "note.pdf"
    @State private var showSavedOverlay = false
    private let formatter = MarkdownFormatter()
    private static let favoritesKey = "quartz.favoriteNotes"

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorHeader
                .hidesInFocusMode()

            formattingBar
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

            MarkdownTextViewRepresentable(
                text: $viewModel.content,
                cursorPosition: $viewModel.cursorPosition,
                editorFontScale: appearance.editorFontScale,
                noteURL: viewModel.note?.fileURL
            )
            .onDrop(of: [.image], isTargeted: nil) { providers in
                handleImageDrop(providers)
            }

            if showBacklinks && !backlinks.isEmpty {
                backlinkBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.note != nil {
                tagBar
                    .hidesInFocusMode()
            }

            statusBar
                .hidesInFocusMode()
        }
        .sensoryFeedback(.success, trigger: viewModel.manualSaveCompleted)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: focusMode.isFocusModeActive)
        .onChange(of: viewModel.manualSaveCompleted) { _, _ in
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
            ToolbarItem(placement: .primaryAction) {
                toolbarActions
            }
        }
        .keyboardShortcut(for: .bold) { applyFormatting(.bold) }
        .keyboardShortcut(for: .italic) { applyFormatting(.italic) }
        .keyboardShortcut(for: .code) { applyFormatting(.code) }
        .keyboardShortcut(for: .link) { applyFormatting(.link) }
        .onTapGesture(count: 3) {
            if focusMode.isFocusModeActive { focusMode.toggleFocusMode() }
        }
        .accessibilityAction(named: String(localized: "Exit focus mode", bundle: .module)) {
            if focusMode.isFocusModeActive { focusMode.toggleFocusMode() }
        }
        .overlay(alignment: .bottom) {
            if showFocusModeHint {
                Text(String(localized: "Triple-tap to exit focus mode", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
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
            AIWritingToolsView(selectedText: text) { [viewModel] processedText in
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
                noteTitle: viewModel.note?.displayName ?? "Note"
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
        .fileExporter(
            isPresented: $showPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: pdfExportFilename
        ) { _ in
            pdfDocument = nil
        }
        .task(id: viewModel.note?.fileURL) {
            await loadBacklinks()
        }
    }

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

    private func computeLinkSuggestions() {
        guard let note = viewModel.note else {
            linkSuggestions = []
            return
        }
        let service = LinkSuggestionService()
        linkSuggestions = service.suggestLinks(
            for: viewModel.content,
            currentNoteURL: note.fileURL,
            allNotes: viewModel.fileTree
        )
    }

    private func applyLinkSuggestion(_ suggestion: LinkSuggestionService.Suggestion) {
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
                                computeLinkSuggestions()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "link")
                                        .font(.body)
                                        .foregroundStyle(QuartzColors.accent)
                                        .frame(width: 28)

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
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return false }

        let vm = viewModel
        Task {
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data else { return }

            let suggested = provider.suggestedName ?? "dropped-image"
            let name = URL(fileURLWithPath: suggested).pathExtension.isEmpty
                ? "\(suggested).png"
                : suggested
            let tempURL = FileManager.default.temporaryDirectory.appending(path: name)
            try? FileManager.default.removeItem(at: tempURL)
            try? data.write(to: tempURL)
            await vm.importImage(from: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
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
                                .font(.system(size: 10, weight: .semibold))
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

                // Metadata
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text(note.frontmatter.modifiedAt, style: .relative)
                    }

                    if !note.frontmatter.tags.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "tag")
                                .font(.system(size: 12))
                            Text(note.frontmatter.tags.prefix(3).joined(separator: ", "))
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }

            Divider()
                .overlay(QuartzColors.accent.opacity(0.1))
        }
        .background(.ultraThinMaterial)
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

    // MARK: - Formatting Bar

    private var formattingBar: some View {
        FormattingToolbar { action in
            if action == .image {
                showImagePicker = true
            } else {
                applyFormatting(action)
            }
        }
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .bottom) {
                    Divider().overlay(QuartzColors.accent.opacity(0.05))
                }
        }
    }

    // MARK: - Backlinks Bar

    private var backlinkBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(QuartzColors.accent.opacity(0.05))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(backlinks) { backlink in
                        Text(backlink.sourceNoteName)
                            .font(.caption.weight(.medium))
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
            .background(.ultraThinMaterial)
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
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.note?.frontmatter.tags ?? [], id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text("#\(tag)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(QuartzColors.accent)

                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
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
                        .font(.caption)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.wordCount) words")
                    .monospacedDigit()
            }

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
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
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .foregroundStyle(statusColor == .green ? QuartzColors.accent : .secondary)
                }
            }
        }
        .font(.system(size: 11))
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

    // MARK: - PDF Export

    private func exportAsPDF() {
        guard let note = viewModel.note else { return }
        let data = generatePDFData(title: note.displayName, body: viewModel.content)
        pdfDocument = PDFFileDocument(data: data)
        pdfExportFilename = note.displayName
            .replacingOccurrences(of: ".md", with: "") + ".pdf"
        showPDFExporter = true
    }

    private func generatePDFData(title: String, body: String) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 54
        let contentWidth = pageSize.width - 2 * margin
        let contentHeight = pageSize.height - 2 * margin

        #if os(macOS)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        #else
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.black,
        ]
        #endif

        let fullText = NSMutableAttributedString()
        fullText.append(NSAttributedString(string: title + "\n\n", attributes: titleAttributes))
        fullText.append(NSAttributedString(string: body, attributes: bodyAttributes))

        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(fullText as CFAttributedString)
        var currentIndex = 0

        while currentIndex < fullText.length {
            ctx.beginPage(mediaBox: &mediaBox)

            let frameRect = CGRect(x: margin, y: margin, width: contentWidth, height: contentHeight)
            let framePath = CGPath(rect: frameRect, transform: nil)
            let ctFrame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: currentIndex, length: 0), framePath, nil
            )

            CTFrameDraw(ctFrame, ctx)

            let visibleRange = CTFrameGetVisibleStringRange(ctFrame)
            if visibleRange.length == 0 { break }
            currentIndex += visibleRange.length

            ctx.endPage()
        }

        ctx.closePDF()
        return mutableData as Data
    }

    // MARK: - Toolbar Actions

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button { showAITools = true } label: {
                    Label(String(localized: "Writing Tools (Apple Intelligence)", bundle: .module), systemImage: "wand.and.stars")
                }
                Button { showChat = true } label: {
                    Label(String(localized: "Chat with Note", bundle: .module), systemImage: "bubble.left.and.bubble.right")
                }
                Button { showAudioRecording = true } label: {
                    Label(String(localized: "Record Audio", bundle: .module), systemImage: "mic.fill")
                }
                Button { showImagePicker = true } label: {
                    Label(String(localized: "Insert Image", bundle: .module), systemImage: "photo.on.rectangle.angled")
                }
                Divider()
                Button {
                    computeLinkSuggestions()
                    showLinkSuggestions = true
                } label: {
                    Label(String(localized: "Suggest Links", bundle: .module), systemImage: "link.badge.plus")
                }
                Button {
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
                showKnowledgeGraph = true
            } label: {
                Label(String(localized: "Knowledge Graph", bundle: .module), systemImage: "circle.hexagongrid")
            }
            Divider()
            Button { exportAsPDF() } label: {
                Label(String(localized: "Export as PDF", bundle: .module), systemImage: "doc.richtext")
            }
        } label: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(String(localized: "AI & Tools", bundle: .module))
            .help(String(localized: "AI writing tools, link suggestions, frontmatter, backlinks, knowledge graph, PDF export", bundle: .module))

            if featureGate.isEnabled(.focusMode) {
                Button {
                    focusMode.toggleFocusMode()
                } label: {
                    Image(systemName: focusMode.isFocusModeActive ? "eye.slash.fill" : "eye.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(focusMode.isFocusModeActive
                    ? String(localized: "Exit focus mode", bundle: .module)
                    : String(localized: "Enter focus mode", bundle: .module))
                .help(focusMode.isFocusModeActive
                    ? String(localized: "Exit focus mode", bundle: .module)
                    : String(localized: "Enter focus mode", bundle: .module))
            }

            Button {
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
    case bold, italic, code, link
}

private extension View {
    func keyboardShortcut(for shortcut: EditorShortcut, action: @escaping () -> Void) -> some View {
        self.background {
            switch shortcut {
            case .bold:
                Button("") { action() }.keyboardShortcut("b", modifiers: .command).hidden()
            case .italic:
                Button("") { action() }.keyboardShortcut("i", modifiers: .command).hidden()
            case .code:
                Button("") { action() }.keyboardShortcut("e", modifiers: .command).hidden()
            case .link:
                Button("") { action() }.keyboardShortcut("k", modifiers: .command).hidden()
            }
        }
    }
}

// MARK: - PDF Export Document

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
