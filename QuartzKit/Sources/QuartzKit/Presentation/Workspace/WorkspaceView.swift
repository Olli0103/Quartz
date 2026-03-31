import SwiftUI

/// Three-pane workspace shell.
///
/// Pure layout container using `NavigationSplitView`.
/// All state flows through `WorkspaceStore`.
/// No local columnVisibility hacks — binds directly to the store.
public struct WorkspaceView: View {
    @Bindable var store: WorkspaceStore
    let noteListStore: NoteListStore
    let sidebarViewModel: SidebarViewModel?
    let editorSession: EditorSession?
    var documentChatSession: DocumentChatSession?
    var onMapViewTap: (() -> Void)?
    var onDoubleClick: ((URL) -> Void)?
    var onNewNote: (() -> Void)?
    var onVoiceNote: (() -> Void)?
    var onMeetingMinutes: (() -> Void)?
    var onVaultChat: (() -> Void)?
    var onDashboard: (() -> Void)?
    var onSwitchVault: (() -> Void)?
    /// URLs with unresolved iCloud conflicts — drives the conflict banner in the editor.
    var conflictedNoteURLs: Set<URL> = []
    var onResolveConflict: ((URL) -> Void)?
    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarNoteSelection: URL?

    public init(
        store: WorkspaceStore,
        noteListStore: NoteListStore,
        sidebarViewModel: SidebarViewModel? = nil,
        editorSession: EditorSession? = nil,
        documentChatSession: DocumentChatSession? = nil,
        onMapViewTap: (() -> Void)? = nil,
        onDoubleClick: ((URL) -> Void)? = nil,
        onNewNote: (() -> Void)? = nil,
        onVoiceNote: (() -> Void)? = nil,
        onMeetingMinutes: (() -> Void)? = nil,
        onVaultChat: (() -> Void)? = nil,
        onDashboard: (() -> Void)? = nil,
        onSwitchVault: (() -> Void)? = nil,
        conflictedNoteURLs: Set<URL> = [],
        onResolveConflict: ((URL) -> Void)? = nil
    ) {
        self.store = store
        self.noteListStore = noteListStore
        self.sidebarViewModel = sidebarViewModel
        self.editorSession = editorSession
        self.documentChatSession = documentChatSession
        self.onMapViewTap = onMapViewTap
        self.onDoubleClick = onDoubleClick
        self.onNewNote = onNewNote
        self.onVoiceNote = onVoiceNote
        self.onMeetingMinutes = onMeetingMinutes
        self.onVaultChat = onVaultChat
        self.onDashboard = onDashboard
        self.onSwitchVault = onSwitchVault
        self.conflictedNoteURLs = conflictedNoteURLs
        self.onResolveConflict = onResolveConflict
    }

    private var isPureDark: Bool {
        appearance.pureDarkMode && colorScheme == .dark
    }

    /// Whether we need to override the system column backgrounds.
    /// Pure dark → black. No vibrant transparency → solid system background.
    private var needsOpaqueBackground: Bool {
        isPureDark || !appearance.vibrantTransparency
    }

    private var columnBackground: Color {
        if isPureDark { return .black }
        return colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
    }

