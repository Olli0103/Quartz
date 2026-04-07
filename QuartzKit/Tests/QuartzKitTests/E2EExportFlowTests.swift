import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Export Flow Tests
//
// Export format selection and output contracts: ExportFormat variants,
// ExportMetadata, NoteExportService markdown/HTML production.

@Suite("E2EExportFlow")
struct E2EExportFlowTests {

    @Test("ExportFormat covers pdf, html, rtf, and markdown")
    func formatCoverage() {
        let cases = ExportFormat.allCases
        #expect(cases.count == 4)

        let rawValues = Set(cases.map(\.rawValue))
        #expect(rawValues.contains("pdf"))
        #expect(rawValues.contains("html"))
        #expect(rawValues.contains("rtf"))
        #expect(rawValues.contains("markdown"))
    }

    @Test("ExportFormat has fileExtension for all cases")
    func fileExtensions() {
        for format in ExportFormat.allCases {
            #expect(!format.fileExtension.isEmpty,
                "ExportFormat.\(format.rawValue) must have a file extension")
        }
    }

    @Test("ExportFormat has mimeType for all cases")
    func mimeTypes() {
        for format in ExportFormat.allCases {
            #expect(!format.mimeType.isEmpty,
                "ExportFormat.\(format.rawValue) must have a MIME type")
        }
    }

    @Test("ExportMetadata stores author and tags")
    func exportMetadata() {
        let metadata = ExportMetadata(
            author: "Test Author",
            createdAt: Date(),
            modifiedAt: Date(),
            tags: ["export", "test"],
            vaultRootURL: URL(fileURLWithPath: "/vault")
        )

        #expect(metadata.author == "Test Author")
        #expect(metadata.tags.count == 2)
        #expect(metadata.createdAt != nil)
        #expect(metadata.vaultRootURL != nil)
    }

    @Test("NoteExportService produces non-empty markdown data")
    func markdownExport() {
        let service = NoteExportService()
        let data = service.exportToMarkdown(
            text: "# Title\n\nSome **bold** text",
            title: "Test Note",
            metadata: nil
        )

        #expect(!data.isEmpty, "Markdown export should produce non-empty data")
        let content = String(data: data, encoding: .utf8)
        #expect(content?.contains("Title") == true)
    }

    @Test("NoteExportService produces non-empty HTML data")
    func htmlExport() {
        let service = NoteExportService()
        let data = service.exportToHTML(
            text: "# Title\n\nSome **bold** text",
            title: "Test Note",
            metadata: nil
        )

        #expect(!data.isEmpty, "HTML export should produce non-empty data")
        let content = String(data: data, encoding: .utf8)
        #expect(content?.contains("<") == true, "HTML export should contain HTML tags")
    }
}
