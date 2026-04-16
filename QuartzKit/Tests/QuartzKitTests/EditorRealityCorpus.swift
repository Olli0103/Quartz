import Foundation
import XCTest

enum EditorRealityFixture: String, CaseIterable {
    case headingParagraphDrift = "heading_paragraph_drift"
    case editorStateRoundtrip = "editor_state_roundtrip"
    case concealmentBoundaries = "concealment_boundaries"
    case multilineFormattingToolbar = "multiline_formatting_toolbar"
    case existingLongHeadingRender = "existing_long_heading_render"

    var fileName: String { rawValue }

    var verificationAnchor: String {
        switch self {
        case .headingParagraphDrift:
            return "Das ist ein Test..."
        case .editorStateRoundtrip:
            return "Paragraph with"
        case .concealmentBoundaries:
            return "Paragraph with"
        case .multilineFormattingToolbar:
            return "How are you?"
        case .existingLongHeadingRender:
            return "Release Notes"
        }
    }

    func load() throws -> String {
        let bundle = Bundle.module

        let directURL =
            bundle.url(forResource: fileName, withExtension: "md", subdirectory: "EditorRealityCorpus")
            ?? bundle.url(forResource: fileName, withExtension: "md")
            ?? bundle.resourceURL?
                .appending(path: "EditorRealityCorpus")
                .appending(path: "\(fileName).md")

        guard let url = directURL, FileManager.default.fileExists(atPath: url.path()) else {
            XCTFail("Missing editor reality fixture: \(fileName).md")
            throw CocoaError(.fileNoSuchFile)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
