import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Centralized font factory for the editor.
///
/// Maps `EditorFontFamily` to platform fonts with proper weight and italic support.
/// Used by `MarkdownASTHighlighter` and the editor representables.
///
/// Code blocks always use monospaced regardless of the editor font family.
public enum EditorFontFactory {

    #if canImport(UIKit)
    public static func makeFont(
        family: AppearanceManager.EditorFontFamily,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        italic: Bool = false
    ) -> UIFont {
        let descriptor: UIFontDescriptor

        switch family {
        case .system:
            descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        case .serif:
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            if let serifDesc = base.withDesign(.serif) {
                descriptor = serifDesc.addingAttributes([.size: size])
            } else {
                descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            }
        case .monospaced:
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            if let roundedDesc = base.withDesign(.rounded) {
                descriptor = roundedDesc.addingAttributes([.size: size])
            } else {
                descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            }
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if weight == .bold || weight == .semibold || weight == .heavy {
            traits.insert(.traitBold)
        }
        if italic {
            traits.insert(.traitItalic)
        }

        if !traits.isEmpty, let styledDesc = descriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: styledDesc, size: size)
        }

        return UIFont(descriptor: descriptor, size: size)
    }

    /// Always returns monospaced font for code blocks.
    public static func makeCodeFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    #elseif canImport(AppKit)
    public static func makeFont(
        family: AppearanceManager.EditorFontFamily,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        italic: Bool = false
    ) -> NSFont {
        var font: NSFont

        switch family {
        case .system:
            font = .systemFont(ofSize: size, weight: weight)
        case .serif:
            if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.serif),
               let resolved = NSFont(descriptor: descriptor, size: size),
               resolved.pointSize > 0 {
                font = resolved
            } else {
                font = .systemFont(ofSize: size, weight: weight)
            }
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.rounded),
               let resolved = NSFont(descriptor: descriptor, size: size),
               resolved.pointSize > 0 {
                font = resolved
            } else {
                font = .systemFont(ofSize: size, weight: weight)
            }
        }

        // Apply weight for non-system designs
        if family != .system && family != .monospaced {
            if weight == .bold || weight == .semibold || weight == .heavy {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }

        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }

    /// Always returns monospaced font for code blocks.
    public static func makeCodeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
    #endif
}
