import SwiftUI
#if os(macOS)
import AppKit

/// Invisible NSView that walks up the view hierarchy to find the parent
/// NSTableView/NSOutlineView and disables the native selection highlight.
///
/// This allows `List(selection:)` + `.tag()` + `.draggable()` to work
/// while our custom `.listRowBackground` provides a light, semi-transparent
/// selection highlight instead of the opaque system one.
struct TableViewSelectionRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HighlightRemoverView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class HighlightRemoverView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async { [weak self] in
            var currentView: NSView? = self
            while let view = currentView {
                if let tableView = view as? NSTableView {
                    tableView.selectionHighlightStyle = .none
                    break
                }
                currentView = view.superview
            }
        }
    }
}
#endif
