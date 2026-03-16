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
    @State private var deletionTrigger: Bool = false

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
        .searchable(text: $viewModel.searchText, prompt: Text(String(localized: "Search notes…", bundle: .module)))
        .overlay {
            if viewModel.isLoading {
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        SkeletonRow()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .staggered(index: i, baseDelay: 0.1)
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            } else if viewModel.fileTree.isEmpty {
                QuartzEmptyState(
                    icon: "tray",
                    title: String(localized: "No Notes Yet", bundle: .module),
                    subtitle: String(localized: "Create your first note to get started.", bundle: .module)
                )
            }
        }
        .alert(String(localized: "New Folder", bundle: .module), isPresented: $showNewFolderDialog) {
            TextField(String(localized: "Folder name", bundle: .module), text: $newItemName)
            Button(String(localized: "Create", bundle: .module)) {
                guard let parent = newItemParent else { return }
                Task { await viewModel.createFolder(named: newItemName, in: parent) }
                newItemName = ""
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { newItemName = "" }
        }
        .alert(String(localized: "New Note", bundle: .module), isPresented: $showNewNoteDialog) {
            TextField(String(localized: "Note name", bundle: .module), text: $newItemName)
            Button(String(localized: "Create", bundle: .module)) {
                guard let parent = newItemParent else { return }
                Task { await viewModel.createNote(named: newItemName, in: parent) }
                newItemName = ""
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { newItemName = "" }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTag)
        .sensoryFeedback(.warning, trigger: deletionTrigger)
        .task {
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
                    Text(String(localized: "New Note", bundle: .module))
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
                    ForEach(Array(viewModel.tagInfos.prefix(12).enumerated()), id: \.element.id) { index, tag in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                        .buttonStyle(QuartzBounceButtonStyle())
                        .scaleIn(delay: Double(index) * 0.05)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                QuartzSectionHeader(String(localized: "Tags", bundle: .module), icon: "tag")
                Spacer()
                if viewModel.selectedTag != nil {
                    Button(String(localized: "Clear", bundle: .module)) {
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
            ForEach(Array(viewModel.filteredTree.enumerated()), id: \.element.id) { index, node in
                nodeView(for: node)
                    .staggered(index: index)
            }
        } header: {
            QuartzSectionHeader(String(localized: "Notes", bundle: .module), icon: "doc.text")
        }
    }

    // MARK: - Node View

    @ViewBuilder
    private func nodeView(for node: FileNode) -> some View {
        if node.isFolder, let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    nodeView(for: child)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
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
            Label(String(localized: "New Note", bundle: .module), systemImage: "doc.badge.plus")
        }

        Button {
            newItemParent = node.url
            showNewFolderDialog = true
        } label: {
            Label(String(localized: "New Folder", bundle: .module), systemImage: "folder.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            deletionTrigger.toggle()
            Task { await viewModel.delete(at: node.url) }
        } label: {
            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func noteContextMenu(for node: FileNode) -> some View {
        Button(role: .destructive) {
            if selectedNoteURL == node.url {
                selectedNoteURL = nil
            }
            deletionTrigger.toggle()
            Task { await viewModel.delete(at: node.url) }
        } label: {
            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
        }
    }
}
