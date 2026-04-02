import SwiftUI
import QuartzKit
import UniformTypeIdentifiers
import os

/// Main layout: 3-column NavigationSplitView with source sidebar, note list, and editor.
///
/// ContentView is a thin layout shell. All modal/sheet/alert routing
/// lives in `AppCoordinator`. All workspace layout state lives in `WorkspaceStore`.
/// All column content lives in `WorkspaceView`.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ContentViewModel?
    @State private var workspaceStore = WorkspaceStore()
    @State private var coordinator = AppCoordinator()
    @State private var noteListStore = NoteListStore()
    @State private var securityOrchestrator = SecurityOrchestrator.shared
    @State private var commandPaletteEngine = CommandPaletteEngine(previewRepository: nil, commands: [])
    @State private var vaultCoordinator: VaultCoordinator?
    @State private var exportFileData: Data?
    @State private var exportFileName: String = "note.pdf"
    @State private var exportContentType: UTType = .pdf
    @State private var showExportFileExporter = false

    /// Convenience bridge — routes to WorkspaceStore's selection.
    private var selectedNoteURL: URL? {
        get { workspaceStore.selectedNoteURL }
        nonmutating set { workspaceStore.selectedNoteURL = newValue }
    }

    // MARK: - State Restoration
    @SceneStorage("quartz.selectedNotePath") private var restoredNotePath: String?
    @SceneStorage("quartz.cursorLocation") private var restoredCursorLocation: Int = 0
    @SceneStorage("quartz.cursorLength") private var restoredCursorLength: Int = 0
    @SceneStorage("quartz.scrollOffset") private var restoredScrollOffset: Double = 0

    /// Local text binding for alert TextFields.
    @State private var alertTextFieldValue = ""

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private static let onboardingCompletedKey = "quartz.hasCompletedOnboarding"

    // MARK: - Layout

    private var mainLayout: some View {
        WorkspaceView(
            store: workspaceStore,
            noteListStore: noteListStore,
            sidebarViewModel: viewModel?.sidebarViewModel,
            editorSession: viewModel?.editorSession,
            documentChatSession: viewModel?.documentChatSession,
            onMapViewTap: {
                workspaceStore.setRoute(.graph)
            },
            onDoubleClick: { url in
                #if os(macOS)
                openWindow(id: "note-window", value: url.standardizedFileURL)
                #endif
            },
            onNewNote: {
                if let root = viewModel?.sidebarViewModel?.vaultRootURL {
                    coordinator.presentNewNote(in: root)
                }
            },
            onVoiceNote: {
                coordinator.activeSheet = .voiceNote
            },
            onMeetingMinutes: {
                coordinator.activeSheet = .meetingMinutes
            },
            onVaultChat: {
                openVaultChat()
            },
            onDashboard: {
                workspaceStore.setRoute(.dashboard)
            },
            onSwitchVault: {
                #if os(macOS)
                presentOpenVaultFlow()
                #else
                coordinator.activeSheet = .vaultPicker
                #endif
            },
            vaultProvider: viewModel?.vaultProvider,
            conflictedNoteURLs: Set(viewModel?.conflictingFileURLs ?? []),
            onResolveConflict: { url in
                coordinator.activeSheet = .conflictResolver
            }
        )
        .stageManagerSupport(appState: appState, selectedNoteURL: Binding(
            get: { workspaceStore.selectedNoteURL },
            set: { workspaceStore.selectedNoteURL = $0 }
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            bodyWithSheets
                .disabled(securityOrchestrator.isLocked)

            if securityOrchestrator.isLocked {
                AppLockView(orchestrator: securityOrchestrator)
                    .transition(.opacity)
                    .zIndex(999) // Always on top of everything
            }
        }
        .animation(.smooth(duration: 0.3), value: securityOrchestrator.isLocked)
    }

    // MARK: - Sheet & Alert Layer

    private var bodyWithSheets: some View {
        bodyWithTask
            .sheet(item: $coordinator.activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            .background {
                // Cmd+Shift+J: Open Vault Chat
                Button("") { openVaultChat() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .hidden()
                // Cmd+K: Command Palette
                Button("") { toggleCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
            }
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { coordinator.activeAlert != nil },
                    set: { if !$0 { coordinator.activeAlert = nil; alertTextFieldValue = "" } }
                )
            ) {
                alertActions
            }
            .overlay(alignment: .top) { errorOverlay }
            .overlay {
                if coordinator.isCommandPaletteVisible {
                    CommandPaletteOverlay(
                        engine: commandPaletteEngine,
                        onDismiss: {
                            withAnimation(QuartzAnimation.standard) {
                                coordinator.isCommandPaletteVisible = false
                            }
                        },
                        onOpenNote: { url in
                            withAnimation(QuartzAnimation.standard) {
                                coordinator.isCommandPaletteVisible = false
                            }
                            selectedNoteURL = url
                        }
                    )
                    .zIndex(200)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: coordinator.isCommandPaletteVisible)
            .tint(appearance.accentColor)
            .fileExporter(
                isPresented: $showExportFileExporter,
                document: ExportFileDocument(data: exportFileData ?? Data(), format: .pdf),
                contentType: exportContentType,
                defaultFilename: exportFileName
            ) { _ in
                exportFileData = nil
            }
            #if os(macOS)
            .onDisappear {
                coordinator.quickNoteManager?.unregisterHotkey()
                coordinator.quickNoteManager = nil
                viewModel?.stopCloudSync()
            }
            #endif
    }

    // MARK: - Sheet Content Router

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .onboarding:
            onboardingSheet

        case .vaultPicker:
            #if os(iOS)
            VaultPickerView { vault in
                QuartzFeedback.success()
                vaultCoordinator?.persistBookmark(for: vault.rootURL, vaultName: vault.name)
                openVault(vault)
            }
            #else
            EmptyView()
            #endif

        case .settings:
            #if os(iOS)
            SettingsView()
            #else
            EmptyView()
            #endif

        case .search:
            searchSheet

        case .knowledgeGraph:
            #if os(macOS)
            knowledgeGraphSheet
            #else
            EmptyView()
            #endif

        case .voiceNote:
            voiceNoteSheet

        case .meetingMinutes:
            meetingMinutesSheet

        case .vaultChat:
            // Legacy case — migrated to .vaultChat2
            EmptyView()

        case .vaultChat2(let session):
            VaultChatView(
                session: session,
                onNavigateToNote: { noteID in
                    guard let url = viewModel?.urlForVaultNote(stableID: noteID) else { return }
                    selectedNoteURL = url
                    coordinator.activeSheet = nil
                },
                onReindex: {
                    viewModel?.reindexVault()
                }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif

        case .conflictResolver:
            if let urls = viewModel?.conflictingFileURLs, !urls.isEmpty {
                ConflictListResolverView(fileURLs: urls) {
                    // Reload the editor if the current note was resolved
                    if viewModel?.editorSession?.note?.fileURL != nil {
                        Task { await viewModel?.editorSession?.reloadFromDisk() }
                    }
                    Task { await viewModel?.sidebarViewModel?.refresh() }
                }
            }
        }
    }

    // MARK: - Alert Content

    private var alertTitle: String {
        switch coordinator.activeAlert {
        case .newNote: String(localized: "New Note")
        case .newFolder: String(localized: "New Folder")
        case nil: ""
        }
    }

    @ViewBuilder
    private var alertActions: some View {
        switch coordinator.activeAlert {
        case .newNote(let parent, let suggestedName):
            TextField(String(localized: "Note name"), text: $alertTextFieldValue)
                .onAppear { alertTextFieldValue = suggestedName }
            Button(String(localized: "Create")) {
                let name = alertTextFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                alertTextFieldValue = ""
                coordinator.activeAlert = nil
                guard !name.isEmpty else { return }
                Task {
                    if let url = await viewModel?.sidebarViewModel?.createNote(named: name, in: parent) {
                        await MainActor.run { selectedNoteURL = url }
                    }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                alertTextFieldValue = ""
            }

        case .newFolder(let parent):
            TextField(String(localized: "Folder name"), text: $alertTextFieldValue)
                .onAppear { alertTextFieldValue = "" }
            Button(String(localized: "Create")) {
                let name = alertTextFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                alertTextFieldValue = ""
                coordinator.activeAlert = nil
                guard !name.isEmpty else { return }
                Task {
                    await viewModel?.sidebarViewModel?.createFolder(named: name, in: parent)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                alertTextFieldValue = ""
            }

        case nil:
            EmptyView()
        }
    }

    // MARK: - Task & Event Layer

    private var bodyWithTask: some View {
        mainLayout
        .quartzAmbientShellBackground()
        .userActivity(QuartzUserActivity.openNoteActivityType, element: selectedNoteURL) { noteURL, activity in
            guard let vaultRoot = appState.currentVault?.rootURL else {
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                return
            }
            let title = viewModel?.editorSession?.note?.displayName
                ?? noteURL.deletingPathExtension().lastPathComponent
            QuartzUserActivity.configureOpenNoteActivity(
                activity,
                noteURL: noteURL,
                displayTitle: title,
                vaultRoot: vaultRoot
            )
        }
        .onContinueUserActivity(QuartzUserActivity.openNoteActivityType) { activity in
            guard let link = QuartzUserActivity.quartzDeepLink(from: activity) else { return }
            applyPendingOpenNoteDeepLink(link)
        }
        .task {
            if viewModel == nil {
                viewModel = ContentViewModel(appState: appState)
            }
            if vaultCoordinator == nil {
                vaultCoordinator = VaultCoordinator(appState: appState)
            }
            if appState.currentVault == nil {
                if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) {
                    coordinator.activeSheet = .onboarding
                } else {
                    vaultCoordinator?.restoreLastVault(
                        viewModel: viewModel,
                        noteListStore: noteListStore,
                        workspaceStore: workspaceStore
                    ) { restoreSelectedNoteIfNeeded() }
                    // If restoration failed (deleted folder, stale bookmark), show onboarding
                    if appState.currentVault == nil {
                        coordinator.activeSheet = .onboarding
                    }
                }
            }
            // Respect the user's dashboard-on-launch preference.
            // If a note was restored, showDashboard is already false (via didSet).
            // If no note was restored and the preference is off, dismiss the dashboard.
            if !appearance.showDashboardOnLaunch && workspaceStore.route == .dashboard {
                workspaceStore.setRoute(.empty)
            }
            coordinator.availableUpdate = await UpdateChecker.shared.checkForUpdate()
            consumePendingWidgetDeepLinks()
        }
        .onChange(of: scenePhase) { _, phase in
            securityOrchestrator.scenePhaseDidChange(to: phase)
            if phase == .active {
                consumePendingWidgetDeepLinks()
            }
            if phase == .background || phase == .inactive {
                saveStateForRestoration()
            }
        }
        .onChange(of: appState.pendingOpenDocumentScanner) { _, pending in
            guard pending else { return }
            appState.pendingOpenDocumentScanner = false
            // TODO: Document scanner presentation should be handled via EditorSession
            // or a dedicated coordinator, not via legacy editorViewModel.
            // See CODEX.md F3 for architectural direction.
            #if os(iOS)
            // Scanner is now presented by EditorContainerView's @State showDocumentScanner.
            // A proper fix would inject AppState into EditorContainerView and observe the flag there.
            #endif
        }
        .onChange(of: workspaceStore.selectedNoteURL) { _, newURL in
            viewModel?.openNote(at: newURL)
            if let url = newURL, let vaultRoot = appState.currentVault?.rootURL {
                let relativePath = url.path(percentEncoded: false)
                    .replacingOccurrences(of: vaultRoot.path(percentEncoded: false), with: "")
                restoredNotePath = relativePath
            } else {
                restoredNotePath = nil
            }
        }
        .onChange(of: appState.pendingCommand) { _, command in
            guard command != .none else { return }
            defer { appState.pendingCommand = .none }

            // Vault commands are handled here (they need ContentView's panel methods)
            switch command {
            case .openVault:
                #if os(macOS)
                presentOpenVaultFlow()
                #else
                coordinator.activeSheet = .vaultPicker
                #endif
                return
            case .createVault:
                #if os(macOS)
                presentCreateVaultFlow()
                #endif
                return
            default:
                break
            }

            viewModel?.handleCommand(
                command,
                coordinator: coordinator,
                workspaceStore: workspaceStore
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzReindexRequested)) { _ in
            viewModel?.reindexVault()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzNoteSaved)) { output in
            if let url = output.object as? URL {
                viewModel?.spotlightIndexNote(at: url)
                viewModel?.updatePreviewForNote(at: url)
                viewModel?.updateSearchIndex(for: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzSpotlightNotesRemoved)) { output in
            if let urls = output.userInfo?["urls"] as? [URL] {
                viewModel?.spotlightRemoveNotes(at: urls)
                viewModel?.removePreviewsForNotes(at: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzSpotlightNoteRelocated)) { output in
            guard let oldURL = output.userInfo?["old"] as? URL,
                  let newURL = output.userInfo?["new"] as? URL else { return }
            viewModel?.spotlightRelocateNote(from: oldURL, to: newURL)
            viewModel?.relocatePreview(from: oldURL, to: newURL)
        }
    }

    // MARK: - Deep Links

    private func consumePendingWidgetDeepLinks() {
        let d = UserDefaults(suiteName: "group.app.quartz.shared")
        if d?.bool(forKey: "pendingDocumentScanner") == true {
            d?.removeObject(forKey: "pendingDocumentScanner")
            // TODO: Scanner presentation needs architectural fix (see CODEX.md F3)
            #if os(iOS)
            // Currently no-op until EditorContainerView observes AppState
            #endif
        }
        guard let link = d?.string(forKey: "pendingDeepLink") else { return }
        d?.removeObject(forKey: "pendingDeepLink")
        if let url = URL(string: link), url.scheme == "quartz", url.host() == "note" {
            applyPendingOpenNoteDeepLink(url)
            return
        }
        switch link {
        case "quartz://new":
            appState.pendingCommand = .newNote
        case "quartz://daily":
            appState.pendingCommand = .dailyNote
        case "quartz://audio":
            coordinator.activeSheet = .voiceNote
        case "quartz://dashboard":
            workspaceStore.setRoute(.dashboard)
        case "quartz://scan":
            // TODO: Scanner presentation needs architectural fix (see CODEX.md F3)
            #if os(iOS)
            // Currently no-op until EditorContainerView observes AppState
            #endif
        default:
            break
        }
    }

    private func applyPendingOpenNoteDeepLink(_ url: URL) {
        guard let noteURL = QuartzUserActivity.resolveNoteFileURL(fromQuartzDeepLink: url, vaultRoot: appState.currentVault?.rootURL) else { return }
        selectedNoteURL = noteURL
    }

    // MARK: - Sheet Builders

    @ViewBuilder
    private var onboardingSheet: some View {
        OnboardingView { vault in
            Task { @MainActor in
                UserDefaults.standard.set(true, forKey: ContentView.onboardingCompletedKey)
                coordinator.activeSheet = nil
                vaultCoordinator?.persistBookmark(for: vault.rootURL, vaultName: vault.name)
                QuartzFeedback.success()
                openVault(vault)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    @ViewBuilder
    private var searchSheet: some View {
        if let searchIndex = viewModel?.searchIndex {
            SearchView(searchIndex: searchIndex) { url in
                selectedNoteURL = url
            }
        }
    }

    #if os(macOS)
    private var knowledgeGraphSheet: some View {
        NavigationStack {
            KnowledgeGraphView(
                fileTree: viewModel?.sidebarViewModel?.fileTree ?? [],
                currentNoteURL: viewModel?.editorSession?.note?.fileURL,
                vaultRootURL: viewModel?.sidebarViewModel?.vaultRootURL,
                vaultProvider: FileSystemVaultProvider(frontmatterParser: FrontmatterParser()),
                embeddingService: viewModel?.embeddingService,
                onSelectNote: { url in
                    coordinator.activeSheet = nil
                    selectedNoteURL = url
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        coordinator.activeSheet = nil
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    #endif

    @ViewBuilder
    private var voiceNoteSheet: some View {
        if let vaultURL = viewModel?.sidebarViewModel?.vaultRootURL {
            AudioRecordingView(
                vaultURL: vaultURL,
                onInsertText: { [viewModel] text in
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH-mm"
                    let name = "Voice Note \(df.string(from: Date()))"
                    Task {
                        if let url = await viewModel?.sidebarViewModel?.createNote(named: name, in: vaultURL, initialContent: text) {
                            await MainActor.run {
                                coordinator.activeSheet = nil
                                selectedNoteURL = url
                            }
                        }
                    }
                },
                compactMode: true
            )
        }
    }

    @ViewBuilder
    private var meetingMinutesSheet: some View {
        if let vaultURL = viewModel?.sidebarViewModel?.vaultRootURL {
            AudioRecordingView(
                vaultURL: vaultURL,
                onInsertText: { [viewModel] text in
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH-mm"
                    let name = "Meeting \(df.string(from: Date()))"
                    Task {
                        if let url = await viewModel?.sidebarViewModel?.createNote(named: name, in: vaultURL, initialContent: text) {
                            await MainActor.run {
                                coordinator.activeSheet = nil
                                selectedNoteURL = url
                            }
                        }
                    }
                },
                compactMode: true,
                initialMode: .meetingMinutes
            )
        }
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private var errorOverlay: some View {
        if let error = appState.errorMessage {
            errorBanner(message: error)
                .id(error)
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation { appState.dismissCurrentError() }
                }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button {
                    QuartzFeedback.selection()
                    withAnimation { appState.dismissCurrentError() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Dismiss"))
                .buttonStyle(.plain)
            }
            .padding(12)
            .quartzMaterialBackground(cornerRadius: 12, shadowRadius: 8)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
        .animation(QuartzAnimation.status, value: appState.errorMessage)
    }

    // MARK: - Vault Opening

    private func toggleCommandPalette() {
        if coordinator.isCommandPaletteVisible {
            withAnimation(QuartzAnimation.standard) {
                coordinator.isCommandPaletteVisible = false
            }
        } else {
            // Rebuild engine with current context before showing
            rebuildCommandPaletteEngine()
            withAnimation(QuartzAnimation.content) {
                coordinator.isCommandPaletteVisible = true
            }
        }
    }

    private func rebuildCommandPaletteEngine() {
        let vaultRoot = viewModel?.sidebarViewModel?.vaultRootURL
        let commands = CommandRegistry.build(
            vaultRoot: vaultRoot,
            onNewNote: { [weak viewModel] in
                if let root = viewModel?.sidebarViewModel?.vaultRootURL {
                    coordinator.presentNewNote(in: root)
                }
            },
            onNewFolder: { [weak viewModel] in
                if let root = viewModel?.sidebarViewModel?.vaultRootURL {
                    coordinator.presentNewFolder(in: root)
                }
            },
            onDailyNote: { [weak viewModel] in
                viewModel?.createDailyNote()
            },
            onVaultChat: {
                openVaultChat()
            },
            onSettings: {
                #if os(iOS)
                coordinator.activeSheet = .settings
                #endif
            },
            onToggleFocus: {
                focusMode.isFocusModeActive.toggle()
            },
            onToggleDarkMode: {
                appearance.theme = appearance.theme == .dark ? .light : .dark
            },
            onReindex: { [weak viewModel] in
                viewModel?.reindexVault()
            },
            onExportBackup: { [weak viewModel] in
                viewModel?.triggerManualBackup()
            },
            onExportPDF: { [weak viewModel] in
                exportNoteAs(.pdf, viewModel: viewModel)
            },
            onExportHTML: { [weak viewModel] in
                exportNoteAs(.html, viewModel: viewModel)
            },
            onOpenInNewWindow: {
                #if os(macOS)
                if let url = workspaceStore.selectedNoteURL {
                    openWindow(id: "note-window", value: url.standardizedFileURL)
                }
                #endif
            },
            onKnowledgeGraph: {
                coordinator.activeSheet = .knowledgeGraph
            }
        )

        commandPaletteEngine = CommandPaletteEngine(
            previewRepository: viewModel?.previewRepository,
            commands: commands,
            vaultRootURL: vaultRoot
        )
    }

    private func exportNoteAs(_ format: ExportFormat, viewModel: ContentViewModel?) {
        guard let session = viewModel?.editorSession,
              let note = session.note else { return }
        let text = session.currentText
        let title = note.displayName

        Task.detached(priority: .userInitiated) {
            let service = NoteExportService()
            let data: Data
            switch format {
            case .pdf: data = service.exportToPDF(text: text, title: title)
            case .html: data = service.exportToHTML(text: text, title: title)
            case .rtf: data = service.exportToRTF(text: text, title: title)
            case .markdown: data = service.exportToMarkdown(text: text, title: title)
            }

            let baseName = title.replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "/", with: "-")

            await MainActor.run {
                exportFileData = data
                exportFileName = "\(baseName).\(format.fileExtension)"
                switch format {
                case .pdf: exportContentType = .pdf
                case .html: exportContentType = .html
                case .rtf: exportContentType = .rtf
                case .markdown: exportContentType = .plainText
                }
                showExportFileExporter = true
            }
        }
    }

    private func openVaultChat() {
        Task {
            guard let session = await viewModel?.createVaultChatSession2() else { return }
            coordinator.activeSheet = .vaultChat2(session: session)
        }
    }

    private func openVault(_ vault: VaultConfig) {
        vaultCoordinator?.openVault(
            vault,
            viewModel: viewModel,
            noteListStore: noteListStore,
            workspaceStore: workspaceStore
        ) { restoreSelectedNoteIfNeeded() }

        #if os(macOS)
        coordinator.quickNoteManager?.unregisterHotkey()
        coordinator.quickNoteManager = QuickNoteManager(vaultRoot: vault.rootURL)
        coordinator.quickNoteManager?.registerHotkey()
        #endif
    }

    #if os(macOS)
    private func presentOpenVaultFlow() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Vault Folder")
        panel.message = String(localized: "Choose an existing folder with your notes.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Open")

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                let success = vaultCoordinator?.openVaultFromURL(
                    url,
                    viewModel: viewModel,
                    noteListStore: noteListStore,
                    workspaceStore: workspaceStore
                ) { restoreSelectedNoteIfNeeded() }
                if success != true {
                    // Error already shown by VaultCoordinator
                }
            }
        }
    }

    private func presentCreateVaultFlow() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Create Vault")
        panel.message = String(localized: "Choose where to create your Quartz Notes vault folder.")
        panel.prompt = String(localized: "Create")
        panel.nameFieldStringValue = String(localized: "Quartz Notes Vault")
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.treatsFilePackagesAsDirectories = true
        panel.isExtensionHidden = true

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                let success = vaultCoordinator?.createVault(
                    at: url,
                    viewModel: viewModel,
                    noteListStore: noteListStore,
                    workspaceStore: workspaceStore
                ) { restoreSelectedNoteIfNeeded() }
                if success != true {
                    // Error already shown by VaultCoordinator
                }
            }
        }
    }
    #endif

    // MARK: - State Restoration

    private func saveStateForRestoration() {
        guard let session = viewModel?.editorSession else { return }
        restoredCursorLocation = session.cursorPosition.location
        restoredCursorLength = session.cursorPosition.length
        restoredScrollOffset = session.scrollOffset.y
    }

    private func restoreSelectedNoteIfNeeded() {
        guard let vaultRoot = appState.currentVault?.rootURL,
              let relativePath = restoredNotePath,
              !relativePath.isEmpty else { return }
        let noteURL = vaultRoot.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            restoredNotePath = nil
            return
        }
        selectedNoteURL = noteURL

        // Schedule cursor/scroll restoration after note loads
        // Use a small delay to allow the editor to mount and populate
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            restoreEditorState()
        }
    }

    /// Restores cursor and scroll position to the active editor session.
    /// Called after note selection is restored.
    private func restoreEditorState() {
        guard let session = viewModel?.editorSession,
              session.note != nil else { return }

        // Restore cursor position
        if restoredCursorLocation > 0 || restoredCursorLength > 0 {
            session.restoreCursor(location: restoredCursorLocation, length: restoredCursorLength)
        }

        // Restore scroll position
        if restoredScrollOffset > 0 {
            session.restoreScroll(y: restoredScrollOffset)
        }
    }
}
