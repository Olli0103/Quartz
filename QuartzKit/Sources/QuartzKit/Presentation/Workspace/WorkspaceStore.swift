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
/// **Architecture (per CODEX.md Phase 0):**
/// `route` is the single source of truth for detail pane routing.
/// The boolean properties (`showDashboard`, `showGraph`) and `selectedNoteURL`
/// are now **computed** from `route` for backward compatibility.
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

    // MARK: - Route State (Single Source of Truth)

    /// The canonical detail route state. This is the ONLY mutable route property.
    /// All other route-related properties are computed from this.
    public var route: DetailRoute = .dashboard {
        didSet {
            // Notify observers of route change for debugging/logging
            routeChangeCount += 1
        }
    }

    /// Counter for route changes (useful for debugging/testing)
    public private(set) var routeChangeCount: Int = 0

    // MARK: - Selection State

    /// Currently selected source in the left sidebar.
    /// Changing this resets note selection (via route) to nil,
    /// unless the selected note is inside the new source folder.
    public var selectedSource: SourceSelection = .allNotes {
        didSet {
            if oldValue != selectedSource {
                // Don't clear selection if the note is inside the newly selected folder
                if case .folder(let folderURL) = selectedSource,
                   case .note(let noteURL) = route {
                    // Normalize both URLs by removing trailing slashes for comparison
                    let noteDirPath = noteURL.deletingLastPathComponent().path(percentEncoded: false)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/").inverted.inverted)
                    let folderPath = folderURL.path(percentEncoded: false)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/").inverted.inverted)
                    if noteDirPath == folderPath {
                        return
                    }
                }
                // Clear note selection when changing to a different source
                if case .note = route {
                    route = .empty
                }
            }
        }
    }

    // MARK: - Computed Properties (Backward Compatibility)

    /// Currently selected note URL, derived from route.
    /// Setting this property updates the route atomically.
    public var selectedNoteURL: URL? {
        get {
            if case .note(let url) = route {
                return url
            }
            return nil
        }
        set {
            if let url = newValue {
                route = .note(url)
            } else if case .note = route {
                route = .empty
            }
        }
    }

    /// Whether the detail pane shows the Dashboard.
    /// Setting this property updates the route atomically.
    public var showDashboard: Bool {
        get { route == .dashboard }
        set {
            if newValue {
                route = .dashboard
            } else if route == .dashboard {
                route = .empty
            }
        }
    }

    /// Whether the detail pane shows the Knowledge Graph.
    /// Setting this property updates the route atomically.
    public var showGraph: Bool {
        get { route == .graph }
        set {
            if newValue {
                route = .graph
            } else if route == .graph {
                route = .empty
            }
        }
    }

    // MARK: - Route API

    /// Returns the current detail route (same as `route` property).
    /// Kept for API compatibility.
    public var currentRoute: DetailRoute {
        route
    }

    /// Sets the detail route atomically.
    /// This is the preferred way to change routes.
    public func setRoute(_ newRoute: DetailRoute) {
        route = newRoute
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
