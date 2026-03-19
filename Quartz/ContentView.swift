import SwiftUI
import QuartzKit
import UniformTypeIdentifiers
import os

/// Vault header subtitle font – larger on macOS.
private var vaultSubtitleFont: Font {
    #if os(macOS)
    .subheadline
    #else
    .caption
    #endif
}

/// Sidebar footer text font – larger on macOS.
private var sidebarFooterFont: Font {
    #if os(macOS)
    .subheadline
    #else
    .caption
    #endif
}

/// Main layout: 2-column NavigationSplitView with sidebar and editor.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @State private var viewModel: ContentViewModel?
    @State private var selectedNoteURL: URL?
    @State private var showVaultPicker = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var newNoteName = ""
    @State private var newNoteParent: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showOnboarding = false
    #if os(macOS)
    @State private var showKnowledgeGraph = false
    @State private var showVoiceNoteSheet = false
    @State private var showMeetingMinutesSheet = false
    #endif
    @State private var vaultChatSheetItem: VaultChatSheetItem?
    @State private var showSupport = false
    @State private var availableUpdate: UpdateChecker.ReleaseInfo?
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeIconSize: CGFloat = 64
    #if os(macOS)
    @State private var quickNoteManager: QuickNoteManager?
    #endif

    private static let onboardingCompletedKey = "quartz.hasCompletedOnboarding"

    private var mainLayout: some View {
        AdaptiveLayoutView(columnVisibility: focusMode.isFocusModeActive ? .constant(.detailOnly) : $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
    }

    var body: some View {
        bodyWithSheets
    }

    private var bodyWithSheets: some View {
        bodyWithTask
            .sheet(isPresented: $showOnboarding) { onboardingSheet }
            #if os(iOS)
            .sheet(isPresented: $showVaultPicker) { VaultPickerView { openVault($0) } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            #endif
            .sheet(isPresented: $showSearch) { searchSheet }
            .sheet(isPresented: $showSupport) { SupportView() }
            #if os(macOS)
            .sheet(isPresented: $showKnowledgeGraph) { knowledgeGraphSheet }
            #endif
            .sheet(item: $vaultChatSheetItem) { VaultChatView(session: $0.session) }
            #if os(macOS)
            .sheet(isPresented: $showVoiceNoteSheet) { voiceNoteSheet }
            .sheet(isPresented: $showMeetingMinutesSheet) { meetingMinutesSheet }
            #endif
            .alert(String(localized: "New Note"), isPresented: $showNewNote) {
                TextField(String(localized: "Note name"), text: $newNoteName)
                Button(String(localized: "Create")) {
                    guard let parent = newNoteParent else { return }
                    let name = newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    newNoteName = ""
                    guard !name.isEmpty else { return }
                    let finalName = name.hasSuffix(".md") ? name : "\(name).md"
                    let noteURL = parent.appending(path: finalName)
                    Task {
                        await viewModel?.sidebarViewModel?.createNote(named: name, in: parent)
                        await MainActor.run { selectedNoteURL = noteURL }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
            }
            .alert(String(localized: "New Folder"), isPresented: $showNewFolder) {
                TextField(String(localized: "Folder name"), text: $newNoteName)
                Button(String(localized: "Create")) {
                    guard let parent = newNoteParent else { return }
                    let name = newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    newNoteName = ""
                    guard !name.isEmpty else { return }
                    Task {
                        await viewModel?.sidebarViewModel?.createFolder(named: name, in: parent)
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
            }
            .overlay(alignment: .top) { errorOverlay }
            .onChange(of: showVaultPicker) { _, shouldShow in
                #if os(macOS)
                if shouldShow {
                    showVaultPicker = false
                    Task { @MainActor in pickVaultFolderMacOS() }
                }
                #endif
            }
            .tint(appearance.accentColor)
            #if os(macOS)
            .onDisappear {
                quickNoteManager?.unregisterHotkey()
                quickNoteManager = nil
                viewModel?.stopCloudSync()
            }
            #endif
    }

    private var bodyWithTask: some View {
        mainLayout
        .task {
            if viewModel == nil {
                viewModel = ContentViewModel(appState: appState)
            }
            if appState.currentVault == nil {
                if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) {
                    showOnboarding = true
                } else {
                    restoreLastVault()
                }
            }
            availableUpdate = await UpdateChecker.shared.checkForUpdate()
        }
        .onChange(of: selectedNoteURL) { _, newURL in
            viewModel?.openNote(at: newURL)
        }
        .onChange(of: appState.pendingCommand) { _, command in
            guard command != .none else { return }
            defer { appState.pendingCommand = .none }
            viewModel?.handleCommand(
                command,
                showNewNote: &showNewNote,
                showNewFolder: &showNewFolder,
                showSearch: &showSearch,
                columnVisibility: &columnVisibility,
                newNoteParent: &newNoteParent
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .quartzReindexRequested)) { _ in
            viewModel?.reindexVault()
        }
    }

    @ViewBuilder
    private var onboardingSheet: some View {
        OnboardingView { vault in
            Task { @MainActor in
                UserDefaults.standard.set(true, forKey: ContentView.onboardingCompletedKey)
                showOnboarding = false
                persistBookmark(for: vault.rootURL, vaultName: vault.name)
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
                currentNoteURL: viewModel?.editorViewModel?.note?.fileURL,
                vaultRootURL: viewModel?.sidebarViewModel?.vaultRootURL,
                vaultProvider: FileSystemVaultProvider(frontmatterParser: FrontmatterParser()),
                embeddingService: viewModel?.embeddingService,
                onSelectNote: { url in
                    showKnowledgeGraph = false
                    selectedNoteURL = url
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        showKnowledgeGraph = false
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

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
                                showVoiceNoteSheet = false
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
                                showMeetingMinutesSheet = false
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
    #endif

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

    // MARK: - Vault Opening

    private func openVault(_ vault: VaultConfig) {
        appState.switchVault(to: vault)
        viewModel?.loadVault(vault)
        selectedNoteURL = nil

        #if os(macOS)
        quickNoteManager?.unregisterHotkey()
        quickNoteManager = QuickNoteManager(vaultRoot: vault.rootURL)
        quickNoteManager?.registerHotkey()
        #endif
    }

    #if os(macOS)
    private func pickVaultFolderMacOS() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Vault Folder")
        panel.message = String(localized: "Choose an existing folder with your notes, or create a new one.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Open")

        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }

                guard url.startAccessingSecurityScopedResource() else {
                    appState.showError(String(localized: "Unable to access the selected folder. Please try again."))
                    return
                }

                let vault = VaultConfig(name: url.lastPathComponent, rootURL: url)
                persistBookmark(for: url, vaultName: vault.name)
                openVault(vault)
            }
        }
    }
    #endif

    // MARK: - Sidebar Column

    @ViewBuilder
    private var sidebarColumn: some View {
        if let sidebarVM = viewModel?.sidebarViewModel {
            VStack(spacing: 0) {
                // Vault header
                vaultHeader
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                #if os(macOS)
                SidebarView(viewModel: sidebarVM, selectedNoteURL: $selectedNoteURL, onMapViewTap: { showKnowledgeGraph = true })
                #else
                SidebarView(viewModel: sidebarVM, selectedNoteURL: $selectedNoteURL)
                #endif

                // Bottom bar: sync/ indexing (macOS also has Settings link)
                sidebarBottomBar
            }
            .quartzLiquidGlass(enabled: appearance.vibrantTransparency)
            .navigationTitle(appState.currentVault?.name ?? String(localized: "Quartz"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarIconButton(icon: "magnifyingglass") {
                        showSearch = true
                    }
                    .accessibilityLabel(String(localized: "Search"))
                    .help(String(localized: "Search notes"))
                    .disabled(viewModel?.searchIndex == nil)

                    toolbarIconButton(icon: "cup.and.saucer") {
                        showSupport = true
                    }
                    .accessibilityLabel(String(localized: "Support My Work"))
                    .help(String(localized: "Support the project"))

                    toolbarIconButton(icon: "brain.head.profile") {
                        if let session = viewModel?.createVaultChatSession() {
                            vaultChatSheetItem = VaultChatSheetItem(session: session)
                        }
                    }
                    .accessibilityLabel(String(localized: "Chat with Vault"))
                    .help(String(localized: "AI chat across all notes"))
                    .disabled(viewModel?.embeddingService == nil)

                    toolbarIconButton(icon: "folder.badge.plus") {
                        showVaultPicker = true
                    }
                    .accessibilityLabel(String(localized: "Open Vault"))
                    .help(String(localized: "Open or create vault"))

                    #if os(iOS)
                    toolbarIconButton(icon: "gearshape") {
                        showSettings = true
                    }
                    .accessibilityLabel(String(localized: "Settings"))
                    .help(String(localized: "Settings"))
                    #endif
                }
            }
        } else {
            welcomeView
        }
    }

    /// HIG-compliant toolbar icon button: minimum 44×44pt touch target.
    @ViewBuilder
    private func toolbarIconButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
    }

    // MARK: - Vault Header

    private var vaultHeader: some View {
        HStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentVault?.name ?? String(localized: "Quartz"))
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                Group {
                    #if os(macOS)
                    Text(String(localized: "Second Brain"))
                    #else
                    Text(String(localized: "Personal Vault"))
                    #endif
                }
                .font(vaultSubtitleFont)
                .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Button {
                    showVaultPicker = true
                } label: {
                    Label(String(localized: "Open Existing Vault"), systemImage: "folder")
                }
                Button {
                    showOnboarding = true
                } label: {
                    Label(String(localized: "Create New Vault…"), systemImage: "plus.rectangle.on.folder")
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "Vault Options"))
            .help(String(localized: "Vault Options"))
        }
    }

    // MARK: - Sidebar Bottom

    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(QuartzColors.accent.opacity(0.1))

            if let vm = viewModel, vm.cloudSyncStatus != .notApplicable {
                cloudSyncIndicator(status: vm.cloudSyncStatus)
            }

            if let progress = viewModel?.indexingProgress {
                indexingIndicator(current: progress.current, total: progress.total)
            }

            #if os(macOS)
            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Settings"))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #endif
            // iOS: Settings is in the top toolbar, no bottom row needed
        }
    }

    // MARK: - Cloud Sync Indicator

    private func cloudSyncIndicator(status: CloudSyncStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cloudSyncIcon(for: status))
                .font(sidebarFooterFont)
                .foregroundStyle(cloudSyncColor(for: status))
                .symbolEffect(.pulse, isActive: status == .uploading || status == .downloading)
            Text(cloudSyncLabel(for: status))
                .font(sidebarFooterFont)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func cloudSyncIcon(for status: CloudSyncStatus) -> String {
        switch status {
        case .current: "checkmark.icloud"
        case .uploading: "icloud.and.arrow.up"
        case .downloading: "icloud.and.arrow.down"
        case .notDownloaded: "icloud.and.arrow.down"
        case .conflict: "exclamationmark.icloud"
        case .error: "xmark.icloud"
        case .notApplicable: "icloud"
        }
    }

    private func cloudSyncColor(for status: CloudSyncStatus) -> Color {
        switch status {
        case .current: .green
        case .uploading, .downloading, .notDownloaded: .blue
        case .conflict: .orange
        case .error: .red
        case .notApplicable: .secondary
        }
    }

    private func cloudSyncLabel(for status: CloudSyncStatus) -> String {
        switch status {
        case .current: String(localized: "iCloud: Synced")
        case .uploading: String(localized: "iCloud: Uploading…")
        case .downloading, .notDownloaded: String(localized: "iCloud: Downloading…")
        case .conflict: String(localized: "iCloud: Conflict")
        case .error: String(localized: "iCloud: Sync Error")
        case .notApplicable: String(localized: "iCloud")
        }
    }

    // MARK: - Indexing Indicator

    private func indexingIndicator(current: Int, total: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(sidebarFooterFont)
                    .foregroundStyle(appearance.accentColor)
                    .symbolEffect(.pulse)
                Text(String(format: String(localized: "Indexing notes… %lld/%lld"), Int64(current), Int64(total)))
                    .font(sidebarFooterFont)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(current), total: Double(max(total, 1)))
                .tint(appearance.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .transition(.opacity)
        .animation(.easeInOut, value: current)
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            if let editorVM = viewModel?.editorViewModel {
                NoteEditorView(
                    viewModel: editorVM,
                    embeddingService: viewModel?.embeddingService,
                    onSearch: { showSearch = true },
                    onSupport: { showSupport = true },
                    onNewNote: {
                        newNoteParent = viewModel?.sidebarViewModel?.vaultRootURL
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd HH-mm"
                        newNoteName = "Note \(df.string(from: Date()))"
                        showNewNote = true
                    },
                    onRefresh: { Task { await viewModel?.sidebarViewModel?.refresh() } },
                    searchDisabled: viewModel?.searchIndex == nil,
                    newNoteDisabled: viewModel?.sidebarViewModel == nil,
                    refreshDisabled: viewModel?.sidebarViewModel == nil
                )
                .id(editorVM.note?.fileURL)
            } else {
            #if os(macOS)
            DashboardView(
                sidebarViewModel: viewModel?.sidebarViewModel,
                onSelectNote: { url in selectedNoteURL = url },
                onNewNote: {
                    newNoteParent = viewModel?.sidebarViewModel?.vaultRootURL
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH-mm"
                    newNoteName = "Note \(df.string(from: Date()))"
                    showNewNote = true
                },
                onExploreGraph: { showKnowledgeGraph = true },
                onRecordVoiceNote: { showVoiceNoteSheet = true },
                onRecordMeetingMinutes: { showMeetingMinutesSheet = true }
            )
            #else
            QuartzEmptyState(
                icon: "doc.text",
                title: String(localized: "No Note Selected"),
                subtitle: String(localized: "Choose a note from the sidebar to start editing.")
            )
            #endif
            }
        }
        #if os(macOS)
        .toolbar {
            // When no note is open (DashboardView), show global toolbar. When a note is open,
            // NoteEditorView shows the full toolbar (AI, Focus Mode, Search Brain, etc.).
            if viewModel?.editorViewModel == nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showSearch = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                            Text(String(localized: "Search Brain…"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel?.searchIndex == nil)

                    Button {
                        showSupport = true
                    } label: {
                        Image(systemName: "cup.and.saucer")
                    }
                    .help(String(localized: "Support the project"))

                    Button {
                        newNoteParent = viewModel?.sidebarViewModel?.vaultRootURL
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd HH-mm"
                        newNoteName = "Note \(df.string(from: Date()))"
                        showNewNote = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel?.sidebarViewModel == nil)

                    Button {
                        Task { await viewModel?.sidebarViewModel?.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel?.sidebarViewModel == nil)

                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: welcomeIconSize, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating)

                Text(String(localized: "Welcome to Quartz"))
                    .font(.title.bold())

                Text(String(localized: "Open a vault folder to start\ntaking beautiful notes."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideUp()

            QuartzButton(String(localized: "Open Vault"), icon: "folder.badge.plus") {
                showVaultPicker = true
            }
            .padding(.horizontal, 40)
            .slideUp(delay: 0.15)

            Button {
                showOnboarding = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.rectangle.on.folder")
                    Text(String(localized: "Create New Vault"))
                }
                .font(.body.weight(.medium))
                .foregroundStyle(QuartzColors.accent)
            }
            .buttonStyle(.plain)
            .slideUp(delay: 0.25)

            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(String(localized: "Settings"))
            }
        }
    }

    // MARK: - Vault Restoration

    private func restoreLastVault() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "quartz.lastVault.bookmark") else { return }

        var isStale = false
        do {
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            #endif

            guard url.startAccessingSecurityScopedResource() else {
                clearBookmark()
                return
            }

            // Test write access: try to write a tiny temp file then remove it.
            // Old bookmarks created with readonly scope will fail here.
            let testFile = url.appending(path: ".quartz-write-test")
            do {
                try Data().write(to: testFile, options: .atomic)
                try? FileManager.default.removeItem(at: testFile)
            } catch {
                url.stopAccessingSecurityScopedResource()
                clearBookmark()
                Logger(subsystem: "com.quartz", category: "Vault")
                    .warning("Saved bookmark has read-only access; user must re-select vault.")
                return
            }

            if isStale {
                persistBookmark(for: url, vaultName: url.lastPathComponent)
            }

            let name = UserDefaults.standard.string(forKey: "quartz.lastVault.name") ?? url.lastPathComponent
            let vault = VaultConfig(name: name, rootURL: url)
            openVault(vault)
        } catch {
            clearBookmark()
        }
    }

    private func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: "quartz.lastVault.bookmark")
        UserDefaults.standard.removeObject(forKey: "quartz.lastVault.name")
    }

    private func persistBookmark(for url: URL, vaultName: String) {
        do {
            #if os(macOS)
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            UserDefaults.standard.set(bookmarkData, forKey: "quartz.lastVault.bookmark")
            UserDefaults.standard.set(vaultName, forKey: "quartz.lastVault.name")
        } catch {
            Logger(subsystem: "com.quartz", category: "VaultPicker")
                .error("Failed to persist vault bookmark: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button {
                    withAnimation { appState.dismissCurrentError() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
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
}

// MARK: - Vault Chat Sheet Item

private struct VaultChatSheetItem: Identifiable {
    let id = UUID()
    let session: VaultChatSession
}
