import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - TextKit 2 stack factory

/// Shared factory for building the TextKit 2 stack used by `MarkdownEditorRepresentable`.
/// Creates a `MarkdownTextContentManager` and wires it to an `NSTextLayoutManager` + `NSTextContainer`.
#if os(iOS) || os(macOS)
@MainActor
enum MarkdownTextKit2Stack {
    static func makeContentManager() -> MarkdownTextContentManager {
        MarkdownTextContentManager()
    }

    static func wireTextKit2(contentManager: MarkdownTextContentManager) -> (NSTextLayoutManager, NSTextContainer) {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentManager.addTextLayoutManager(layoutManager)
        return (layoutManager, container)
    }
}
#endif
