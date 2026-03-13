import SwiftUI
import QuartzKit

/// Haupt-Layout: NavigationSplitView mit Sidebar und Editor.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarViewModel: SidebarViewModel?
    @State private var selectedNoteURL: URL?
    @State private var editorViewModel: NoteEditorViewModel?
    @State private var showVaultPicker = false

    var body: some View {
        NavigationSplitView {
            if let viewModel = sidebarViewModel {
                SidebarView(viewModel: viewModel, selectedNoteURL: $selectedNoteURL)
                    .navigationTitle(appState.currentVault?.name ?? "Quartz")
                    #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showVaultPicker = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Welcome to Quartz",
                    systemImage: "square.and.pencil",
                    description: Text("Open a vault folder to start taking notes.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open Vault") {
                            showVaultPicker = true
                        }
                    }
                }
            }
        } detail: {
            if let viewModel = editorViewModel {
                NoteEditorView(viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "doc.text",
                    description: Text("Select a note from the sidebar.")
                )
            }
        }
        .onChange(of: selectedNoteURL) { _, newURL in
            guard let url = newURL else {
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
    }
}