    public var body: some View {
        NavigationSplitView(
            columnVisibility: $store.columnVisibility,
            preferredCompactColumn: $store.preferredCompactColumn
        ) {
            sidebarColumn
                .scrollContentBackground(needsOpaqueBackground ? .hidden : .automatic)
                .background(needsOpaqueBackground ? columnBackground : Color.clear)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                #else
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 300)
                #endif
        } content: {
            contentColumn
                .scrollContentBackground(needsOpaqueBackground ? .hidden : .automatic)
                .background(needsOpaqueBackground ? columnBackground : Color.clear)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
                #else
                .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 380)
                #endif
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: focusMode.isFocusModeActive) { _, isActive in
            store.applyFocusMode(isActive)
        }
    }

    // MARK: - Column: Source Sidebar

    @ViewBuilder
    private var sidebarColumn: some View {
        if let sidebarVM = sidebarViewModel {
            SidebarView(
                viewModel: sidebarVM,
                selectedNoteURL: $sidebarNoteSelection,
                onMapViewTap: onMapViewTap,
                onDoubleClick: onDoubleClick,
                onSourceChanged: { source in
                    store.selectedSource = source
                },
                onVaultChat: onVaultChat,
                onSearchChanged: { query in
                    noteListStore.searchText = query
                },
                onDashboard: onDashboard,
                onSwitchVault: onSwitchVault
            )
            .onChange(of: sidebarNoteSelection) { _, newURL in
                if let url = newURL {
                    store.selectedNoteURL = url
                }
            }
            .navigationTitle("Quartz Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        } else {
            QuartzEmptyState(
                icon: "folder",
                title: "No Vault Open",
                subtitle: "Open a vault to see your notes"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Quartz Notes")
        }
    }

    // MARK: - Column: Note List (Middle)

    private var contentColumn: some View {
        NoteListSidebar(
            store: noteListStore,
            selectedNoteURL: $store.selectedNoteURL,
            onNewNote: onNewNote,
            onVoiceNote: onVoiceNote,
            onMeetingMinutes: onMeetingMinutes,
            onDeleteNote: { url in
                Task { await sidebarViewModel?.delete(at: url) }
            }
        )
        .onChange(of: store.selectedSource) { _, newSource in
            Task { await noteListStore.changeSource(to: newSource) }
        }
    }

    // MARK: - Column: Detail (Editor)

    private var detailColumn: some View {
        Group {
            if store.showGraph {
                KnowledgeGraphView(
                    fileTree: sidebarViewModel?.fileTree ?? [],
                    currentNoteURL: store.selectedNoteURL,
                    vaultRootURL: sidebarViewModel?.vaultRootURL,
                    vaultProvider: ServiceContainer.shared.resolveVaultProvider(),
                    embeddingService: nil,
                    onSelectNote: { url in
                        store.selectedNoteURL = url
                    },
                    isEmbedded: true,
                    graphEdgeStore: editorSession?.graphEdgeStore
                )
            } else if store.showDashboard {
                DashboardView(
                    sidebarViewModel: sidebarViewModel,
                    vaultProvider: ServiceContainer.shared.resolveVaultProvider(),
                    onSelectNote: { url in
                        store.selectedNoteURL = url
                    },
                    onNewNote: onNewNote ?? {},
                    onExploreGraph: onMapViewTap ?? {},
                    onRecordVoiceNote: onVoiceNote,
                    onRecordMeetingMinutes: onMeetingMinutes,
                    onQuickCapture: { text in
                        appendToDailyNote(text)
                    }
                )
            } else if store.selectedNoteURL != nil, let session = editorSession {
                let noteInTrash = sidebarViewModel?.isInTrash(store.selectedNoteURL ?? URL(fileURLWithPath: "/")) ?? false
                EditorContainerView(
                    session: session,
                    workspaceStore: store,
                    documentChatSession: documentChatSession,
                    onVoiceNote: onVoiceNote,
                    conflictedNoteURLs: conflictedNoteURLs,
                    onResolveConflict: onResolveConflict,
                    isInTrash: noteInTrash,
                    onRestoreFromTrash: {
                        guard let url = store.selectedNoteURL else { return }
                        store.selectedNoteURL = nil
                        Task { await sidebarViewModel?.restoreFromTrash(at: url) }
                    },
                    onPermanentlyDelete: {
                        guard let url = store.selectedNoteURL else { return }
                        store.selectedNoteURL = nil
                        Task { await sidebarViewModel?.permanentlyDelete(at: url) }
                    }
                )
            } else if let session = editorSession, let error = session.errorMessage {
                iCloudErrorView(message: error)
            } else {
                QuartzEmptyState(
                    icon: "text.cursor",
                    title: "No Note Selected",
                    subtitle: "Choose a note from the list to start editing"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .quartzAmbientShellBackground()
    }

    private func iCloudErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                if let url = store.selectedNoteURL {
                    editorSession?.errorMessage = nil
                    Task { await editorSession?.loadNote(at: url) }
                }
            } label: {
                Label(String(localized: "Try Again", bundle: .module), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Quick Capture → Daily Note

    private func appendToDailyNote(_ text: String) {
        guard let vaultRoot = sidebarViewModel?.vaultRootURL else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let fileName = "Daily Note \(df.string(from: Date())).md"
        let dailyURL = vaultRoot.appending(path: fileName)
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let entry = "\n- \(timestamp): \(text)\n"

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let path = dailyURL.path(percentEncoded: false)
            if fm.fileExists(atPath: path) {
                // Append
                if let handle = try? FileHandle(forWritingTo: dailyURL) {
                    handle.seekToEndOfFile()
                    if let data = entry.data(using: .utf8) {
                        handle.write(data)
                    }
                    try? handle.close()
                }
            } else {
                // Create
                let header = "# Daily Note — \(df.string(from: Date()))\n"
                let content = header + entry
                try? content.data(using: .utf8)?.write(to: dailyURL)
            }
        }
    }
}
