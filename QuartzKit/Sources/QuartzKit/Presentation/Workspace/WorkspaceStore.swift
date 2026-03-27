import SwiftUI

// MARK: - Source Selection Model

/// Represents what the user has selected in the left (navigation) sidebar.
/// Each case maps to a distinct note-list filter in the middle column.
public enum SourceSelection: Hashable, Sendable {
    case allNotes
    case favorites
    case recent
    case folder(URL)
    case tag(String)
}

// MARK: - Workspace Store

/// Owns the three-pane workspace state: source selection, note selection,
/// and column visibility. Replaces the scattered `@State` properties that
/// previously lived in `ContentView`.
///
/// **Apple doc:** `NavigationSplitView` column visibility is driven by a
/// `NavigationSplitViewVisibility` binding. This store provides the
/// canonical source of truth; the view layer bridges to `@SceneStorage`
/// for persistence across relaunches.
///
/// **Ref:** https://developer.apple.com/documentation/swiftui/navigationsplitview
@Observable
@MainActor
public final class WorkspaceStore {

    // MARK: - Selection State

    /// Currently selected source in the left sidebar.
    /// Changing this resets `selectedNoteURL` to nil (new context).
    public var selectedSource: SourceSelection = .allNotes {
        didSet {
            if oldValue != selectedSource {
                selectedNoteURL = nil
            }
        }
    }

    /// Currently selected note URL, driven by the middle column.
    /// Observed by the detail column to load the editor.
    public var selectedNoteURL: URL?

    // MARK: - Column Visibility

    /// Controls which columns are visible in the NavigationSplitView.
    /// View layer persists this to `@SceneStorage` via `onChange`.
    public var columnVisibility: NavigationSplitViewVisibility = .all

    /// Preferred column when in compact (iPhone) width class.
    public var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    // MARK: - Focus Mode Bridge

    /// Stashes the pre-focus visibility so we restore exactly what the user had.
    private var preFocusVisibility: NavigationSplitViewVisibility?

    /// When true, forces `columnVisibility` to `.detailOnly` with a fluid spring.
    /// Restores the previous visibility on exit.
    /// Observed from `FocusModeManager` environment.
    public func applyFocusMode(_ isActive: Bool) {
        QuartzFeedback.toggle()
        withAnimation(QuartzAnimation.content) {
            if isActive {
                preFocusVisibility = columnVisibility
                columnVisibility = .detailOnly
            } else {
                columnVisibility = preFocusVisibility ?? .all
                preFocusVisibility = nil
            }
        }
    }

    // MARK: - Init

    public init() {}
}
