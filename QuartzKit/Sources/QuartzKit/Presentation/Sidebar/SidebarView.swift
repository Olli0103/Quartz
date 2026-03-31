import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Custom UTType for Sidebar Drag

extension UTType {
    /// Custom UTType for sidebar drag-and-drop items — declared in Info.plist.
    static let quartzSidebarItem = UTType(exportedAs: "olli.QuartzNotes.sidebar-item")
}

// MARK: - Transferable for Drag & Drop

/// Transferable wrapper for sidebar drag and drop.
/// Uses a custom UTType to avoid conflicts with iOS text system drag handling.
public struct SidebarItemTransferable: Transferable, Codable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .quartzSidebarItem)
        // Fallback: plain text for cross-app compatibility (e.g., Finder on macOS)
        DataRepresentation(contentType: .plainText) { item in
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

// MARK: - Design Constants

private var sidebarSectionFont: Font {
    #if os(macOS)
    .callout.weight(.bold)
    #else
    .subheadline.weight(.bold)
    #endif
}

private enum NewNoteCTA {
    static let cornerRadius: CGFloat = 18
    static let minHeight: CGFloat = 54
    static let plusSize: CGFloat = 21
}

private var sidebarIconSize: CGFloat {
    #if os(macOS)
    16
    #else
    15
    #endif
}

// MARK: - SidebarView

/// Native sidebar using Apple's recommended patterns:
/// - `List(selection:)` for native selection behavior
/// - `OutlineGroup` for hierarchical file tree
/// - `NavigationLink(value:)` for selectable items
/// - No manual tap gestures on rows
///
/// References:
/// - WWDC 2022 "The SwiftUI Cookbook for Navigation"
/// - See docs/research/list-selection-patterns.md
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?
    var onMapViewTap: (() -> Void)?
    var onDoubleClick: ((URL) -> Void)?
    var onSourceChanged: ((SourceSelection) -> Void)?
    var onVaultChat: (() -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onDashboard: (() -> Void)?
    var onSwitchVault: (() -> Void)?

    @Environment(\.appearanceManager) private var appearance
    @State private var showNewFolderDialog = false
    @State private var showNewNoteDialog = false
    @State private var showRenameDialog = false
    @State private var newItemName: String = ""
    @State private var newItemParent: URL?
    @State private var renameTargetURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteURL: URL?
    @State private var pendingDeleteIsNote = false
    @State private var searchQuery: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedTemplate: NoteTemplate = .blank
    @State private var dropTargetURL: URL?
    @State private var moveSourceURL: MoveTarget?
    // showMoveToFolderSheet removed — using sheet(item: $moveSourceURL) instead
    @ScaledMetric(relativeTo: .caption) private var tagsChipRowVerticalPadding: CGFloat = 4
    #if os(macOS)
    @State private var newNoteButtonHovered = false
    @Environment(\.openWindow) private var openWindow
    #endif

    private static let sidebarListRowInsets = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

    public init(
        viewModel: SidebarViewModel,
        selectedNoteURL: Binding<URL?>,
        onMapViewTap: (() -> Void)? = nil,
        onDoubleClick: ((URL) -> Void)? = nil,
        onSourceChanged: ((SourceSelection) -> Void)? = nil,
        onVaultChat: (() -> Void)? = nil,
        onSearchChanged: ((String) -> Void)? = nil,
        onDashboard: (() -> Void)? = nil,
        onSwitchVault: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._selectedNoteURL = selectedNoteURL
        self.onMapViewTap = onMapViewTap
        self.onDoubleClick = onDoubleClick
        self.onSourceChanged = onSourceChanged
        self.onVaultChat = onVaultChat
        self.onSearchChanged = onSearchChanged
        self.onDashboard = onDashboard
        self.onSwitchVault = onSwitchVault
    }

    public var body: some View {
        VStack(spacing: 0) {

            // Native List with selection binding - SwiftUI handles selection automatically
            List(selection: $selectedNoteURL) {
                Section {
                    quickAccessSection
                        .listRowInsets(Self.sidebarListRowInsets)
                        .listRowBackground(Color.clear)
                }

                if !viewModel.tagInfos.isEmpty {
                    Section {
                        tagsSection
                            .listRowInsets(Self.sidebarListRowInsets)
                            .listRowBackground(Color.clear)
                    }
                }

                if !viewModel.fileTree.isEmpty {
                    Section {
                        fileTreeContent
                    } header: {
                        foldersSectionHeader
                    }
                } else if !viewModel.isLoading {
                    Section {
                        emptyState
                            .listRowInsets(Self.sidebarListRowInsets)
                            .listRowBackground(Color.clear)
                    }
                }

                if !viewModel.trashedItems.isEmpty {
                    Section {
                        recentlyDeletedSection
                            .listRowInsets(Self.sidebarListRowInsets)
                            .listRowBackground(Color.clear)
                    }
                }

                #if os(macOS)
                Section {
                    mapViewAndTrashSection
                        .listRowInsets(Self.sidebarListRowInsets)
                        .listRowBackground(Color.clear)
                }
                #endif
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 68)
        }
        .onChange(of: selectedNoteURL) { oldURL, newURL in
            // When a note is tapped in the sidebar tree, update the source to its parent folder
            // so the note list shows the right context. Skip if URL didn't actually change
            // (avoids cascading reloads from the note list's own selection binding).
            guard let url = newURL, oldURL != newURL else { return }
            let parentURL = url.deletingLastPathComponent()
            onSourceChanged?(.folder(parentURL))
        }
        .onChange(of: searchQuery) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                viewModel.searchText = newValue
                onSearchChanged?(newValue)
            }
        }
        .overlay(alignment: .bottom) { floatingSearchBar }
        #if os(iOS)
        .overlay(alignment: .bottomTrailing) {
            iOSNewNoteButton
                .padding(.trailing, 16)
                .padding(.bottom, 72) // above the search bar
        }
        #endif
        .overlay(alignment: .bottom) {
            if let progress = viewModel.indexingProgress {
                indexingStatusBar(current: progress.current, total: progress.total)
            }
        }
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
                QuartzFeedback.primaryAction()
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
                QuartzFeedback.primaryAction()
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
            String(localized: "Move to Trash?", bundle: .module),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Move to Trash", bundle: .module), role: .destructive) {
                guard let url = pendingDeleteURL else { return }
                if pendingDeleteIsNote, selectedNoteURL == url { selectedNoteURL = nil }
                QuartzFeedback.destructive()
                Task { await viewModel.delete(at: url) }
                pendingDeleteURL = nil
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { pendingDeleteURL = nil }
        } message: {
            Text(String(localized: "The item will be moved to Trash. You can restore it from Trash later.", bundle: .module))
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
        .alert(String(localized: "Rename", bundle: .module), isPresented: $showRenameDialog) {
            TextField(String(localized: "New name", bundle: .module), text: $newItemName)
            Button(String(localized: "Rename", bundle: .module)) {
                guard let url = renameTargetURL else { return }
                let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                newItemName = ""
                renameTargetURL = nil
                guard !name.isEmpty else { return }
                QuartzFeedback.primaryAction()
                Task { await viewModel.rename(at: url, to: name) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                newItemName = ""
                renameTargetURL = nil
            }
        }
        .task { viewModel.collectTags() }
        .sheet(item: $moveSourceURL) { sourceURL in
            moveToFolderSheet(source: sourceURL)
        }
    }

    // MARK: - File Tree Content (OutlineGroup)

    /// Uses OutlineGroup for hierarchical display with native selection support.
    /// Notes use `.tag()` to participate in `List(selection:)` binding.
    /// No NavigationLink needed - we manually manage detail column via onChange.
    ///
    /// Reference: WWDC 2022 "The SwiftUI Cookbook for Navigation"
    @ViewBuilder
    private var fileTreeContent: some View {
        OutlineGroup(viewModel.filteredTree, children: \.children) { node in
            if node.isNote {
                // Notes are selectable via custom listRowBackground (no .tag to avoid system highlight)
                FileNodeRow(node: node)
                    .tag(node.url)
                    #if os(macOS)
                    .background(TableViewSelectionRemover())
                    #endif
                    .draggable(SidebarItemTransferable(url: node.url)) {
                        Label(node.name, systemImage: "doc.text")
                            .padding(8)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                    }
                    .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                        handleDrop(items: items, onto: node.url.deletingLastPathComponent())
                    } isTargeted: { targeted in
                        dropTargetURL = targeted ? node.url : nil
                    }
                    .contextMenu { noteContextMenu(for: node) }
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            viewModel.toggleFavorite(node.url)
                            QuartzFeedback.toggle()
                        } label: {
                            Label(
                                viewModel.isFavorite(node.url)
                                    ? String(localized: "Unfavorite", bundle: .module)
                                    : String(localized: "Favorite", bundle: .module),
                                systemImage: viewModel.isFavorite(node.url) ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)

                        Button(role: .destructive) {
                            pendingDeleteURL = node.url
                            pendingDeleteIsNote = true
                            showDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                        }
                    }
                    #endif
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(noteRowFill(for: node.url))
                    )
            } else {
                // Folders are not selectable but can be drag targets
                FileNodeRow(node: node)
                    #if os(macOS)
                    .background(TableViewSelectionRemover())
                    #endif
                    .draggable(SidebarItemTransferable(url: node.url))
                    .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                        handleDrop(items: items, onto: node.url)
                    } isTargeted: { targeted in
                        dropTargetURL = targeted ? node.url : nil
                    }
                    .contextMenu { folderContextMenu(for: node) }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(dropTargetURL == node.url ? appearance.accentColor.opacity(0.14) : Color.clear)
                    )
            }
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(items: [SidebarItemTransferable], onto folderURL: URL) -> Bool {
        dropTargetURL = nil

        let validURLs = items.map(\.url).filter { sourceURL in
            guard sourceURL != folderURL else { return false }
            let folderPath = folderURL.path(percentEncoded: false)
            let sourcePath = sourceURL.path(percentEncoded: false)
            guard !folderPath.hasPrefix(sourcePath + "/") else { return false }
            return true
        }

        guard !validURLs.isEmpty else { return false }

        QuartzFeedback.selection()

        Task {
            var successCount = 0
            for sourceURL in validURLs {
                if await viewModel.move(at: sourceURL, to: folderURL) {
                    successCount += 1
                }
            }
            if successCount > 0 {
                await MainActor.run { QuartzFeedback.success() }
            }
        }

        return true
    }

    // MARK: - Row Backgrounds

    private func noteRowBackground(for url: URL) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(noteRowFill(for: url))
    }

    private func noteRowFill(for url: URL) -> Color {
        if dropTargetURL == url { return appearance.accentColor.opacity(0.14) }
        if selectedNoteURL == url { return appearance.accentColor.opacity(0.12) }
        return .clear
    }

    private func folderRowBackground(for url: URL) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(dropTargetURL == url ? appearance.accentColor.opacity(0.14) : Color.clear)
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func noteContextMenu(for node: FileNode) -> some View {
        #if os(macOS)
        Button {
            QuartzFeedback.selection()
            selectedNoteURL = node.url
        } label: {
            Label(String(localized: "Open", bundle: .module), systemImage: "doc.text")
        }
        Button {
            onDoubleClick?(node.url)
        } label: {
            Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow")
        }
        Divider()
        #endif
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
            QuartzFeedback.primaryAction()
            renameTargetURL = node.url
            newItemName = node.url.deletingPathExtension().lastPathComponent
            showRenameDialog = true
        } label: {
            Label(String(localized: "Rename", bundle: .module), systemImage: "pencil")
        }
        Button {
            QuartzFeedback.primaryAction()
            moveSourceURL = MoveTarget(url: node.url)
        } label: {
            Label(String(localized: "Move to folder…", bundle: .module), systemImage: "folder")
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

    @ViewBuilder
    private func folderContextMenu(for node: FileNode) -> some View {
        Button {
            QuartzFeedback.primaryAction()
            newItemParent = node.url
            newItemName = generateNoteName()
            showNewNoteDialog = true
        } label: {
            Label(String(localized: "New Note", bundle: .module), systemImage: "doc.badge.plus")
        }
        Button {
            QuartzFeedback.primaryAction()
            newItemParent = node.url
            newItemName = ""
            showNewFolderDialog = true
        } label: {
            Label(String(localized: "New Folder", bundle: .module), systemImage: "folder.badge.plus")
        }
        Divider()
        Button {
            QuartzFeedback.primaryAction()
            renameTargetURL = node.url
            newItemName = node.url.lastPathComponent
            showRenameDialog = true
        } label: {
            Label(String(localized: "Rename", bundle: .module), systemImage: "pencil")
        }
        Button {
            QuartzFeedback.primaryAction()
            moveSourceURL = MoveTarget(url: node.url)
        } label: {
            Label(String(localized: "Move to folder…", bundle: .module), systemImage: "folder")
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

    // MARK: - Move to Folder Sheet

    private func moveToFolderSheet(source: MoveTarget) -> some View {
        NavigationStack {
            List {
                if let root = viewModel.vaultRootURL {
                    Button {
                        QuartzFeedback.primaryAction()
                        Task { await viewModel.move(at: source.url, to: root) }
                        moveSourceURL = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Notes (root)", bundle: .module))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    let folders = collectValidMoveDestinations(from: viewModel.fileTree, sourceURL: source.url, root: root)
                    ForEach(folders, id: \.url) { folder in
                        Button {
                            QuartzFeedback.primaryAction()
                            Task { await viewModel.move(at: source.url, to: folder.url) }
                            moveSourceURL = nil
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                Text(folder.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if folders.isEmpty {
                        Text(String(localized: "No subfolders yet. Create a folder first.", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.secondary)
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

    // MARK: - Indexing Status Bar

    private func indexingStatusBar(current: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(current), total: Double(max(1, total)))
                .progressViewStyle(.linear)
                .tint(appearance.accentColor)

            Text("\(current)/\(total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .quartzFloatingPill()
        .padding(.horizontal, 16)
        .padding(.bottom, 60) // above the search bar
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(QuartzAnimation.status, value: total)
    }

    // MARK: - Floating Search Bar

    private var floatingSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search notes, tags\u{2026}", bundle: .module), text: $searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .quartzFloatingPill()
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - New Note Button

    private var newNoteButton: some View {
        Menu {
            ForEach(NoteTemplate.allCases, id: \.rawValue) { template in
                Button {
                    QuartzFeedback.primaryAction()
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
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: NewNoteCTA.plusSize, weight: .bold))
                Text(String(localized: "New Note", bundle: .module))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.92)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 17)
            .frame(minHeight: NewNoteCTA.minHeight)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: NewNoteCTA.cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    appearance.accentColor,
                                    appearance.accentColor.opacity(0.68),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: NewNoteCTA.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(appearance.vibrantTransparency ? 0.45 : 0.28)
                    RoundedRectangle(cornerRadius: NewNoteCTA.cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                    RoundedRectangle(cornerRadius: NewNoteCTA.cornerRadius, style: .continuous)
                        .strokeBorder(appearance.accentColor.opacity(0.55), lineWidth: 1)
                }
            }
            .shadow(color: appearance.accentColor.opacity(0.4), radius: 20, y: 9)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(NewNoteCTAMenuButtonStyle())
        #if os(macOS)
        .scaleEffect(newNoteButtonHovered ? 1.014 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: newNoteButtonHovered)
        .onHover { newNoteButtonHovered = $0 }
        #endif
        .accessibilityLabel(String(localized: "New Note", bundle: .module))
    }

    // MARK: - iOS Floating Action Button

    #if os(iOS)
    @State private var fabPressed = false

    /// Liquid Glass floating action button for iOS — HIG-compliant circular FAB.
    private var iOSNewNoteButton: some View {
        Menu {
            ForEach(NoteTemplate.allCases, id: \.rawValue) { template in
                Button {
                    QuartzFeedback.primaryAction()
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
            ZStack {
                // Liquid Glass background
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(appearance.accentColor.gradient)
                    .opacity(0.85)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.6),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )

                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .shadow(color: appearance.accentColor.opacity(0.4), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .scaleEffect(fabPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fabPressed)
        }
        .menuStyle(.borderlessButton)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in fabPressed = true }
                .onEnded { _ in fabPressed = false }
        )
        .accessibilityLabel(String(localized: "New Note", bundle: .module))
        .accessibilityHint(String(localized: "Long press for template options", bundle: .module))
    }
    #endif

    private func generateNoteName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH-mm"
        return "Note \(df.string(from: Date()))"
    }

    // MARK: - Quick Access Section

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
            quickAccessRow(icon: "doc.text", iconColor: .primary, label: String(localized: "All Notes", bundle: .module), filter: .all)
            quickAccessRow(icon: "star", iconColor: .primary, label: String(localized: "Favorites", bundle: .module), filter: .favorites)
            quickAccessRow(icon: "clock", iconColor: .primary, label: String(localized: "Recent", bundle: .module), filter: .recent)

            if onVaultChat != nil {
                Button {
                    QuartzFeedback.primaryAction()
                    onVaultChat?()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: sidebarIconSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: sidebarIconSize + 4)
                        Text(String(localized: "Vault Chat", bundle: .module))
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
                    #endif
                }
                .buttonStyle(.plain)
            }

            if onMapViewTap != nil {
                Button {
                    QuartzFeedback.primaryAction()
                    onMapViewTap?()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.hexagongrid")
                            .font(.system(size: sidebarIconSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: sidebarIconSize + 4)
                        Text(String(localized: "Knowledge Graph", bundle: .module))
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    #if os(iOS)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
                    #endif
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    #if os(macOS)
    private var dashboardRow: some View {
        Button {
            QuartzFeedback.selection()
            selectedNoteURL = nil
            onDashboard?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: sidebarIconSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: sidebarIconSize + 4)
                Text(String(localized: "Dashboard", bundle: .module))
                    .font(.body)
                Spacer()
                if selectedNoteURL == nil {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
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
            QuartzFeedback.selection()
            withAnimation(QuartzAnimation.standard) {
                viewModel.activeFilter = filter
                viewModel.selectedTag = nil
            }
            switch filter {
            case .all: onSourceChanged?(.allNotes)
            case .favorites: onSourceChanged?(.favorites)
            case .recent: onSourceChanged?(.recent)
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
                        .foregroundStyle(.primary)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Tags", bundle: .module))
                    .font(sidebarSectionFont)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if viewModel.selectedTag != nil {
                    Button(String(localized: "Clear", bundle: .module)) {
                        QuartzFeedback.selection()
                        withAnimation { viewModel.selectedTag = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(appearance.accentColor)
                }
            }
            .padding(.bottom, Self.sectionHeaderBottomPadding)

            ForEach(viewModel.tagInfos.prefix(20)) { tag in
                tagRow(tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func tagRow(_ tag: TagInfo) -> some View {
        let isSelected = viewModel.selectedTag == tag.name
        return Button {
            QuartzFeedback.selection()
            withAnimation(QuartzAnimation.standard) {
                viewModel.selectedTag = isSelected ? nil : tag.name
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.caption)
                    .foregroundStyle(isSelected ? appearance.accentColor : .secondary)
                    .frame(width: 16)
                Text(tag.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? appearance.accentColor : .primary)
                    .lineLimit(1)
                Spacer()
                Text("\(tag.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? appearance.accentColor.opacity(0.1) : Color.clear)
        )
    }

    // MARK: - Folders Section Header

    private var foldersSectionHeader: some View {
        HStack {
            Text(String(localized: "Folders", bundle: .module))
                .font(sidebarSectionFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()

            Button {
                QuartzFeedback.primaryAction()
                if let root = viewModel.vaultRootURL {
                    newItemParent = root
                    newItemName = ""
                    showNewFolderDialog = true
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "New Folder", bundle: .module))

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
                    QuartzFeedback.primaryAction()
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
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(minWidth: QuartzHIG.minTouchTarget, minHeight: QuartzHIG.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .tint(.primary)
            .accessibilityLabel(String(localized: "More options", bundle: .module))
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
            return handleDrop(items: items, onto: root)
        } isTargeted: { targeted in
            dropTargetURL = targeted ? viewModel.vaultRootURL : (dropTargetURL == viewModel.vaultRootURL ? nil : dropTargetURL)
        }
    }

    // MARK: - macOS Extras

    #if os(macOS)
    private func openVaultTrashInFinder() {
        guard let vaultRoot = viewModel.vaultRootURL else { return }
        let trashURL = VaultTrashService().trashFolderURL(for: vaultRoot)
        do {
            _ = try VaultTrashService().ensureTrashFolderExists(at: vaultRoot)
            NSWorkspace.shared.activateFileViewerSelecting([trashURL])
        } catch {
            viewModel.errorMessage = String(localized: "Could not open the vault trash.", bundle: .module)
        }
    }

    private var mapViewAndTrashSection: some View {
        VStack(alignment: .leading, spacing: Self.quickAccessRowSpacing) {
            Divider()

            Button {
                QuartzFeedback.selection()
                onSwitchVault?()
            } label: {
                Label(String(localized: "Switch Vault…", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
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

    // MARK: - Recently Deleted

    @State private var showRecentlyDeleted = false

    private var recentlyDeletedSection: some View {
        DisclosureGroup(isExpanded: $showRecentlyDeleted) {
            ForEach(viewModel.trashedItems) { node in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: sidebarIconSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: sidebarIconSize + 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(node.metadata.modifiedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .tag(node.url)
                .contextMenu {
                    Button {
                        QuartzFeedback.primaryAction()
                        Task { await viewModel.restoreFromTrash(at: node.url) }
                    } label: {
                        Label(String(localized: "Restore", bundle: .module), systemImage: "arrow.uturn.backward")
                    }
                    Divider()
                    Button(role: .destructive) {
                        QuartzFeedback.destructive()
                        Task { await viewModel.permanentlyDelete(at: node.url) }
                    } label: {
                        Label(String(localized: "Delete Permanently", bundle: .module), systemImage: "trash.slash")
                    }
                }
            }

            if viewModel.trashedItems.count > 1 {
                Button(role: .destructive) {
                    QuartzFeedback.destructive()
                    Task { await viewModel.emptyTrash() }
                } label: {
                    Label(String(localized: "Empty Trash", bundle: .module), systemImage: "trash.slash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: sidebarIconSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: sidebarIconSize + 4)
                Text(String(localized: "Recently Deleted", bundle: .module))
                    .font(.body)
                Spacer()
                Text("\(viewModel.trashedItems.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    // MARK: - Empty State

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
}

// MARK: - Button Styles

private struct NewNoteCTAMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Move Target Wrapper

/// Identifiable wrapper for URL used by `.sheet(item:)` for move-to-folder.
private struct MoveTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
