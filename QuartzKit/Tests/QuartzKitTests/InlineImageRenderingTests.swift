import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import QuartzKit

// MARK: - Inline Image Rendering Tests

/// Verifies ScaledTextAttachment image scaling behavior and the
/// inline image rendering pipeline (U+FFFC placeholder, attachment
/// bounds, scaling logic).

@Suite("Inline Image Rendering")
struct InlineImageRenderingTests {

    /// Creates a ScaledTextAttachment with an embedded test image.
    private func makeAttachment(width: Int = 10, height: Int = 10) -> ScaledTextAttachment {
        let attachment = ScaledTextAttachment()
        #if canImport(UIKit)
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        attachment.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()
        attachment.image = image
        #endif
        return attachment
    }

    @Test("ScaledTextAttachment with image has non-nil image")
    func attachmentWithImage() {
        let attachment = makeAttachment()
        #expect(attachment.image != nil, "Attachment should have an image")
    }

    @Test("Nil image produces zero bounds")
    func nilImageZeroBounds() {
        let attachment = ScaledTextAttachment()
        // No image set — TextKit 1 path
        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 500, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )
        #expect(bounds == .zero, "Nil image should produce zero bounds")
    }

    @Test("Small image uses natural size (no upscaling)")
    func smallImageNaturalSize() {
        let attachment = makeAttachment(width: 10, height: 10)

        let containerWidth: CGFloat = 500
        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: containerWidth, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )
        // 10x10 image is smaller than container (500 - 32 padding = 468), so natural size
        #expect(bounds.width == 10, "Small image should not be upscaled, got \(bounds.width)")
        #expect(bounds.height == 10, "Small image should not be upscaled, got \(bounds.height)")
    }

    @Test("Large image is scaled down to fit container")
    func largeImageScaledDown() {
        let attachment = makeAttachment(width: 1000, height: 500)

        let containerWidth: CGFloat = 300
        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: containerWidth, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )
        let maxWidth = containerWidth - 32 // 16px horizontal padding on each side
        #expect(bounds.width <= maxWidth + 1,
            "Large image should be scaled to fit within container, got \(bounds.width)")
        // Check aspect ratio preserved: original is 2:1
        let ratio = bounds.width / bounds.height
        #expect(abs(ratio - 2.0) < 0.1,
            "Aspect ratio (2:1) should be preserved, got \(ratio)")
    }

    @Test("U+FFFC is the attachment placeholder character")
    func objectReplacementCharacter() {
        let placeholder = "\u{FFFC}"
        #expect(placeholder.unicodeScalars.first?.value == 0xFFFC)
        #expect(placeholder.count == 1)
    }
}
