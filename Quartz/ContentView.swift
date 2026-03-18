import SwiftUI
import QuartzKit

/// Main layout: 3-column NavigationSplitView with sidebar, note list, and editor.
/// Liquid Glass design with smooth transitions.
struct ContentView: View {
    @Environment(AppState.self) private var appState
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
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeIconSize: CGFloat = 64
    @Namespace private var noteTransition

    var body: some View {
        AdaptiveLayoutView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            noteListColumn
        } detail: {
            detailColumn
        }
        .animation(QuartzAnimation.smooth, value: viewModel?.editorViewModel?.note?.fileURL)
        .task {
            if viewModel == nil {
                viewModel = ContentViewModel(appState: appState)
            }
        }
        .onChange(of: selectedNoteURL) { _, newURL in
            viewModel?.openNote(at: newURL)
        }
        // MARK: - Keyboard Shortcut Handlers
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
        .sheet(isPresented: $showVaultPicker) {
            VaultPickerView { vault in
                appState.switchVault(to: vault)
                viewModel?.loadVault(vault)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif
        .sheet(isPresented: $showSearch) {
            if let searchIndex = viewModel?.searchIndex {
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
                Task { await viewModel?.sidebarViewModel?.createNote(named: name, in: parent) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
        }
        .alert(String(localized: "New Folder"), isPresented: $showNewFolder) {
            TextField(String(localized: "Folder name"), text: $newNoteName)
            Button(String(localized: "Create")) {
                guard let parent = newNoteParent else { return }
                let name = newNoteName
                newNoteName = ""
                Task { await viewModel?.sidebarViewModel?.createFolder(named: name, in: parent) }
            }
            Button(String(localized: "Cancel"), role: .cancel) { newNoteName = "" }
        }
        .overlay(alignment: .top) {
            if let error = appState.errorMessage {
                errorBanner(message: error)
                    .id(error) // restart timer for each new error; .id change cancels previous .task
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        withAnimation { appState.dismissCurrentError() }
                    }
            }
        }
        .tint(Color(hex: 0xF2994A))
    }

    // MARK: - Sidebar Column

    @ViewBuilder
    private var sidebarColumn: some View {
        if let sidebarVM = viewModel?.sidebarViewModel {
            SidebarView(viewModel: sidebarVM, selectedNoteURL: $selectedNoteURL)
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
                            .disabled(viewModel?.searchIndex == nil)

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

    // MARK: - Note List Column

    @ViewBuilder
    private var noteListColumn: some View {
        if let sidebarVM = viewModel?.sidebarViewModel {
            let notes = sidebarVM.flatNotes
            List(notes, id: \.url, selection: $selectedNoteURL) { node in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name.replacingOccurrences(of: ".md", with: ""))
                            .font(.body)
                            .lineLimit(1)
                            .matchedGeometryEffect(id: node.url, in: noteTransition)
                        Text(node.url.deletingLastPathComponent().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .tag(node.url)
            }
            #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
            .navigationTitle(String(localized: "Notes"))
            .overlay {
                if notes.isEmpty {
                    QuartzEmptyState(
                        icon: "doc.text",
                        title: String(localized: "No Notes"),
                        subtitle: String(localized: "Create a note to get started.")
                    )
                }
            }
        } else {
            QuartzEmptyState(
                icon: "folder",
                title: String(localized: "No Vault"),
                subtitle: String(localized: "Open a vault to browse notes.")
            )
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let editorVM = viewModel?.editorViewModel {
            NoteEditorView(viewModel: editorVM)
                .id(editorVM.note?.fileURL)
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
                    withAnimation { appState.dismissCurrentError() }
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
}
