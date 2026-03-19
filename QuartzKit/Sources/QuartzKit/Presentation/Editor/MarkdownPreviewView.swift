import SwiftUI
import Textual
#if canImport(UIKit)
import UIKit
#endif

/// Renders markdown as rich structured text using Textual.
/// Used in preview mode for beautiful read-only display.
public struct MarkdownPreviewView: View {
    let markdown: String
    let baseURL: URL?
    let fontScale: CGFloat

    public init(
        markdown: String,
        baseURL: URL? = nil,
        fontScale: CGFloat = 1.0
    ) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.fontScale = fontScale
    }

    public var body: some View {
        ScrollView {
            StructuredText(markdown: markdown, baseURL: baseURL, syntaxExtensions: [.math])
                .textual.structuredTextStyle(.gitHub)
                .textual.textSelection(.enabled)
                .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
                .font(.system(size: baseFontSize * fontScale))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var baseFontSize: CGFloat {
        #if os(macOS)
        14
        #elseif os(iOS)
        UIFont.preferredFont(forTextStyle: .body).pointSize
        #else
        16
        #endif
    }
}
