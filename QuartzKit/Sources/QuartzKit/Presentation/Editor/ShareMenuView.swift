import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Share/export menu for the editor toolbar.
///
/// Provides export to PDF, HTML, RTF, and Markdown via `.fileExporter`,
/// plus copy-to-pasteboard for HTML and RTF.
///
/// **Ref:** Phase H2 Spec — ShareMenuView
public struct ShareMenuView: View {
    /// The raw markdown text to export.
    let markdownText: String
    /// The note's display title.
    let noteTitle: String
    /// Optional metadata for enriched export.
    var metadata: ExportMetadata?

    @State private var exportFormat: ExportFormat?
    @State private var exportedFileURL: URL?
    @State private var showFileExporter = false
    @State private var isExporting = false

    @Environment(\.appearanceManager) private var appearance

    private let exportService = NoteExportService()

    public init(markdownText: String, noteTitle: String, metadata: ExportMetadata? = nil) {
        self.markdownText = markdownText
        self.noteTitle = noteTitle
        self.metadata = metadata
    }

    public var body: some View {
        Menu {
            Section {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button {
                        exportAs(format)
                    } label: {
                        Label("Export as \(format.displayName)", systemImage: format.icon)
                    }
                    .disabled(isExporting)
                }
            }

            Section {
                Button {
                    copyAsHTML()
                } label: {
                    Label(String(localized: "Copy as HTML", bundle: .module), systemImage: "doc.on.clipboard")
                }

                Button {
                    copyAsRTF()
                } label: {
                    Label(String(localized: "Copy as Rich Text", bundle: .module), systemImage: "doc.on.clipboard.fill")
                }
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "Share note", bundle: .module))
        .help(String(localized: "Export or share this note", bundle: .module))
        .fileExporter(
            isPresented: $showFileExporter,
            document: ExportFileDocument(data: exportedData, format: exportFormat ?? .markdown),
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            // Clean up temp state
            exportFormat = nil
            exportedFileURL = nil
        }
    }

    // MARK: - Export Actions

    private func exportAs(_ format: ExportFormat) {
        let text = markdownText
        let title = noteTitle
        let meta = metadata
        isExporting = true
        exportFormat = format

        Task.detached(priority: .userInitiated) {
            let service = NoteExportService()
            let data: Data
            switch format {
            case .pdf: data = service.exportToPDF(text: text, title: title, metadata: meta)
            case .html: data = service.exportToHTML(text: text, title: title, metadata: meta)
            case .rtf: data = service.exportToRTF(text: text, title: title, metadata: meta)
            case .markdown: data = service.exportToMarkdown(text: text, title: title, metadata: meta)
            }

            await MainActor.run {
                pendingExportData = data
                isExporting = false
                showFileExporter = true
            }
        }
    }

    // MARK: - Copy to Pasteboard

    private func copyAsHTML() {
        let text = markdownText
        let title = noteTitle
        let meta = metadata
        Task.detached(priority: .userInitiated) {
            let service = NoteExportService()
            let data = service.exportToHTML(text: text, title: title, metadata: meta)
            await MainActor.run {
                #if canImport(AppKit)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .html)
                #elseif canImport(UIKit)
                UIPasteboard.general.setData(data, forPasteboardType: UTType.html.identifier)
                #endif
                QuartzFeedback.success()
            }
        }
    }

    private func copyAsRTF() {
        let text = markdownText
        let title = noteTitle
        let meta = metadata
        Task.detached(priority: .userInitiated) {
            let service = NoteExportService()
            let data = service.exportToRTF(text: text, title: title, metadata: meta)
            await MainActor.run {
                #if canImport(AppKit)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .rtf)
                #elseif canImport(UIKit)
                UIPasteboard.general.setData(data, forPasteboardType: UTType.rtf.identifier)
                #endif
                QuartzFeedback.success()
            }
        }
    }

    // MARK: - File Exporter Helpers

    @State private var pendingExportData: Data?

    private var exportedData: Data {
        pendingExportData ?? Data()
    }

    private var exportContentType: UTType {
        guard let format = exportFormat else { return .plainText }
        switch format {
        case .pdf: return .pdf
        case .html: return .html
        case .rtf: return .rtf
        case .markdown: return .plainText
        }
    }

    private var exportFilename: String {
        let baseName = noteTitle.replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "/", with: "-")
        return "\(baseName).\(exportFormat?.fileExtension ?? "md")"
    }
}

// MARK: - FileDocument for Export

/// A simple FileDocument wrapper that exports pre-rendered Data.
public struct ExportFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.pdf, .html, .rtf, .plainText] }

    public let data: Data
    public let format: ExportFormat

    public init(data: Data, format: ExportFormat) {
        self.data = data
        self.format = format
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.format = .markdown
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    var contentType: UTType {
        switch format {
        case .pdf: .pdf
        case .html: .html
        case .rtf: .rtf
        case .markdown: .plainText
        }
    }
}
