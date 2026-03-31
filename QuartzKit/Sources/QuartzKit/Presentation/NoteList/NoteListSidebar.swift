import SwiftUI

/// Middle column note list backed by the preview cache.
///
/// Displays a filtered, sorted, sectioned list of `NoteListItem` rows with search,
/// sort menu, swipe actions, and context menus. When sorted by date, notes are
/// grouped under time-bucket headers (Today, Previous 7 Days, etc.).
///
/// Pure view — all data logic lives in `NoteListStore`.
public struct NoteListSidebar: View {
    @Bindable var store: NoteListStore
    @Binding var selectedNoteURL: URL?
    var onNewNote: (() -> Void)?
    var onVoiceNote: (() -> Void)?
    var onMeetingMinutes: (() -> Void)?
    var onDeleteNote: ((URL) -> Void)?

    public init(store: NoteListStore, selectedNoteURL: Binding<URL?>, onNewNote: (() -> Void)? = nil, onVoiceNote: (() -> Void)? = nil, onMeetingMinutes: (() -> Void)? = nil, onDeleteNote: ((URL) -> Void)? = nil) {
        self.store = store
        self._selectedNoteURL = selectedNoteURL
        self.onNewNote = onNewNote
        self.onVoiceNote = onVoiceNote
        self.onMeetingMinutes = onMeetingMinutes
        self.onDeleteNote = onDeleteNote
    }

    public var body: some View {
        Group {
            if store.isLoading {
                loadingView
            } else if store.items.isEmpty {
                emptyStateView
            } else {
                noteList
            }
        }
        .navigationTitle(store.navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $store.searchText, prompt: Text("Filter notes"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        QuartzFeedback.primaryAction()
                        onNewNote?()
                    } label: {
                        Label(String(localized: "New Text Note", bundle: .module), systemImage: "square.and.pencil")
                    }

                    if onVoiceNote != nil {
                        Button {
                            QuartzFeedback.primaryAction()
                            onVoiceNote?()
                        } label: {
                            Label(String(localized: "New Voice Note", bundle: .module), systemImage: "mic")
                        }
                    }

                    if onMeetingMinutes != nil {
                        Button {
                            QuartzFeedback.primaryAction()
                            onMeetingMinutes?()
                        } label: {
                            Label(String(localized: "New Meeting Minutes", bundle: .module), systemImage: "person.2")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .symbolRenderingMode(.hierarchical)
                } primaryAction: {
                    QuartzFeedback.primaryAction()
                    onNewNote?()
                }
                .tint(.primary)
                .accessibilityLabel(String(localized: "New Note", bundle: .module))

                sortMenu
            }
        }
    }

    // MARK: - Note List

    @Environment(\.appearanceManager) private var appearance

    private var noteList: some View {
        List(selection: $selectedNoteURL) {
            ForEach(store.sections) { section in
                if section.title.isEmpty {
                    // Flat section — no header
                    noteRows(for: section.items)
                } else {
                    Section {
                        noteRows(for: section.items)
                    } header: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .animation(QuartzAnimation.content, value: store.sections.map(\.id))
    }

    @ViewBuilder
    private func noteRows(for items: [NoteListItem]) -> some View {
        ForEach(items) { item in
            NoteListRow(item: item)
                .tag(item.url)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedNoteURL == item.url
                              ? appearance.accentColor.opacity(0.1)
                              : Color.clear)
                )
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        QuartzFeedback.destructive()
                        if selectedNoteURL == item.url {
                            selectedNoteURL = nil
                        }
                        onDeleteNote?(item.url)
                    } label: {
                        Label(String(localized: "Trash", bundle: .module), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        QuartzFeedback.toggle()
                        toggleFavorite(item)
                    } label: {
                        Label(
                            item.isFavorite
                                ? String(localized: "Unfavorite", bundle: .module)
                                : String(localized: "Favorite", bundle: .module),
                            systemImage: item.isFavorite ? "star.slash" : "star.fill"
                        )
                    }
                    .tint(.yellow)
                }
                #endif
                .contextMenu {
                    Button {
                        QuartzFeedback.toggle()
                        toggleFavorite(item)
                    } label: {
                        Label(
                            item.isFavorite
                                ? String(localized: "Remove from Favorites", bundle: .module)
                                : String(localized: "Add to Favorites", bundle: .module),
                            systemImage: item.isFavorite ? "star.slash" : "star.fill"
                        )
                    }

                    Divider()

                    Button(role: .destructive) {
                        QuartzFeedback.destructive()
                        if selectedNoteURL == item.url {
                            selectedNoteURL = nil
                        }
                        onDeleteNote?(item.url)
                    } label: {
                        Label(String(localized: "Move to Trash", bundle: .module), systemImage: "trash")
                    }
                }
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        List {
            ForEach(0..<8, id: \.self) { index in
                SkeletonRow()
                    .staggered(index: index)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        QuartzEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        if !store.searchText.isEmpty { return "magnifyingglass" }
        return "doc.text"
    }

    private var emptyTitle: String {
        if !store.searchText.isEmpty {
            return String(localized: "No Results", bundle: .module)
        }
        return String(localized: "No Notes", bundle: .module)
    }

    private var emptySubtitle: String {
        if !store.searchText.isEmpty {
            return String(localized: "No notes match your search.", bundle: .module)
        }
        return String(localized: "Notes will appear here when you create them.", bundle: .module)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(NoteListSortOrder.allCases, id: \.self) { order in
                Button {
                    store.sortOrder = order
                } label: {
                    Label {
                        Text(order.label)
                    } icon: {
                        if store.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .symbolRenderingMode(.hierarchical)
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "Sort Order", bundle: .module))
    }

    // MARK: - Actions

    private func toggleFavorite(_ item: NoteListItem) {
        FavoriteNoteStorage.toggleFavorite(
            fileURL: item.url,
            vaultRoot: store.vaultRoot,
            fileTree: nil
        )
        // NoteListStore auto-refreshes via .quartzFavoritesDidChange observer
    }
}
