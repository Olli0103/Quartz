import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum EditorTypography {
    public static let defaultFontFamily: AppearanceManager.EditorFontFamily = .serif
    public static let defaultFontSize: CGFloat = 17
    public static let defaultLineSpacingMultiplier: CGFloat = 1.625
    public static let defaultMaxWidth: CGFloat = 680

    public static func headingScale(for level: Int) -> CGFloat {
        switch level {
        case 1: 1.58
        case 2: 1.36
        case 3: 1.21
        case 4: 1.12
        case 5: 1.08
        case 6: 1.04
        default: 1.0
        }
    }

    public static func paragraphStyle(
        for blockKind: EditorBlockKind?,
        baseFontSize: CGFloat,
        lineSpacingMultiplier: CGFloat
    ) -> NSParagraphStyle? {
        if case .tableRow = blockKind {
            return nil
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = max((lineSpacingMultiplier - 1) * baseFontSize, 0)
        style.paragraphSpacingBefore = 0
        style.paragraphSpacing = round(baseFontSize * 0.42)
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        style.lineBreakMode = .byWordWrapping

        switch blockKind {
        case .blank:
            style.paragraphSpacing = 0
        case .paragraph, nil:
            break
        case let .heading(level):
            style.paragraphSpacingBefore = headingSpacingBefore(level: level, baseFontSize: baseFontSize)
            style.paragraphSpacing = headingSpacingAfter(level: level, baseFontSize: baseFontSize)
        case .listItem:
            style.paragraphSpacing = round(baseFontSize * 0.18)
        case .blockquote:
            style.paragraphSpacingBefore = round(baseFontSize * 0.18)
            style.paragraphSpacing = round(baseFontSize * 0.32)
            style.headIndent = round(baseFontSize * 0.55)
        case .codeFence:
            style.lineSpacing = max((lineSpacingMultiplier - 1) * baseFontSize * 0.72, 0)
            style.paragraphSpacingBefore = round(baseFontSize * 0.34)
            style.paragraphSpacing = round(baseFontSize * 0.34)
        case .tableRow:
            return nil
        }

        return style
    }

    private static func headingSpacingBefore(level: Int, baseFontSize: CGFloat) -> CGFloat {
        switch level {
        case 1: return round(baseFontSize * 0.64)
        case 2: return round(baseFontSize * 0.5)
        case 3: return round(baseFontSize * 0.34)
        default: return round(baseFontSize * 0.18)
        }
    }

    private static func headingSpacingAfter(level: Int, baseFontSize: CGFloat) -> CGFloat {
        switch level {
        case 1: return round(baseFontSize * 0.28)
        case 2: return round(baseFontSize * 0.22)
        case 3: return round(baseFontSize * 0.18)
        default: return round(baseFontSize * 0.12)
        }
    }
}
