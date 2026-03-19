import SwiftUI
import UniformTypeIdentifiers

/// Transferable wrapper for sidebar items. Using URL.self directly in dropDestination fails on iOS;
/// a custom Transferable with CodableRepresentation works on both platforms.
private struct SidebarItemTransferable: Transferable, Codable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Section header font – larger on macOS.
private var sidebarSectionFont: Font {
    #if os(macOS)
    .callout.weight(.bold)
    #else
    .subheadline.weight(.bold)
    #endif
}

/// New Note button icon size – larger on macOS.
private var newNoteButtonIconSize: CGFloat {
    #if os(macOS)
    17
    #else
    15
    #endif
}

/// Quick access / folder icon size – larger on macOS.
private var sidebarIconSize: CGFloat {
    #if os(macOS)
    22
    #else
    20
    #endif
}

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

    public init(viewModel: SidebarViewModel, selectedNoteURL: Binding<URL?>, onMapViewTap: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self._selectedNoteURL = selectedNoteURL
        self.onMapViewTap = onMapViewTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                newNoteButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // Single scrollable layout: List breaks dropDestination when source and target are in same List (SwiftUI bug).
                // Everything in one ScrollView for correct scrolling; folder tree outside List for drag & drop.
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
        }
        #if os(iOS)
        .overlay(alignment: .bottom) {
            iosFloatingSearchBar
        }
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
    }

    #if os(iOS)
    /// Floating search bar at bottom with liquid glass styling.
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

    // MARK: - New Note Button

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

    private var quickAccessSection: some View {
        Section {
            #if os(macOS)
            dashboardRow
            #endif
            quickAccessRow(
                icon: "folder.fill",
                iconColor: appearance.accentColor,
                label: String(localized: "All Notes", bundle: .module),
                filter: .all
            )
            quickAccessRow(
                icon: "star.fill",
                iconColor: .yellow,
                label: String(localized: "Favorites", bundle: .module),
                filter: .favorites
            )
            quickAccessRow(
                icon: "clock.fill",
                iconColor: .secondary,
                label: String(localized: "Recent", bundle: .module),
                filter: .recent
            )
        } header: {
            Text(String(localized: "Quick Access", bundle: .module))
                .font(sidebarSectionFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
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
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedNoteURL == nil
                ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appearance.accentColor.opacity(0.1))
                : nil
        )
    }
    #endif

    private func quickAccessRow(icon: String, iconColor: Color, label: String, filter: SidebarFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
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
        }
        .buttonStyle(.plain)
        .listRowBackground(
            viewModel.activeFilter == filter
                ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appearance.accentColor.opacity(0.1))
                : nil
        )
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        Section {
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
        } header: {
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
        }
    }

    // MARK: - Folders Section (outside List for drag & drop – List breaks dropDestination)

    private var foldersSectionContent: some View {
        Group {
            if !viewModel.fileTree.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "Folders", bundle: .module))
                        .font(sidebarSectionFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                            guard let root = viewModel.vaultRootURL else { return false }
                            var moved = false
                            for sourceURL in items.map(\.url) {
                                guard sourceURL.deletingLastPathComponent() != root else { continue }
                                Task { await viewModel.move(at: sourceURL, to: root) }
                                moved = true
                            }
                            return moved
                        } isTargeted: { _ in }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.filteredTree) { node in
                            nodeView(for: node)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Map View & Trash (macOS)

    #if os(macOS)
    private var mapViewAndTrashSection: some View {
        Section {
            Button {
                onMapViewTap?()
            } label: {
                Label(String(localized: "Map View", bundle: .module), systemImage: "map")
            }
            .buttonStyle(.plain)

            Button {
                // Trash – future: show deleted notes
            } label: {
                Label(String(localized: "Trash", bundle: .module), systemImage: "trash")
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // MARK: - Empty State

    private var emptyState: some View {
        Section {
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
    }

    // MARK: - Node View

    @ViewBuilder
    private func nodeView(for node: FileNode) -> some View {
        if node.isFolder, let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    AnyView(nodeView(for: child))
                }
            }             label: {
                FileNodeRow(node: node)
                    .contentShape(Rectangle())
                    .draggable(SidebarItemTransferable(url: node.url))
            }
            .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                handleDrop(urls: items.map(\.url), onto: node)
            } isTargeted: { _ in }
            .contentShape(Rectangle())
            .contextMenu { folderContextMenu(for: node) }
        } else if node.isNote {
            Button {
                selectedNoteURL = node.url
            } label: {
                FileNodeRow(node: node)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedNoteURL == node.url ? appearance.accentColor.opacity(0.1) : Color.clear)
            )
            .draggable(SidebarItemTransferable(url: node.url))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        pendingDeleteURL = node.url
                        pendingDeleteIsNote = true
                        showDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                    }
                }
                .contextMenu { noteContextMenu(for: node) }
        } else {
            FileNodeRow(node: node)
        }
    }

    private func handleDrop(urls: [URL], onto folder: FileNode) -> Bool {
        guard folder.isFolder else { return false }
        var moved = false
        for sourceURL in urls {
            guard sourceURL != folder.url else { continue }
            // Don't drop a folder into itself or a parent into its descendant
            let folderPath = folder.url.path(percentEncoded: false)
            let sourcePath = sourceURL.path(percentEncoded: false)
            guard !folderPath.hasPrefix(sourcePath + "/") else { continue }
            Task {
                await viewModel.move(at: sourceURL, to: folder.url)
            }
            moved = true
        }
        return moved
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func folderContextMenu(for node: FileNode) -> some View {
        Button {
            newItemParent = node.url
            newItemName = generateNoteName()
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
            pendingDeleteURL = node.url
            pendingDeleteIsNote = false
            showDeleteConfirmation = true
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
        Divider()
        Button(role: .destructive) {
            pendingDeleteURL = node.url
            pendingDeleteIsNote = true
            showDeleteConfirmation = true
        } label: {
            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
        }
    }
}
