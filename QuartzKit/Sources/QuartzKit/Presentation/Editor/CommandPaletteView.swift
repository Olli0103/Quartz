import SwiftUI

/// Native command palette triggered by Cmd+K.
/// Fuzzy-searches vault notes and executes quick actions (New Note, Search Brain).
public struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let fileTree: [FileNode]
    let vaultRootURL: URL?
    let onSelectNote: (URL) -> Void
    let onNewNote: (() -> Void)?
    let onSearch: (() -> Void)?

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var searchResults: [CommandPaletteItem] = []
    @State private var allItems: [CommandPaletteItem] = []
    @FocusState private var isSearchFocused: Bool

    public init(
        isPresented: Binding<Bool>,
        fileTree: [FileNode],
        vaultRootURL: URL?,
        onSelectNote: @escaping (URL) -> Void,
        onNewNote: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.fileTree = fileTree
        self.vaultRootURL = vaultRootURL
        self.onSelectNote = onSelectNote
        self.onNewNote = onNewNote
        self.onSearch = onSearch
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Search notes or run command…", bundle: .module), text: $query)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }
                        .onChange(of: query) { _, newValue in
                            updateResults(for: newValue)
                        }
                }
                .padding(16)
                #if os(visionOS)
                .frame(minHeight: QuartzHIG.minTouchTarget)
                #endif
                .quartzFloatingUltraThinSurface(cornerRadius: 12)

                if !searchResults.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                                    CommandPaletteRow(
                                        item: item,
                                        isSelected: index == selectedIndex
                                    ) {
                                        execute(item)
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: selectedIndex) { _, newIndex in
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                    .quartzFloatingUltraThinSurface(cornerRadius: 12)
                    .padding(.top, 8)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .quartzMaterialBackground(cornerRadius: 20, shadowRadius: 24, layer: .floating)
        }
        .onAppear {
            buildAllItems()
            updateResults(for: query)
            isSearchFocused = true
        }
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(searchResults.count - 1, selectedIndex + 1)
            return .handled
        }
    }

    private func buildAllItems() {
        var items: [CommandPaletteItem] = []
        if onNewNote != nil {
            items.append(.command(
                id: "new-note",
                title: String(localized: "New Note", bundle: .module),
                icon: "plus",
                keywords: ["new", "create"]
            ))
        }
        if onSearch != nil {
            items.append(.command(
                id: "search-brain",
                title: String(localized: "Search Brain", bundle: .module),
                icon: "magnifyingglass",
                keywords: ["search", "find"]
            ))
        }
        for node in collectNotes(from: fileTree) {
            let name = node.name.replacingOccurrences(of: ".md", with: "")
            items.append(.note(id: node.url.absoluteString, title: name, url: node.url))
        }
        allItems = items
    }

    private func collectNotes(from nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isNote { result.append(node) }
            if let children = node.children {
                result.append(contentsOf: collectNotes(from: children))
            }
        }
        return result
    }

    private func updateResults(for q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            searchResults = Array(allItems.prefix(20))
        } else {
            searchResults = allItems.filter { item in
                fuzzyMatch(query: trimmed, in: item.searchableText)
            }
            .prefix(20)
            .map { $0 }
        }
        selectedIndex = 0
    }

    /// Fuzzy match: query characters must appear in order in the target.
    private func fuzzyMatch(query: String, in target: String) -> Bool {
        var targetIndex = target.startIndex
        for char in query {
            guard let found = target[targetIndex...].firstIndex(where: { $0 == char }) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }

    private func executeSelected() {
        guard selectedIndex >= 0, selectedIndex < searchResults.count else { return }
        execute(searchResults[selectedIndex])
    }

    private func execute(_ item: CommandPaletteItem) {
        switch item {
        case .note(_, _, let url):
            isPresented = false
            onSelectNote(url)
        case .command(let id, _, _, _):
            isPresented = false
            if id == "new-note" { onNewNote?() }
            else if id == "search-brain" { onSearch?() }
        }
    }

    private func dismiss() {
        withAnimation(QuartzAnimation.content) {
            isPresented = false
        }
    }
}

// MARK: - Item Model

private enum CommandPaletteItem {
    case note(id: String, title: String, url: URL)
    case command(id: String, title: String, icon: String, keywords: [String])

    var id: String {
        switch self {
        case .note(let id, _, _): id
        case .command(let id, _, _, _): id
        }
    }

    var searchableText: String {
        switch self {
        case .note(_, let title, _): title.lowercased()
        case .command(_, let title, _, let keywords):
            (title.lowercased() + " " + keywords.joined(separator: " "))
        }
    }

    var displayTitle: String {
        switch self {
        case .note(_, let title, _): title
        case .command(_, let title, _, _): title
        }
    }

    var icon: String {
        switch self {
        case .note: "doc.text"
        case .command(_, _, let icon, _): icon
        }
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 24, alignment: .center)
                Text(item.displayTitle)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            #if os(visionOS)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            #endif
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
