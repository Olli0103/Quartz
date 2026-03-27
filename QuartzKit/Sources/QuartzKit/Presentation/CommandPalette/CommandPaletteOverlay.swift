import SwiftUI

/// Spotlight-style command palette overlay.
///
/// Floats above the app content with a dimming scrim. Provides a search
/// field that fuzzy-matches notes and commands, keyboard navigation
/// (Up/Down/Enter/Escape), and auto-scrolling to the selected row.
///
/// **Ref:** Phase H1 Spec — CommandPaletteOverlay
public struct CommandPaletteOverlay: View {
    let engine: CommandPaletteEngine
    var onDismiss: () -> Void
    var onOpenNote: ((URL) -> Void)?

    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        engine: CommandPaletteEngine,
        onDismiss: @escaping () -> Void,
        onOpenNote: ((URL) -> Void)? = nil
    ) {
        self.engine = engine
        self.onDismiss = onDismiss
        self.onOpenNote = onOpenNote
    }

    public var body: some View {
        ZStack {
            // Tap-catching scrim — nearly invisible, only catches taps to dismiss
            Color.black.opacity(0.01)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)
                .transition(.opacity)

            // Palette container — the only element that scales
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
                if !engine.results.isEmpty {
                    Divider()
                    keyboardHints
                }
            }
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .frame(maxWidth: 580)
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, topOffset)
            .transition(
                .scale(scale: 0.96, anchor: .top)
                .combined(with: .opacity)
            )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: engine.results.count)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
        .onKeyPress(.upArrow) {
            engine.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            engine.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.return) {
            executeAndDismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(String(localized: "Command Palette", bundle: .module))
    }

    // MARK: - Top Offset

    private var topOffset: CGFloat {
        #if os(iOS)
        60 // closer to top on iPhone
        #else
        80 // ~18% from top on macOS
        #endif
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            TextField(
                String(localized: "Search notes or commands…", bundle: .module),
                text: Binding(
                    get: { engine.searchText },
                    set: { engine.searchText = $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($isSearchFieldFocused)
            #if os(iOS)
            .submitLabel(.go)
            .onSubmit { executeAndDismiss() }
            #endif

            if !engine.searchText.isEmpty {
                Button {
                    engine.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search", bundle: .module))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Section: Notes
                    let noteItems = engine.results.enumerated().filter {
                        if case .note = $0.element { return true }
                        return false
                    }
                    let commandItems = engine.results.enumerated().filter {
                        if case .command = $0.element { return true }
                        return false
                    }

                    if !noteItems.isEmpty {
                        sectionHeader(engine.searchText.isEmpty
                            ? String(localized: "Recent Notes", bundle: .module)
                            : String(localized: "Notes", bundle: .module))
                        ForEach(noteItems, id: \.offset) { index, item in
                            resultRow(item: item, index: index, proxy: proxy)
                        }
                    }

                    if !commandItems.isEmpty {
                        sectionHeader(engine.searchText.isEmpty
                            ? String(localized: "Quick Actions", bundle: .module)
                            : String(localized: "Commands", bundle: .module))
                        ForEach(commandItems, id: \.offset) { index, item in
                            resultRow(item: item, index: index, proxy: proxy)
                        }
                    }

                    if engine.results.isEmpty && !engine.searchText.isEmpty {
                        Text(String(localized: "No results found", bundle: .module))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)
            .onChange(of: engine.selectedIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < engine.results.count else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(engine.results[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func resultRow(item: PaletteItem, index: Int, proxy: ScrollViewProxy) -> some View {
        CommandPaletteResultRow(item: item, isSelected: index == engine.selectedIndex)
            .id(item.id)
            .onTapGesture {
                engine.selectedIndex = index
                executeAndDismiss()
            }
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    engine.selectedIndex = index
                }
            }
            #endif
    }

    // MARK: - Keyboard Hints Footer

    private var keyboardHints: some View {
        HStack(spacing: 16) {
            keyHint("↑↓", label: String(localized: "Navigate", bundle: .module))
            keyHint("↵", label: String(localized: "Open", bundle: .module))
            keyHint("esc", label: String(localized: "Close", bundle: .module))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.primary.opacity(0.08))
                )
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func executeAndDismiss() {
        if let url = engine.executeSelected() {
            onOpenNote?(url)
        }
        dismiss()
    }

    private func dismiss() {
        QuartzFeedback.selection()
        onDismiss()
    }
}
