import SwiftUI

/// Sidebar mit rekursivem Dateibaum, Tags, Suche und Kontextmenüs.
/// Apple-Notes-inspiriertes Design mit Liquid Glass Akzenten.
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?
    @State private var showNewFolderDialog = false
    @State private var showNewNoteDialog = false
    @State private var newItemName: String = ""
    @State private var newItemParent: URL?

    public init(viewModel: SidebarViewModel, selectedNoteURL: Binding<URL?>) {
        self.viewModel = viewModel
        self._selectedNoteURL = selectedNoteURL
    }

    public var body: some View {
        List(selection: $selectedNoteURL) {
            // Quick Actions
            quickActionsSection

            // Tags
            if !viewModel.tagInfos.isEmpty {
                tagsSection
            }

            // File Tree
            notesSection
        }
        .listStyle(.sidebar)
        .searchable(text: $viewModel.searchText, prompt: Text("Search notes…"))
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else if viewModel.fileTree.isEmpty {
                QuartzEmptyState(
                    icon: "tray",
                    title: "No Notes Yet",
                    subtitle: "Create your first note to get started."
                )
            }
        }
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("Folder name", text: $newItemName)
            Button("Create") {
                guard let parent = newItemParent else { return }
                Task { await viewModel.createFolder(named: newItemName, in: parent) }
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
        .alert("New Note", isPresented: $showNewNoteDialog) {
            TextField("Note name", text: $newItemName)
            Button("Create") {
                guard let parent = newItemParent else { return }
                Task { await viewModel.createNote(named: newItemName, in: parent) }
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        }
        .onAppear {
            viewModel.collectTags()
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        Section {
            Button {
                if let root = viewModel.vaultRootURL {
                    newItemParent = root
                    showNewNoteDialog = true
                }
            } label: {
                Label {
                    Text("New Note")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color(hex: 0xF2994A))
                }
            }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.tagInfos.prefix(12)) { tag in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if viewModel.selectedTag == tag.name {
                                    viewModel.selectedTag = nil
                                } else {
                                    viewModel.selectedTag = tag.name
                                }
                            }
                        } label: {
                            QuartzTagBadge(
                                text: tag.name,
                                isSelected: viewModel.selectedTag == tag.name
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                QuartzSectionHeader("Tags", icon: "tag")
                Spacer()
                if viewModel.selectedTag != nil {
                    Button("Clear") {
                        withAnimation { viewModel.selectedTag = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            ForEach(viewModel.filteredTree) { node in
                nodeView(for: node)
            }
        } header: {
            QuartzSectionHeader("Notes", icon: "doc.text")
        }
    }

    // MARK: - Node View

    @ViewBuilder
    private func nodeView(for node: FileNode) -> some View {
        if node.isFolder, let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    nodeView(for: child)
                }
            } label: {
                FileNodeRow(node: node)
            }
            .contextMenu { folderContextMenu(for: node) }
        } else if node.isNote {
            FileNodeRow(node: node)
                .tag(node.url)
                .contextMenu { noteContextMenu(for: node) }
        } else {
            FileNodeRow(node: node)
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func folderContextMenu(for node: FileNode) -> some View {
        Button {
            newItemParent = node.url
            showNewNoteDialog = true
        } label: {
            Label("New Note", systemImage: "doc.badge.plus")
        }

        Button {
            newItemParent = node.url
            showNewFolderDialog = true
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.delete(at: node.url) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func noteContextMenu(for node: FileNode) -> some View {
        Button(role: .destructive) {
            if selectedNoteURL == node.url {
                selectedNoteURL = nil
            }
            Task { await viewModel.delete(at: node.url) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
