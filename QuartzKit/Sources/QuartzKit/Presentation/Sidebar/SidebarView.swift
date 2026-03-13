import SwiftUI

/// Sidebar mit rekursivem Dateibaum und Suchfeld.
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?

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
        } else if node.isNote {
            FileNodeRow(node: node)
                .tag(node.url)
        } else {
            FileNodeRow(node: node)
        }
    }
}
