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
    var onTogglePreview: (() -> Void)?
    var onToggleFocusMode: (() -> Void)?
    var onSave: (() -> Void)?

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var searchResults: [CommandPaletteItem] = []
    @State private var allItems: [CommandPaletteItem] = []
    @FocusState private var isSearchFocused: Bool
    @Environment(\.appearanceManager) private var appearance

    public init(
        isPresented: Binding<Bool>,
        fileTree: [FileNode],
        vaultRootURL: URL?,
        onSelectNote: @escaping (URL) -> Void,
        onNewNote: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onTogglePreview: (() -> Void)? = nil,
        onToggleFocusMode: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.fileTree = fileTree
        self.vaultRootURL = vaultRootURL
        self.onSelectNote = onSelectNote
        self.onNewNote = onNewNote
        self.onSearch = onSearch
        self.onTogglePreview = onTogglePreview
        self.onToggleFocusMode = onToggleFocusMode
        self.onSave = onSave
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Search field with keyboard shortcut hint
                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appearance.accentColor)
                    TextField(String(localized: "Search notes or run command…", bundle: .module), text: $query)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }
                        .onChange(of: query) { _, newValue in
                            updateResults(for: newValue)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                #if os(visionOS)
                .frame(minHeight: QuartzHIG.minTouchTarget)
                #endif

                Divider()
                    .overlay(appearance.accentColor.opacity(0.2))

                if !searchResults.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, item in
                                    CommandPaletteRow(
                                        item: item,
                                        isSelected: index == selectedIndex,
                                        accentColor: appearance.accentColor
                                    ) {
                                        QuartzFeedback.selection()
                                        execute(item)
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                        }
                        .frame(maxHeight: 360)
                        .onChange(of: selectedIndex) { _, newIndex in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                } else if !query.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "No results", bundle: .module))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }

                // Footer with keyboard hints
                HStack(spacing: 16) {
                    keyboardHint("↑↓", label: String(localized: "Navigate", bundle: .module))
                    keyboardHint("↵", label: String(localized: "Select", bundle: .module))
                    keyboardHint("esc", label: String(localized: "Close", bundle: .module))
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .frame(maxWidth: 520)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(appearance.accentColor.opacity(0.15), lineWidth: 1)
            }
            .padding(24)
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
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func keyboardHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func buildAllItems() {
        var items: [CommandPaletteItem] = []

        // Commands section
        if onNewNote != nil {
            items.append(.command(
                id: "new-note",
                title: String(localized: "New Note", bundle: .module),
                icon: "plus.circle.fill",
                keywords: ["new", "create", "add"],
                shortcut: "⌘N"
            ))
        }
        if onSearch != nil {
            items.append(.command(
                id: "search-brain",
                title: String(localized: "Search Brain", bundle: .module),
                icon: "brain.head.profile",
                keywords: ["search", "find", "query"],
                shortcut: "⌘⇧F"
            ))
        }
        if onTogglePreview != nil {
            items.append(.command(
                id: "toggle-preview",
                title: String(localized: "Toggle Preview", bundle: .module),
                icon: "eye",
                keywords: ["preview", "view", "markdown", "render"],
                shortcut: "⌘P"
            ))
        }
        if onToggleFocusMode != nil {
            items.append(.command(
                id: "focus-mode",
                title: String(localized: "Toggle Focus Mode", bundle: .module),
                icon: "moon.fill",
                keywords: ["focus", "zen", "distraction", "free"],
                shortcut: "⌘."
            ))
        }
        if onSave != nil {
            items.append(.command(
                id: "save",
                title: String(localized: "Save Note", bundle: .module),
                icon: "square.and.arrow.down",
                keywords: ["save", "write"],
                shortcut: "⌘S"
            ))
        }

        // Notes section
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
            // Show commands first, then recent notes
            let commands = allItems.filter { if case .command = $0 { return true }; return false }
            let notes = allItems.filter { if case .note = $0 { return true }; return false }
            searchResults = commands + Array(notes.prefix(15))
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
        QuartzFeedback.primaryAction()
        execute(searchResults[selectedIndex])
    }

    private func execute(_ item: CommandPaletteItem) {
        switch item {
        case .note(_, _, let url):
            isPresented = false
            onSelectNote(url)
        case .command(let id, _, _, _, _):
            isPresented = false
            switch id {
            case "new-note": onNewNote?()
            case "search-brain": onSearch?()
            case "toggle-preview": onTogglePreview?()
            case "focus-mode": onToggleFocusMode?()
            case "save": onSave?()
            default: break
            }
        }
    }

    private func dismiss() {
        QuartzFeedback.selection()
        withAnimation(QuartzAnimation.content) {
            isPresented = false
        }
    }
}

// MARK: - Item Model

private enum CommandPaletteItem {
    case note(id: String, title: String, url: URL)
    case command(id: String, title: String, icon: String, keywords: [String], shortcut: String? = nil)

    var id: String {
        switch self {
        case .note(let id, _, _): id
        case .command(let id, _, _, _, _): id
        }
    }

    var searchableText: String {
        switch self {
        case .note(_, let title, _): title.lowercased()
        case .command(_, let title, _, let keywords, _):
            (title.lowercased() + " " + keywords.joined(separator: " "))
        }
    }

    var displayTitle: String {
        switch self {
        case .note(_, let title, _): title
        case .command(_, let title, _, _, _): title
        }
    }

    var icon: String {
        switch self {
        case .note: "doc.text.fill"
        case .command(_, _, let icon, _, _): icon
        }
    }

    var shortcut: String? {
        switch self {
        case .note: nil
        case .command(_, _, _, _, let shortcut): shortcut
        }
    }

    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : (item.isCommand ? accentColor : .secondary))
                    .frame(width: 26, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.body)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                    if item.isCommand {
                        Text(String(localized: "Command", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                    }
                }
                Spacer()
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            #if os(visionOS)
            .frame(minHeight: QuartzHIG.minTouchTarget)
            #endif
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
