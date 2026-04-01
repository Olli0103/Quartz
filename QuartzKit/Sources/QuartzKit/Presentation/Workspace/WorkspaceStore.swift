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

// MARK: - Detail Route Model

/// Represents what is shown in the detail (right) pane.
/// This enum is the canonical source of truth for detail routing,
/// replacing the boolean flags showGraph/showDashboard/selectedNoteURL.
public enum DetailRoute: Equatable, Sendable {
    case dashboard
    case graph
    case note(URL)
    case empty
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
    /// Changing this resets `selectedNoteURL` to nil (new context),
    /// unless the selected note is inside the new source folder.
    public var selectedSource: SourceSelection = .allNotes {
        didSet {
            if oldValue != selectedSource {
                // Don't clear selection if the note is inside the newly selected folder
                if case .folder(let folderURL) = selectedSource,
                   let noteURL = selectedNoteURL {
                    // Normalize both URLs by removing trailing slashes for comparison
                    let noteDirPath = noteURL.deletingLastPathComponent().path(percentEncoded: false)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/").inverted.inverted)
                    let folderPath = folderURL.path(percentEncoded: false)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/").inverted.inverted)
                    if noteDirPath == folderPath {
                        return
                    }
                }
                selectedNoteURL = nil
            }
        }
    }

    /// Currently selected note URL, driven by the middle column.
    /// Observed by the detail column to load the editor.
    public var selectedNoteURL: URL? {
        didSet {
            if selectedNoteURL != nil {
                showDashboard = false
                showGraph = false
            }
        }
    }

    /// Whether the detail pane shows the Dashboard instead of a note editor.
    public var showDashboard: Bool = true {
        didSet {
            if showDashboard {
                showGraph = false
                selectedNoteURL = nil
            }
        }
    }

    /// Whether the detail pane shows the Knowledge Graph.
    public var showGraph: Bool = false {
        didSet {
            if showGraph {
                showDashboard = false
                selectedNoteURL = nil
            }
        }
    }

    // MARK: - Computed Route (Compatibility Layer)

    /// Derives the current detail route from boolean flags.
    /// This provides a clean enum-based API while maintaining
    /// backward compatibility with existing boolean-based code.
    ///
    /// Precedence: graph > dashboard > note > empty
    public var currentRoute: DetailRoute {
        if showGraph {
            return .graph
        } else if showDashboard {
            return .dashboard
        } else if let noteURL = selectedNoteURL {
            return .note(noteURL)
        } else {
            return .empty
        }
    }

    /// Sets the detail route atomically, updating all boolean flags consistently.
    /// This is the preferred way to change routes going forward.
    public func setRoute(_ route: DetailRoute) {
        // Temporarily disable didSet side effects by setting all at once
        switch route {
        case .dashboard:
            showGraph = false
            selectedNoteURL = nil
            showDashboard = true
        case .graph:
            showDashboard = false
            selectedNoteURL = nil
            showGraph = true
        case .note(let url):
            showGraph = false
            showDashboard = false
            selectedNoteURL = url
        case .empty:
            showGraph = false
            showDashboard = false
            selectedNoteURL = nil
        }
    }

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
