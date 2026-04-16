import SwiftUI
import Textual
#if canImport(UIKit)
import UIKit
#endif

/// Renders markdown as rich structured text using Textual.
/// Internal read-only renderer used by supporting flows such as version previews
/// and snapshot coverage. It is not exposed as a live editor preview mode.
struct MarkdownPreviewView: View {
    static let isUserFacingEditorMode = false

    let markdown: String
    let baseURL: URL?
    let fontScale: CGFloat

    init(
        markdown: String,
        baseURL: URL? = nil,
        fontScale: CGFloat = 1.0
    ) {
        self.markdown = markdown
        self.baseURL = baseURL
        self.fontScale = fontScale
    }

    var body: some View {
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
