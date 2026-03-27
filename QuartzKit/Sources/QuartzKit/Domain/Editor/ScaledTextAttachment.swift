import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Text attachment that scales its image to fit within the text container width,
/// maintaining the original aspect ratio. Prevents 4K images from blowing out
/// the editor layout.
///
/// Used by `MarkdownASTHighlighter` when rendering inline `![](...)` images.
/// Overrides both TextKit 1 and TextKit 2 attachment bounds methods.
public final class ScaledTextAttachment: NSTextAttachment, @unchecked Sendable {

    /// Horizontal padding subtracted from the available width so the image
    /// doesn't touch the container edges.
    private static let horizontalPadding: CGFloat = 16

    // MARK: - TextKit 2 (NSTextAttachmentLayout)

    override public func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        return scaledBounds(within: proposedLineFragment.width)
    }

    // MARK: - TextKit 1 fallback

    #if canImport(AppKit)
    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        return scaledBounds(within: lineFrag.width)
    }
    #endif

    #if canImport(UIKit)
    override public func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        return scaledBounds(within: lineFrag.width)
    }
    #endif

    // MARK: - Shared Scaling Logic

    private func scaledBounds(within availableWidth: CGFloat) -> CGRect {
        guard let img = image else {
            return .zero
        }

        let imageSize = img.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let maxWidth = availableWidth - Self.horizontalPadding * 2
        guard maxWidth > 0 else {
            return CGRect(origin: .zero, size: imageSize)
        }

        if imageSize.width <= maxWidth {
            // Image fits — use its natural size
            return CGRect(origin: .zero, size: imageSize)
        }

        // Scale down to fit
        let scale = maxWidth / imageSize.width
        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(origin: .zero, size: scaledSize)
    }
}
