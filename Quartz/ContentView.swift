import SwiftUI
import QuartzKit

/// Haupt-Layout: NavigationSplitView mit Sidebar und Editor.
/// Liquid Glass Design mit sanften Übergängen.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarViewModel: SidebarViewModel?
    @State private var selectedNoteURL: URL?
    @State private var editorViewModel: NoteEditorViewModel?
    @State private var showVaultPicker = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var newNoteName = ""
    @State private var newNoteParent: URL?
    @State private var searchIndex: VaultSearchIndex?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeIconSize: CGFloat = 64

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
        .animation(QuartzAnimation.smooth, value: editorViewModel?.note?.fileURL)
        .onChange(of: selectedNoteURL) { _, newURL in
            openNote(at: newURL)
        }
        // MARK: - Keyboard Shortcut Handlers
        .onChange(of: appState.pendingCommand) { _, command in
            guard command != .none else { return }
            defer { appState.pendingCommand = .none }
            switch command {
            case .newNote:
                if let root = sidebarViewModel?.vaultRootURL {
                    newNoteParent = root
                    showNewNote = true
                }
            case .newFolder:
                if let root = sidebarViewModel?.vaultRootURL {
                    newNoteParent = root
                    showNewFolder = true
                }
            case .search, .globalSearch:
                showSearch = true
            case .toggleSidebar:
                withAnimation {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
            case .dailyNote:
                createDailyNote()
            case .none:
                break
            }
        }
        .sheet(isPresented: $showVaultPicker) {
            VaultPickerView { vault in
                appState.currentVault = vault
                loadVault(vault)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSearch) {
            if let searchIndex {
                SearchView(searchIndex: searchIndex) { url in
                    selectedNoteURL = url
                }
            }
        }
        .alert(String(localized: "New Note"), isPresented: $showNewNote) {
            TextField(String(localized: "Note name"), text: $newNoteName)
            Button(String(localized: "Create")) {
                guard let parent = newNoteParent else { return }
                let name = newNoteName
                newNoteName = ""
                Task { await sidebarViewModel?.createNote(named: name, in: parent) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
        }
        .alert(String(localized: "New Folder"), isPresented: $showNewFolder) {
            TextField(String(localized: "Folder name"), text: $newNoteName)
            Button(String(localized: "Create")) {
                guard let parent = newNoteParent else { return }
                let name = newNoteName
                newNoteName = ""
                Task { await sidebarViewModel?.createFolder(named: name, in: parent) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
        }
        .overlay {
            if let error = appState.errorMessage {
                errorBanner(message: error)
            }
        }
        .tint(Color(hex: 0xF2994A))
    }

    // MARK: - Sidebar Column

    @ViewBuilder
    private var sidebarColumn: some View {
        if let viewModel = sidebarViewModel {
            SidebarView(viewModel: viewModel, selectedNoteURL: $selectedNoteURL)
                .navigationTitle(appState.currentVault?.name ?? "Quartz")
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 4) {
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel(String(localized: "Search"))
                            .disabled(searchIndex == nil)

                            Menu {
                                Button {
                                    showVaultPicker = true
                                } label: {
                                    Label(String(localized: "Open Vault"), systemImage: "folder.badge.plus")
                                }
                                Button {
                                    showSettings = true
                                } label: {
                                    Label(String(localized: "Settings"), systemImage: "gearshape")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel(String(localized: "More options"))
                        }
                    }
                }
        } else {
            welcomeView
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let viewModel = editorViewModel {
            NoteEditorView(viewModel: viewModel)
                .id(viewModel.note?.fileURL)
                .transition(.asymmetric(
                    insertion: .opacity
                        .combined(with: .scale(scale: 0.98, anchor: .top))
                        .combined(with: .offset(y: 8)),
                    removal: .opacity.combined(with: .scale(scale: 0.99))
                ))
        } else {
            QuartzEmptyState(
                icon: "doc.text",
                title: String(localized: "No Note Selected"),
                subtitle: String(localized: "Choose a note from the sidebar to start editing.")
            )
            .transition(.opacity)
        }
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
                    withAnimation { appState.errorMessage = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Dismiss"))
                .buttonStyle(.plain)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
        .animation(QuartzAnimation.status, value: appState.errorMessage)
    }

    // MARK: - Actions

    private func loadVault(_ vault: VaultConfig) {
        let provider = ServiceContainer.shared.resolveVaultProvider()
        let viewModel = SidebarViewModel(vaultProvider: provider)
        sidebarViewModel = viewModel

        let index = VaultSearchIndex(vaultProvider: provider)
        searchIndex = index

        Task {
            await viewModel.loadTree(at: vault.rootURL)
            do {
                try await index.buildIndex(at: vault.rootURL)
            } catch {
                appState.errorMessage = String(localized: "Search index could not be built. Search may be incomplete.")
            }
        }
    }

    private func createDailyNote() {
        guard let root = sidebarViewModel?.vaultRootURL else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: Date())
        Task {
            await sidebarViewModel?.createNote(named: name, in: root)
        }
    }

    private func openNote(at url: URL?) {
        editorViewModel?.cancelAllTasks()
        guard let url else {
            editorViewModel = nil
            return
        }
        let container = ServiceContainer.shared
        let vm = NoteEditorViewModel(
            vaultProvider: container.resolveVaultProvider(),
            frontmatterParser: container.resolveFrontmatterParser()
        )
        editorViewModel = vm
        Task { await vm.loadNote(at: url) }
    }
}
