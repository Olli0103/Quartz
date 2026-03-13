import SwiftUI

/// Sidebar mit rekursivem Dateibaum, Suchfeld und Kontextmenüs.
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?
    @State private var renamingNode: FileNode?
    @State private var renameText: String = ""
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
            ForEach(viewModel.filteredTree) { node in
                nodeView(for: node)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: Text("Search notes"))
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.fileTree.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "doc.text",
                    description: Text("Open a vault to get started.")
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
    }

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

        Button {
            renameText = node.name
            renamingNode = node
        } label: {
            Label("Rename", systemImage: "pencil")
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
        Button {
            renameText = node.name
            renamingNode = node
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

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
