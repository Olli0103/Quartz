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
        onVaultChat: (() -> Void)? = nil
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
                }
            )
            .onChange(of: sidebarNoteSelection) { _, newURL in
                if let url = newURL {
                    store.selectedNoteURL = url
                }
            }
            .navigationTitle("Quartz")
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
            .navigationTitle("Quartz")
        }
    }

    // MARK: - Column: Note List (Middle)

    private var contentColumn: some View {
        NoteListSidebar(
            store: noteListStore,
            selectedNoteURL: $store.selectedNoteURL,
            onNewNote: onNewNote,
            onVoiceNote: onVoiceNote,
            onMeetingMinutes: onMeetingMinutes
        )
        .onChange(of: store.selectedSource) { _, newSource in
            Task { await noteListStore.changeSource(to: newSource) }
        }
    }

    // MARK: - Column: Detail (Editor)

    private var detailColumn: some View {
        Group {
            if let session = editorSession, session.note != nil {
                EditorContainerView(session: session, workspaceStore: store, documentChatSession: documentChatSession, onVoiceNote: onVoiceNote)
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
}
