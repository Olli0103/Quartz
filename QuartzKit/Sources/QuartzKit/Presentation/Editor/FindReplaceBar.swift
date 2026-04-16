import SwiftUI

/// Editor-local find/replace surface scoped to the currently open note.
/// This never searches or mutates outside the active ``EditorSession``.
public struct FindReplaceBar: View {
    let session: EditorSession

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case find
        case replace
    }

    public init(session: EditorSession) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCompactLayout {
                compactLayout
            } else {
                regularLayout
            }

            if session.inNoteSearch.isReplaceVisible {
                replaceRow
            }
        }
        .padding(12)
        .quartzMaterialBackground(cornerRadius: 14, shadowRadius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            focusedField = .find
        }
        .onChange(of: session.inNoteSearch.focusRequestToken) { _, _ in
            focusedField = .find
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 10) {
            queryField
            matchSummary
            navigationButtons
            caseSensitivityButton
            replaceVisibilityButton
            closeButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                queryField
                closeButton
            }

            HStack(spacing: 10) {
                matchSummary
                Spacer(minLength: 0)
                navigationButtons
                caseSensitivityButton
                replaceVisibilityButton
            }
        }
    }

    private var queryField: some View {
        TextField(
            String(localized: "Find in Note", bundle: .module),
            text: Binding(
                get: { session.inNoteSearch.query },
                set: { session.setInNoteSearchQuery($0) }
            )
        )
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .find)
        .autocorrectionDisabled(true)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .accessibilityIdentifier("editor-find-query")
        .onSubmit {
            session.findNextInNote()
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 10) {
            TextField(
                String(localized: "Replace", bundle: .module),
                text: Binding(
                    get: { session.inNoteSearch.replacement },
                    set: { session.setInNoteReplaceText($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .replace)
            .autocorrectionDisabled(true)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .accessibilityIdentifier("editor-replace-query")
            .onSubmit {
                session.replaceCurrentInNote()
            }

            Button(String(localized: "Replace", bundle: .module)) {
                session.replaceCurrentInNote()
            }
            .disabled(!session.inNoteSearch.hasReplaceableCurrentMatch)
            .accessibilityIdentifier("editor-find-replace-current")

            Button(String(localized: "Replace All", bundle: .module)) {
                session.replaceAllInNote()
            }
            .disabled(session.inNoteSearch.query.isEmpty || session.inNoteSearch.matchCount == 0)
            .accessibilityIdentifier("editor-find-replace-all")
        }
    }

    private var matchSummary: some View {
        Text(matchSummaryText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 84, alignment: .trailing)
            .accessibilityIdentifier("editor-find-match-count")
    }

    private var navigationButtons: some View {
        HStack(spacing: 6) {
            Button {
                session.findPreviousInNote()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(session.inNoteSearch.matchCount == 0)
            .accessibilityIdentifier("editor-find-previous")

            Button {
                session.findNextInNote()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(session.inNoteSearch.matchCount == 0)
            .accessibilityIdentifier("editor-find-next")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var caseSensitivityButton: some View {
        Button {
            session.setInNoteSearchCaseSensitive(!session.inNoteSearch.isCaseSensitive)
        } label: {
            Text("Aa")
                .font(.caption.weight(.semibold))
                .frame(minWidth: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(session.inNoteSearch.isCaseSensitive ? .accentColor : .secondary)
        .accessibilityLabel(String(localized: "Match Case", bundle: .module))
        .accessibilityIdentifier("editor-find-case-sensitive")
    }

    private var replaceVisibilityButton: some View {
        Button(session.inNoteSearch.isReplaceVisible
               ? String(localized: "Hide Replace", bundle: .module)
               : String(localized: "Replace", bundle: .module)) {
            session.toggleInNoteReplaceControls()
            if session.inNoteSearch.isReplaceVisible {
                focusedField = .replace
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("editor-find-toggle-replace")
    }

    private var closeButton: some View {
        Button {
            session.dismissInNoteSearch()
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(String(localized: "Close Find in Note", bundle: .module))
        .accessibilityIdentifier("editor-find-close")
    }

    private var matchSummaryText: String {
        guard !session.inNoteSearch.query.isEmpty else {
            return String(localized: "Enter text", bundle: .module)
        }
        guard session.inNoteSearch.matchCount > 0,
              let currentIndex = session.inNoteSearch.currentMatchDisplayIndex else {
            return String(localized: "No matches", bundle: .module)
        }
        return "\(currentIndex) / \(session.inNoteSearch.matchCount)"
    }

    private var isCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }
}
