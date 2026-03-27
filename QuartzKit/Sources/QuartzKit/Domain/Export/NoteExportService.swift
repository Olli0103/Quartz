import Foundation
import CoreGraphics
import CoreText

/// Pure-function export engine for Markdown notes.
///
/// Converts raw Markdown text to PDF, HTML, RTF, or Markdown `Data`.
/// All methods are CPU-bound pure functions with no mutable state —
/// call from `Task.detached` to avoid blocking the main actor.
///
/// **PDF**: swift-markdown AST → `NSAttributedString` → `CTFramesetter` paginated render.
/// **HTML**: swift-markdown AST → direct HTML emission with embedded CSS.
/// **RTF**: swift-markdown AST → `NSAttributedString` → Cocoa RTF serialization.
/// **Markdown**: Pass-through UTF-8 encoding.
public struct NoteExportService: Sendable {

    public init() {}

    // MARK: - Markdown Export

    /// Returns the raw markdown text as UTF-8 data.
    public func exportToMarkdown(text: String, title: String, metadata: ExportMetadata? = nil) -> Data {
        text.data(using: .utf8) ?? Data()
    }

    // MARK: - HTML Export

    /// Renders markdown to a self-contained HTML document with embedded CSS.
    public func exportToHTML(text: String, title: String, metadata: ExportMetadata? = nil) -> Data {
        let html = HTMLExportVisitor.render(markdown: text, title: title, metadata: metadata)
        return html.data(using: .utf8) ?? Data()
    }

    // MARK: - RTF Export

    /// Renders markdown to RTF data via NSAttributedString.
    public func exportToRTF(text: String, title: String, metadata: ExportMetadata? = nil) -> Data {
        let attrString = RichAttributedStringBuilder.build(markdown: text, title: title)
        let range = NSRange(location: 0, length: attrString.length)

        do {
            #if canImport(UIKit)
            let rtfData = try attrString.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            return rtfData
            #elseif canImport(AppKit)
            let rtfData = try attrString.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            return rtfData
            #else
            return Data()
            #endif
        } catch {
            return Data()
        }
    }

    // MARK: - PDF Export

    /// Renders markdown to a paginated PDF using CoreText.
    ///
    /// Layout: US Letter (612×792pt), 54pt margins, title + body with proper font sizing.
    /// Page numbers are drawn bottom-center on each page.
    public func exportToPDF(text: String, title: String, metadata: ExportMetadata? = nil) -> Data {
        let attrString = RichAttributedStringBuilder.build(markdown: text, title: title)
        return renderPDF(from: attrString, title: title)
    }

    // MARK: - PDF Rendering (CoreText + CoreGraphics)

    /// US Letter dimensions in points.
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54 // 0.75 inches

    /// Text area in bottom-left PDF coordinates.
    /// y starts above the page number area, extends up to the top margin.
    private static var textRect: CGRect {
        let bottomY = margin + 20 // 20pt reserved for page number at the very bottom
        let topY = pageHeight - margin
        return CGRect(
            x: margin,
            y: bottomY,
            width: pageWidth - margin * 2,
            height: topY - bottomY
        )
    }

    private func renderPDF(from attributedString: NSAttributedString, title: String) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: Self.pageWidth, height: Self.pageHeight)

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let pdfInfo: [CFString: Any] = [
            kCGPDFContextTitle: title as CFString,
            kCGPDFContextCreator: "Quartz Notes" as CFString
        ]

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var currentIndex = 0
        var pageNumber = 1
        let textRect = Self.textRect

        while currentIndex < attributedString.length {
            if pageNumber == 1 {
                context.beginPDFPage(pdfInfo as CFDictionary)
            } else {
                context.beginPDFPage(nil)
            }

            // No coordinate flip — CGPDFContext and CTFrameDraw both use
            // bottom-left origin natively. CTFrame fills text from the top
            // of the rect downward automatically.
            context.textMatrix = .identity

            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(currentIndex, 0), path, nil)

            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentIndex += visibleRange.length

            drawPageNumber(pageNumber, in: context)

            context.endPDFPage()
            pageNumber += 1

            if visibleRange.length == 0 { break }
        }

        if pageNumber == 1 {
            context.beginPDFPage(pdfInfo as CFDictionary)
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private func drawPageNumber(_ number: Int, in context: CGContext) {
        let text = "\(number)" as CFString
        let font = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0.5, alpha: 1.0)
        ]
        let attrString = CFAttributedStringCreate(nil, text, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)

        // Position at bottom center
        let x = (Self.pageWidth - CGFloat(lineWidth)) / 2
        let y: CGFloat = 30 // 30pt from bottom

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
