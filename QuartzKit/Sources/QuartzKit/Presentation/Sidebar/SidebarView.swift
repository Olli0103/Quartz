import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

/// ADA-quality sidebar built on native list/outline primitives with reliable drag & drop.
public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Binding var selectedNoteURL: URL?
    var onMapViewTap: (() -> Void)?
    @Environment(\.appearanceManager) private var appearance
    @State private var showNewFolderDialog = false
    @State private var showNewNoteDialog = false
    @State private var newItemName: String = ""
    @State private var newItemParent: URL?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteURL: URL?
    @State private var pendingDeleteIsNote = false
    @State private var searchQuery: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedTemplate: NoteTemplate = .blank
    @State private var dropTargetURL: URL?
    @State private var moveSourceURL: URL?
    @State private var showMoveToFolderSheet = false
    @ScaledMetric(relativeTo: .caption) private var tagsChipRowVerticalPadding: CGFloat = 4
    #if os(macOS)
    @State private var newNoteButtonHovered = false
    #endif

    private static let sidebarListRowInsets = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

    public init(viewModel: SidebarViewModel, selectedNoteURL: Binding<URL?>, onMapViewTap: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self._selectedNoteURL = selectedNoteURL
        self.onMapViewTap = onMapViewTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            // CTA lives *outside* the List: macOS sidebar `List` rows collapse `Menu` labels to a lone SF Symbol.
            newNoteButton
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)

            List {
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
                    SidebarOutlineView(
                        nodes: viewModel.filteredTree,
                        selectedNoteURL: $selectedNoteURL,
                        dropTargetURL: $dropTargetURL,
                        appearance: appearance,
                        onDrop: { urls, folder in handleDrop(urls: urls, onto: folder) },
                        onDropSuccess: { QuartzFeedback.success() },
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
                            QuartzFeedback.primaryAction()
                            newItemParent = $0
                            newItemName = generateNoteName()
                            showNewNoteDialog = true
                        },
                        onNewFolder: {
                            QuartzFeedback.primaryAction()
                            newItemParent = $0
                            newItemName = ""
                            showNewFolderDialog = true
                        },
                        onMoveToFolder: {
                            QuartzFeedback.primaryAction()
                            moveSourceURL = $0
                            showMoveToFolderSheet = true
                        },
                        viewModel: viewModel
                    )
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
            #if os(macOS)
            .searchable(text: $searchQuery, prompt: Text(String(localized: "Search notes, tags…", bundle: .module)))
            #endif
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 68)
        }
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
        .task { viewModel.collectTags() }
        .sheet(isPresented: $showMoveToFolderSheet) { moveToFolderSheet }
    }

    private var moveToFolderSheet: some View {
        NavigationStack {
            List {
                if let root = viewModel.vaultRootURL, let source = moveSourceURL {
                    if source.deletingLastPathComponent() != root {
                        Button {
                            QuartzFeedback.primaryAction()
                            Task { await viewModel.move(at: source, to: root) }
                            moveSourceURL = nil
                            showMoveToFolderSheet = false
                        } label: {
                            Label(String(localized: "Notes (root)", bundle: .module), systemImage: "folder.fill")
                        }
                    }
                    ForEach(collectValidMoveDestinations(from: viewModel.fileTree, sourceURL: source, root: root), id: \.url) { folder in
                        Button {
                            QuartzFeedback.primaryAction()
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

    // MARK: - New Note (primary CTA — liquid glass + accent)

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
            QuartzFeedback.selection()
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
            QuartzFeedback.selection()
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
                        QuartzFeedback.selection()
                        withAnimation { viewModel.selectedTag = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(appearance.accentColor)
                }
            }
            .padding(.bottom, Self.sectionHeaderBottomPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(viewModel.tagInfos.prefix(12)) { tag in
                        Button {
                            QuartzFeedback.selection()
                            withAnimation(QuartzAnimation.standard) {
                                viewModel.selectedTag = viewModel.selectedTag == tag.name ? nil : tag.name
                            }
                        } label: {
                            QuartzTagBadge(text: tag.name, isSelected: viewModel.selectedTag == tag.name)
                        }
                        .buttonStyle(QuartzBounceButtonStyle())
                    }
                }
                .padding(.vertical, tagsChipRowVerticalPadding)
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Folders Section (ADA Drag & Drop)

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
            var moved = false
            for sourceURL in items.map(\.url) {
                guard sourceURL.deletingLastPathComponent() != root else { continue }
                Task { await viewModel.move(at: sourceURL, to: root) }
                moved = true
            }
            if moved { QuartzFeedback.success() }
            return moved
        } isTargeted: { targeted in
            dropTargetURL = targeted ? viewModel.vaultRootURL : (dropTargetURL == viewModel.vaultRootURL ? nil : dropTargetURL)
        }
    }

    #if os(macOS)
    /// Reveals Quartz's hidden vault-local trash folder in Finder.
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
            Button { onMapViewTap?() } label: {
                Label(String(localized: "Map View", bundle: .module), systemImage: "map")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
            }
            .buttonStyle(.plain)

            Button {
                QuartzFeedback.selection()
                openVaultTrashInFinder()
            } label: {
                Label(String(localized: "Trash", bundle: .module), systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: QuartzHIG.minTouchTarget)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Reveals Quartz’s hidden trash folder in Finder.", bundle: .module))
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

        // Filter valid URLs that can be moved
        let validURLs = urls.filter { sourceURL in
            // Can't drop on itself
            guard sourceURL != folder.url else { return false }
            // Can't move a folder into its own descendant (circular dependency)
            let folderPath = folder.url.path(percentEncoded: false)
            let sourcePath = sourceURL.path(percentEncoded: false)
            guard !folderPath.hasPrefix(sourcePath + "/") else { return false }
            return true
        }

        guard !validURLs.isEmpty else { return false }

        // Provide haptic feedback for drop initiation
        QuartzFeedback.selection()

        // Batch move all valid items and track results
        Task {
            var successCount = 0
            var failureCount = 0

            for sourceURL in validURLs {
                let success = await viewModel.move(at: sourceURL, to: folder.url)
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }

            await MainActor.run {
                if successCount > 0 && failureCount == 0 {
                    // All moves succeeded
                    QuartzFeedback.success()
                } else if successCount > 0 && failureCount > 0 {
                    // Partial success - some items moved, some failed
                    QuartzFeedback.warning()
                    viewModel.errorMessage = String(
                        localized: "Moved \(successCount) item(s), but \(failureCount) failed.",
                        bundle: .module
                    )
                } else {
                    // All moves failed - error already set by viewModel.move()
                    QuartzFeedback.destructive()
                }
            }
        }

        return true
    }
}

// MARK: - Sidebar Outline View

private struct SidebarOutlineView: View {
    let nodes: [FileNode]
    @Binding var selectedNoteURL: URL?
    @Binding var dropTargetURL: URL?
    let appearance: AppearanceManager
    let onDrop: ([URL], FileNode) -> Bool
    let onDropSuccess: () -> Void
    let onSelectNote: (URL) -> Void
    let onDeleteNote: (URL) -> Void
    let onDeleteFolder: (URL) -> Void
    let onNewNote: (URL) -> Void
    let onNewFolder: (URL) -> Void
    let onMoveToFolder: (URL) -> Void
    let viewModel: SidebarViewModel

    var body: some View {
        OutlineGroup(nodes, children: \.children) { node in
            SidebarOutlineRow(
                node: node,
                selectedNoteURL: $selectedNoteURL,
                dropTargetURL: $dropTargetURL,
                appearance: appearance,
                onDrop: onDrop,
                onDropSuccess: onDropSuccess,
                onSelectNote: onSelectNote,
                onDeleteNote: onDeleteNote,
                onDeleteFolder: onDeleteFolder,
                onNewNote: onNewNote,
                onNewFolder: onNewFolder,
                onMoveToFolder: onMoveToFolder,
                viewModel: viewModel
            )
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }
}

private struct SidebarOutlineRow: View {
    let node: FileNode
    @Binding var selectedNoteURL: URL?
    @Binding var dropTargetURL: URL?
    let appearance: AppearanceManager
    let onDrop: ([URL], FileNode) -> Bool
    let onDropSuccess: () -> Void
    let onSelectNote: (URL) -> Void
    let onDeleteNote: (URL) -> Void
    let onDeleteFolder: (URL) -> Void
    let onNewNote: (URL) -> Void
    let onNewFolder: (URL) -> Void
    let onMoveToFolder: (URL) -> Void
    let viewModel: SidebarViewModel

    @Environment(AppState.self) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private var isDropTarget: Bool { dropTargetURL == node.url }

    var body: some View {
        rowContent
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(minHeight: QuartzHIG.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .overlay(rowBorder)
            .draggable(SidebarItemTransferable(url: node.url))
            .modifier(SidebarFolderDropModifier(
                node: node,
                dropTargetURL: $dropTargetURL,
                onDrop: onDrop,
                onDropSuccess: onDropSuccess
            ))
            .contextMenu {
                if node.isFolder {
                    folderContextMenu(for: node)
                } else if node.isNote {
                    noteContextMenu(for: node)
                }
            }
            .accessibilityElement(children: .combine)
            .modifier(SidebarNoteAccessibilityModifier(
                node: node,
                viewModel: viewModel,
                onDeleteNote: onDeleteNote
            ))
    }

    @ViewBuilder
    private var rowContent: some View {
        if node.isNote {
            FileNodeRow(node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    QuartzFeedback.selection()
                    onSelectNote(node.url)
                }
                #if os(macOS)
                .onTapGesture(count: 2) {
                    QuartzFeedback.primaryAction()
                    onSelectNote(node.url)
                    openWindow(value: node.url.standardizedFileURL)
                }
                #endif
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
                        onDeleteNote(node.url)
                    } label: {
                        Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                    }
                }
        } else {
            FileNodeRow(node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(backgroundFillColor)
    }

    @ViewBuilder
    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isDropTarget ? 1.5 : 0)
    }

    private var backgroundFillColor: Color {
        if isDropTarget { return appearance.accentColor.opacity(0.14) }
        if node.isNote && selectedNoteURL == node.url { return appearance.accentColor.opacity(0.1) }
        return .clear
    }

    private var borderColor: Color {
        isDropTarget ? appearance.accentColor.opacity(0.5) : .clear
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
        #if os(macOS)
        Button {
            openWindow(value: node.url.standardizedFileURL)
        } label: {
            Label(String(localized: "Open in New Window", bundle: .module), systemImage: "macwindow")
        }
        .disabled(appState.currentVault == nil)
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

private struct SidebarNoteAccessibilityModifier: ViewModifier {
    let node: FileNode
    let viewModel: SidebarViewModel
    let onDeleteNote: (URL) -> Void

    func body(content: Content) -> some View {
        if node.isNote {
            content
                .accessibilityAction(
                    named: viewModel.isFavorite(node.url)
                        ? String(localized: "Remove from Favorites", bundle: .module)
                        : String(localized: "Add to Favorites", bundle: .module)
                ) {
                    viewModel.toggleFavorite(node.url)
                    QuartzFeedback.toggle()
                }
                .accessibilityAction(named: String(localized: "Delete", bundle: .module)) {
                    onDeleteNote(node.url)
                }
        } else {
            content
        }
    }
}

private struct SidebarFolderDropModifier: ViewModifier {
    let node: FileNode
    @Binding var dropTargetURL: URL?
    let onDrop: ([URL], FileNode) -> Bool
    let onDropSuccess: () -> Void

    func body(content: Content) -> some View {
        if node.isFolder {
            // Folders accept drops directly into them
            content
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: dropTargetURL)
                .dropDestination(for: SidebarItemTransferable.self) { items, location in
                    // Ensure state is always cleared on drop completion
                    defer {
                        dropTargetURL = nil
                    }
                    let moved = onDrop(items.map(\.url), node)
                    if moved { onDropSuccess() }
                    return moved
                } isTargeted: { targeted in
                    if targeted {
                        dropTargetURL = node.url
                    } else if dropTargetURL == node.url {
                        // Clear state when no longer targeted (including cancelled drags)
                        dropTargetURL = nil
                    }
                }
        } else {
            // Notes accept drops to move items to the note's parent folder
            content
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: dropTargetURL)
                .dropDestination(for: SidebarItemTransferable.self) { items, _ in
                    defer {
                        dropTargetURL = nil
                    }
                    // For notes, create a virtual folder node representing the parent directory
                    let parentURL = node.url.deletingLastPathComponent()
                    let parentNode = FileNode(
                        name: parentURL.lastPathComponent,
                        url: parentURL,
                        nodeType: .folder
                    )
                    let moved = onDrop(items.map(\.url), parentNode)
                    if moved { onDropSuccess() }
                    return moved
                } isTargeted: { targeted in
                    if targeted {
                        dropTargetURL = node.url
                    } else if dropTargetURL == node.url {
                        dropTargetURL = nil
                    }
                }
        }
    }
}

// MARK: - New Note primary CTA (press animation)

private struct NewNoteCTAMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
