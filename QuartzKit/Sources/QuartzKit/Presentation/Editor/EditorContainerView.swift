import SwiftUI

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
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode

    /// AI Writing Tools state — uses an Identifiable item for `.sheet(item:)` to guarantee
    /// the captured text is available when the sheet renders (prevents blank popover).
    @State private var aiToolsRequest: AIToolsRequest?
    @State private var showChat = false

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
        onResolveConflict: ((URL) -> Void)? = nil
    ) {
        self.session = session
        self.workspaceStore = workspaceStore
        self.documentChatSession = documentChatSession
        self.onVoiceNote = onVoiceNote
        self.conflictedNoteURLs = conflictedNoteURLs
        self.onResolveConflict = onResolveConflict
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let note = session.note {
                editorHeader(for: note)
            }

            MarkdownEditorRepresentable(
                session: session,
                editorFontScale: appearance.editorFontScale,
                editorFontFamily: appearance.editorFontFamily,
                editorLineSpacing: appearance.editorLineSpacing,
                editorMaxWidth: appearance.editorMaxWidth
            )

            editorStatusBar
        }
        .overlay(alignment: .top) {
            if isCurrentNoteConflicted {
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
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 72)
        }
        .overlay(alignment: .bottom) {
            IosEditorToolbar(
                onFormatting: { action in session.applyFormatting(action) },
                onSave: { Task { await session.manualSave() } },
                formattingState: session.formattingState,
                isComposing: session.isComposing,
                hasSelection: session.cursorPosition.length > 0,
                onAIAssist: { triggerAIAssist() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup(placement: .principal) {
                MacEditorToolbar(
                    onFormatting: { action in session.applyFormatting(action) },
                    formattingState: session.formattingState,
                    isComposing: session.isComposing,
                    hasSelection: session.cursorPosition.length > 0,
                    onUndo: { session.undo() },
                    onRedo: { session.redo() },
                    onAIAssist: { triggerAIAssist() }
                )
            }
            #endif

            ToolbarItemGroup(placement: .primaryAction) {
                if let onVoiceNote {
                    Button {
                        QuartzFeedback.primaryAction()
                        onVoiceNote()
                    } label: {
                        Image(systemName: "mic")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "Record Voice Note", bundle: .module))
                    .help(String(localized: "Record a voice note", bundle: .module))
                }

                // Share / Export menu
                if session.note != nil {
                    ShareMenuView(
                        markdownText: session.currentText,
                        noteTitle: session.note?.displayName ?? "Note"
                    )
                }

                Button {
                    focusMode.isFocusModeActive.toggle()
                } label: {
                    Image(systemName: focusMode.isFocusModeActive
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(
                    focusMode.isFocusModeActive
                        ? String(localized: "Exit Focus Mode", bundle: .module)
                        : String(localized: "Enter Focus Mode", bundle: .module)
                )
                .help(String(localized: "Toggle distraction-free writing", bundle: .module))

                if documentChatSession != nil {
                    Button {
                        QuartzFeedback.primaryAction()
                        showChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(String(localized: "Chat about this note", bundle: .module))
                    .help(String(localized: "Ask AI about this note", bundle: .module))
                }

                Button {
                    withAnimation(QuartzAnimation.content) {
                        session.inspectorStore.isVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(
                    session.inspectorStore.isVisible
                        ? String(localized: "Hide Inspector", bundle: .module)
                        : String(localized: "Show Inspector", bundle: .module)
                )
            }
        }
        #if os(macOS)
        .inspector(isPresented: Binding(
            get: { session.inspectorStore.isVisible },
            set: { session.inspectorStore.isVisible = $0 }
        )) {
            InspectorSidebar(
                store: session.inspectorStore,
                note: session.note,
                vaultRootURL: session.vaultRootURL,
                onScrollToHeading: { heading in
                    session.scrollToHeading(heading)
                },
                onUpdateTags: { newTags in
                    session.updateTags(newTags)
                },
                onNavigateToNote: { url in
                    QuartzFeedback.primaryAction()
                    NotificationCenter.default.post(
                        name: .quartzWikiLinkNavigation,
                        object: nil,
                        userInfo: [
                            "url": url,
                            "title": url.deletingPathExtension().lastPathComponent
                        ]
                    )
                }
            )
            .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
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
                        )
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
}
