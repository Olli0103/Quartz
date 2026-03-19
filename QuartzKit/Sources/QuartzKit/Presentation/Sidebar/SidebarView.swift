import SwiftUI
import UniformTypeIdentifiers

/// Transferable for sidebar drag & drop. Multiple representations for cross-platform reliability.
private struct SidebarItemTransferable: Transferable, Codable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        DataRepresentation(contentType: .utf8PlainText) { item in
            Data(item.url.absoluteString.utf8)
        } importing: { data in
            guard let str = String(data: data, encoding: .utf8),
                  let url = URL(string: str) else {
                throw NSError(domain: "SidebarItemTransferable", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL data"])
            }
            return SidebarItemTransferable(url: url)
        }
    }
}

private var sidebarSectionFont: Font {
    #if os(macOS)
    .callout.weight(.bold)
    #else
    .subheadline.weight(.bold)
    #endif
}

private var newNoteButtonIconSize: CGFloat {
    #if os(macOS)
    17
    #else
    15
    #endif
}

private var sidebarIconSize: CGFloat {
    #if os(macOS)
    16
    #else
    15
    #endif
}

/// ADA-quality sidebar with flawless drag & drop, insertion indicators, and spring-open folders.
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?
    var onMapViewTap: (() -> Void)?
    @Environment(\.appearanceManager) private var appearance
    @State private var showNewFolderDialog = false
    @State private var showNewNoteDialog = false
    @State private var newItemName: String = ""
    @State private var newItemParent: URL?
    @State private var deletionTrigger: Bool = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteURL: URL?
    @State private var pendingDeleteIsNote = false
    @State private var searchQuery: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedTemplate: NoteTemplate = .blank
    @State private var dropTargetURL: URL?
    @State private var moveSourceURL: URL?
    @State private var showMoveToFolderSheet = false
    /// Folders expanded by drag hover (spring-open). Persists during drag session.
    @State private var dragExpandedFolderURLs: Set<URL> = []
    /// Insertion indicator: (parentURL, index) for "drop between" visual.
    @State private var insertionIndicator: (parent: URL, index: Int)?

    public init(viewModel: SidebarViewModel, selectedNoteURL: Binding<URL?>, onMapViewTap: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self._selectedNoteURL = selectedNoteURL
        self.onMapViewTap = onMapViewTap
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                newNoteButton
                    .padding(.horizontal, 16)

                quickAccessSection
                    .padding(.horizontal, 16)

                if !viewModel.tagInfos.isEmpty {
                    tagsSection
                        .padding(.horizontal, 16)
                }

                foldersSectionContent

                #if os(macOS)
                mapViewAndTrashSection
                    .padding(.horizontal, 16)
                #endif

                if !viewModel.isLoading && viewModel.fileTree.isEmpty {
                    emptyState
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 68)
        }
        #endif
        #if os(macOS)
        .searchable(text: $searchQuery, prompt: Text(String(localized: "Search notes, tags…", bundle: .module)))
        #endif
        .onChange(of: searchQuery) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                viewModel.searchText = newValue
            }
        }
        #if os(iOS)
        .overlay(alignment: .bottom) { iosFloatingSearchBar }
        #endif
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .quartzMaterialBackground(cornerRadius: 0)
            }
        }
        .alert(String(localized: "New Folder", bundle: .module), isPresented: $showNewFolderDialog) {
            TextField(String(localized: "Folder name", bundle: .module), text: $newItemName)
            Button(String(localized: "Create", bundle: .module)) {
                guard let parent = newItemParent else { return }
                let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                newItemName = ""
                guard !name.isEmpty else { return }
                Task { await viewModel.createFolder(named: name, in: parent) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { newItemName = "" }
        }
        .alert(String(localized: "New Note", bundle: .module), isPresented: $showNewNoteDialog) {
            TextField(String(localized: "Note name", bundle: .module), text: $newItemName)
            Button(String(localized: "Create", bundle: .module)) {
                guard let parent = newItemParent else { return }
                let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                let template = selectedTemplate
                newItemName = ""
                guard !name.isEmpty else { return }
                Task {
                    if template == .blank {
                        await viewModel.createNote(named: name, in: parent)
                    } else {
                        await viewModel.createNoteFromTemplate(template, named: name, in: parent)
                    }
                    let noteURL = parent.appending(path: "\(name.hasSuffix(".md") ? name : "\(name).md")")
                    selectedNoteURL = noteURL
                }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { newItemName = "" }
        }
        .confirmationDialog(
            String(localized: "Delete this item?", bundle: .module),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                guard let url = pendingDeleteURL else { return }
                if pendingDeleteIsNote, selectedNoteURL == url { selectedNoteURL = nil }
                deletionTrigger.toggle()
                Task { await viewModel.delete(at: url) }
                pendingDeleteURL = nil
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingDeleteURL = nil }
        } message: {
            Text(String(localized: "This action cannot be undone.", bundle: .module))
        }
        .alert(
            String(localized: "Error", bundle: .module),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) {}
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTag)
        .sensoryFeedback(.warning, trigger: deletionTrigger)
        .task { viewModel.collectTags() }
        .sheet(isPresented: $showMoveToFolderSheet) { moveToFolderSheet }
    }

    private var moveToFolderSheet: some View {
        NavigationStack {
            List {
                if let root = viewModel.vaultRootURL, let source = moveSourceURL {
                    if source.deletingLastPathComponent() != root {
                        Button {
                            Task { await viewModel.move(at: source, to: root) }
                            moveSourceURL = nil
                            showMoveToFolderSheet = false
                        } label: {
                            Label(String(localized: "Notes (root)", bundle: .module), systemImage: "folder.fill")
                        }
                    }
                    ForEach(collectValidMoveDestinations(from: viewModel.fileTree, sourceURL: source, root: root), id: \.url) { folder in
                        Button {
                            Task { await viewModel.move(at: source, to: folder.url) }
                            moveSourceURL = nil
                            showMoveToFolderSheet = false
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Move to folder", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        moveSourceURL = nil
                        showMoveToFolderSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 300)
    }

    private func collectValidMoveDestinations(from nodes: [FileNode], sourceURL: URL, root: URL) -> [FileNode] {
        var result: [FileNode] = []
        let sourcePath = sourceURL.path(percentEncoded: false)
        for node in nodes where node.isFolder {
            let folderPath = node.url.path(percentEncoded: false)
            guard folderPath != sourcePath else { continue }
            guard !folderPath.hasPrefix(sourcePath + "/") else { continue }
            result.append(node)
            if let children = node.children {
                result.append(contentsOf: collectValidMoveDestinations(from: children, sourceURL: sourceURL, root: root))
            }
        }
        return result
    }

    #if os(iOS)
    private var iosFloatingSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search notes, tags…", bundle: .module), text: $searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .quartzMaterialBackground(cornerRadius: 16, shadowRadius: 12, preferRegularMaterial: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    #endif

    // MARK: - New Note Button (44pt HIG)

    private static let navyButton = Color(hex: 0x1E3A5F)

    private var newNoteButtonFill: some ShapeStyle {
        #if os(macOS)
        Self.navyButton
        #else
        appearance.accentColor.gradient
        #endif
    }

    private var newNoteButton: some View {
        Menu {
            ForEach(NoteTemplate.allCases, id: \.rawValue) { template in
                Button {
                    if let root = viewModel.vaultRootURL {
                        newItemParent = root
                        newItemName = generateNoteName()
                        selectedTemplate = template
                        showNewNoteDialog = true
                    }
                } label: {
                    Label(template.displayName, systemImage: template.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: newNoteButtonIconSize, weight: .bold))
                Text(String(localized: "New Note", bundle: .module))
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(newNoteButtonFill)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            )
            .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
    }

    private func generateNoteName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH-mm"
        return "Note \(df.string(from: Date()))"
    }

    // MARK: - Quick Access

    private static let quickAccessRowSpacing: CGFloat = 0
    private static let sectionHeaderBottomPadding: CGFloat = 6

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: Self.quickAccessRowSpacing) {
            Text(String(localized: "Quick Access", bundle: .module))
                .font(sidebarSectionFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.bottom, Self.sectionHeaderBottomPadding)

            #if os(macOS)
            dashboardRow
            #endif
            quickAccessRow(icon: "folder.fill", iconColor: appearance.accentColor, label: String(localized: "All Notes", bundle: .module), filter: .all)
            quickAccessRow(icon: "star.fill", iconColor: .yellow, label: String(localized: "Favorites", bundle: .module), filter: .favorites)
            quickAccessRow(icon: "clock.fill", iconColor: .secondary, label: String(localized: "Recent", bundle: .module), filter: .recent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    #if os(macOS)
    private var dashboardRow: some View {
        Button {
            selectedNoteURL = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: sidebarIconSize, weight: .medium))
                    .foregroundStyle(QuartzColors.accent)
                    .frame(width: sidebarIconSize + 4)
                Text(String(localized: "Dashboard", bundle: .module))
                    .font(.body)
                Spacer()
                if selectedNoteURL == nil {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appearance.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedNoteURL == nil ? appearance.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    private func quickAccessRow(icon: String, iconColor: Color, label: String, filter: SidebarFilter) -> some View {
        Button {
            withAnimation(QuartzAnimation.standard) {
                viewModel.activeFilter = filter
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: sidebarIconSize, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: sidebarIconSize + 4)
                Text(label)
                    .font(.body)
                Spacer()
                if viewModel.activeFilter == filter {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appearance.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            #if os(iOS)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(viewModel.activeFilter == filter ? appearance.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Self.quickAccessRowSpacing) {
            HStack {
                Text(String(localized: "Tags", bundle: .module))
                    .font(sidebarSectionFont)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if viewModel.selectedTag != nil {
                    Button(String(localized: "Clear", bundle: .module)) {
                        withAnimation { viewModel.selectedTag = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(appearance.accentColor)
                }
            }
            .padding(.bottom, Self.sectionHeaderBottomPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.tagInfos.prefix(12)) { tag in
                        Button {
                            withAnimation(QuartzAnimation.standard) {
                                viewModel.selectedTag = viewModel.selectedTag == tag.name ? nil : tag.name
                            }
                        } label: {
                            QuartzTagBadge(text: tag.name, isSelected: viewModel.selectedTag == tag.name)
                        }
                        .buttonStyle(QuartzBounceButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Folders Section (ADA Drag & Drop)

    private var foldersSectionContent: some View {
        Group {
            if !viewModel.fileTree.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    foldersSectionHeader

                    SidebarTreeView(
                        nodes: viewModel.filteredTree,
                        selectedNoteURL: $selectedNoteURL,
                        dropTargetURL: $dropTargetURL,
                        dragExpandedFolderURLs: $dragExpandedFolderURLs,
                        insertionIndicator: $insertionIndicator,
                        appearance: appearance,
                        onDrop: { urls, folder in handleDrop(urls: urls, onto: folder) },
                        onSelectNote: { selectedNoteURL = $0 },
                        onDeleteNote: {
                            pendingDeleteURL = $0
                            pendingDeleteIsNote = true
                            showDeleteConfirmation = true
                        },
                        onDeleteFolder: {
                            pendingDeleteURL = $0
                            pendingDeleteIsNote = false
                            showDeleteConfirmation = true
                        },
                        onNewNote: {
                            newItemParent = $0
                            newItemName = generateNoteName()
                            showNewNoteDialog = true
                        },
                        onNewFolder: {
                            newItemParent = $0
                            newItemName = ""
                            showNewFolderDialog = true
                        },
                        onMoveToFolder: {
                            moveSourceURL = $0
                            showMoveToFolderSheet = true
                        },
                        vaultRootURL: viewModel.vaultRootURL,
                        viewModel: viewModel
                    )
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var foldersSectionHeader: some View {
        HStack {
            Text(String(localized: "Folders", bundle: .module))
                .font(sidebarSectionFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Menu {
                ForEach(SidebarSortOrder.allCases, id: \.rawValue) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.label)
                            if viewModel.sortOrder == order { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button {
                    if let root = viewModel.vaultRootURL {
                        newItemParent = root
                        newItemName = ""
                        showNewFolderDialog = true
                    }
                } label: {
                    Label(String(localized: "New Folder", bundle: .module), systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(minWidth: QuartzHIG.minTouchTarget, minHeight: QuartzHIG.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dropTargetURL == viewModel.vaultRootURL ? appearance.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(dropTargetURL == viewModel.vaultRootURL ? appearance.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: SidebarItemTransferable.self) { items, _ in
            guard let root = viewModel.vaultRootURL else { return false }
            dropTargetURL = nil
            dragExpandedFolderURLs = []
            insertionIndicator = nil
            var moved = false
            for sourceURL in items.map(\.url) {
                guard sourceURL.deletingLastPathComponent() != root else { continue }
                Task { await viewModel.move(at: sourceURL, to: root) }
                moved = true
            }
            return moved
        } isTargeted: { targeted in
            dropTargetURL = targeted ? viewModel.vaultRootURL : (dropTargetURL == viewModel.vaultRootURL ? nil : dropTargetURL)
        }
    }

    #if os(macOS)
    private var mapViewAndTrashSection: some View {
        VStack(alignment: .leading, spacing: Self.quickAccessRowSpacing) {
            Button { onMapViewTap?() } label: {
                Label(String(localized: "Map View", bundle: .module), systemImage: "map")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
            }
            .buttonStyle(.plain)

            Button {} label: {
                Label(String(localized: "Trash", bundle: .module), systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.quaternary)
            Text(String(localized: "No Notes Yet", bundle: .module))
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Create your first note to get started.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func handleDrop(urls: [URL], onto folder: FileNode) -> Bool {
        guard folder.isFolder else { return false }
        var moved = false
        for sourceURL in urls {
            guard sourceURL != folder.url else { continue }
            let folderPath = folder.url.path(percentEncoded: false)
            let sourcePath = sourceURL.path(percentEncoded: false)
            guard !folderPath.hasPrefix(sourcePath + "/") else { continue }
            Task { await viewModel.move(at: sourceURL, to: folder.url) }
            moved = true
        }
        return moved
    }
}

// MARK: - Sidebar Tree View (ADA Drag & Drop)

private struct SidebarTreeView: View {
    let nodes: [FileNode]
    @Binding var selectedNoteURL: URL?
    @Binding var dropTargetURL: URL?
    @Binding var dragExpandedFolderURLs: Set<URL>
    @Binding var insertionIndicator: (parent: URL, index: Int)?
    let appearance: AppearanceManager
    let onDrop: ([URL], FileNode) -> Bool
    let onSelectNote: (URL) -> Void
    let onDeleteNote: (URL) -> Void
    let onDeleteFolder: (URL) -> Void
    let onNewNote: (URL) -> Void
    let onNewFolder: (URL) -> Void
    let onMoveToFolder: (URL) -> Void
    let vaultRootURL: URL?
    let viewModel: SidebarViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                SidebarTreeNode(
                    node: node,
                    depth: 0,
                    index: index,
                    selectedNoteURL: $selectedNoteURL,
                    dropTargetURL: $dropTargetURL,
                    dragExpandedFolderURLs: $dragExpandedFolderURLs,
                    insertionIndicator: $insertionIndicator,
                    appearance: appearance,
                    onDrop: onDrop,
                    onSelectNote: onSelectNote,
                    onDeleteNote: onDeleteNote,
                    onDeleteFolder: onDeleteFolder,
                    onNewNote: onNewNote,
                    onNewFolder: onNewFolder,
                    onMoveToFolder: onMoveToFolder,
                    vaultRootURL: vaultRootURL,
                    viewModel: viewModel
                )
            }
        }
    }
}

private struct SidebarTreeNode: View {
    let node: FileNode
    let depth: Int
    let index: Int
    @Binding var selectedNoteURL: URL?
    @Binding var dropTargetURL: URL?
    @Binding var dragExpandedFolderURLs: Set<URL>
    @Binding var insertionIndicator: (parent: URL, index: Int)?
    let appearance: AppearanceManager
    let onDrop: ([URL], FileNode) -> Bool
    let onSelectNote: (URL) -> Void
    let onDeleteNote: (URL) -> Void
    let onDeleteFolder: (URL) -> Void
    let onNewNote: (URL) -> Void
    let onNewFolder: (URL) -> Void
    let onMoveToFolder: (URL) -> Void
    let vaultRootURL: URL?
    let viewModel: SidebarViewModel

    @State private var isExpanded: Bool = true

    private var isDropTarget: Bool { dropTargetURL == node.url }
    private var isDragExpanded: Bool { node.isFolder && dragExpandedFolderURLs.contains(node.url) }
    private var effectiveExpanded: Bool { isExpanded || isDragExpanded }

    var body: some View {
        if node.isFolder, let children = node.children {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(Array(children.enumerated()), id: \.element.id) { childIndex, child in
                    SidebarTreeNode(
                        node: child,
                        depth: depth + 1,
                        index: childIndex,
                        selectedNoteURL: $selectedNoteURL,
                        dropTargetURL: $dropTargetURL,
                        dragExpandedFolderURLs: $dragExpandedFolderURLs,
                        insertionIndicator: $insertionIndicator,
                        appearance: appearance,
                        onDrop: onDrop,
                        onSelectNote: onSelectNote,
                        onDeleteNote: onDeleteNote,
                        onDeleteFolder: onDeleteFolder,
                        onNewNote: onNewNote,
                        onNewFolder: onNewFolder,
                        onMoveToFolder: onMoveToFolder,
                        vaultRootURL: vaultRootURL,
                        viewModel: viewModel
                    )
                }
                .padding(.leading, 16)
            } label: {
                folderRow
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDropTarget ? appearance.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isDropTarget ? appearance.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                dropTargetURL = nil
                dragExpandedFolderURLs = []
                insertionIndicator = nil
                return onDrop(items.map(\.url), node)
            } isTargeted: { targeted in
                if targeted {
                    dropTargetURL = node.url
                    if node.isFolder { dragExpandedFolderURLs.insert(node.url) }
                } else if dropTargetURL == node.url {
                    dropTargetURL = nil
                    dragExpandedFolderURLs.remove(node.url)
                }
            }
            .draggable(SidebarItemTransferable(url: node.url))
            .contextMenu { folderContextMenu(for: node) }
            .animation(QuartzAnimation.standard, value: isDropTarget)
            .animation(QuartzAnimation.content, value: effectiveExpanded)
        } else if node.isFolder {
            folderRow
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(minHeight: QuartzHIG.minTouchTarget)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDropTarget ? appearance.accentColor.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isDropTarget ? appearance.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
                )
                .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                    dropTargetURL = nil
                    dragExpandedFolderURLs = []
                    insertionIndicator = nil
                    return onDrop(items.map(\.url), node)
                } isTargeted: { targeted in
                    if targeted { dropTargetURL = node.url }
                    else if dropTargetURL == node.url { dropTargetURL = nil }
                }
                .draggable(SidebarItemTransferable(url: node.url))
                .contextMenu { folderContextMenu(for: node) }
        } else if node.isNote {
            Button {
                onSelectNote(node.url)
            } label: {
                FileNodeRow(node: node)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            #if os(iOS)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedNoteURL == node.url ? appearance.accentColor.opacity(0.1) : Color.clear)
            )
            .draggable(SidebarItemTransferable(url: node.url))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { onDeleteNote(node.url) } label: {
                    Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                }
            }
            .contextMenu { noteContextMenu(for: node) }
        } else {
            FileNodeRow(node: node)
        }
    }

    private var folderRow: some View {
        FileNodeRow(node: node)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func folderContextMenu(for node: FileNode) -> some View {
        Button {
            onNewNote(node.url)
        } label: {
            Label(String(localized: "New Note", bundle: .module), systemImage: "doc.badge.plus")
        }
        Button {
            onNewFolder(node.url)
        } label: {
            Label(String(localized: "New Folder", bundle: .module), systemImage: "folder.badge.plus")
        }
        Divider()
        Button {
            onMoveToFolder(node.url)
        } label: {
            Label(String(localized: "Move to folder…", bundle: .module), systemImage: "folder.badge.arrow.right")
        }
        Divider()
        Button(role: .destructive) {
            onDeleteFolder(node.url)
        } label: {
            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func noteContextMenu(for node: FileNode) -> some View {
        Button {
            viewModel.toggleFavorite(node.url)
        } label: {
            Label(
                viewModel.isFavorite(node.url)
                    ? String(localized: "Remove from Favorites", bundle: .module)
                    : String(localized: "Add to Favorites", bundle: .module),
                systemImage: viewModel.isFavorite(node.url) ? "star.slash" : "star"
            )
        }
        Button {
            onMoveToFolder(node.url)
        } label: {
            Label(String(localized: "Move to folder…", bundle: .module), systemImage: "folder.badge.arrow.right")
        }
        Divider()
        Button(role: .destructive) {
            onDeleteNote(node.url)
        } label: {
            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
        }
    }
}
