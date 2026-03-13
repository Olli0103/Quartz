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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editorViewModel?.note?.fileURL)
        .onChange(of: selectedNoteURL) { _, newURL in
            openNote(at: newURL)
        }
        .sheet(isPresented: $showVaultPicker) {
            VaultPickerView { vault in
                appState.currentVault = vault
                let provider = ServiceContainer.shared.resolveVaultProvider()
                let viewModel = SidebarViewModel(vaultProvider: provider)
                sidebarViewModel = viewModel
                Task {
                    await viewModel.loadTree(at: vault.rootURL)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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

                            Menu {
                                Button {
                                    showVaultPicker = true
                                } label: {
                                    Label("Open Vault", systemImage: "folder.badge.plus")
                                }
                                Button {
                                    showSettings = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
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
                title: "No Note Selected",
                subtitle: "Choose a note from the sidebar to start editing."
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
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating)

                Text("Welcome to Quartz")
                    .font(.title.bold())

                Text("Open a vault folder to start\ntaking beautiful notes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideUp()

            QuartzButton("Open Vault", icon: "folder.badge.plus") {
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
            }
        }
    }

    // MARK: - Actions

    private func openNote(at url: URL?) {
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
