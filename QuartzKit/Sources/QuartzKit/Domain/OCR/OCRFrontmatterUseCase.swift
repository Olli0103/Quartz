#if canImport(PencilKit) && canImport(Vision)
import Foundation
import PencilKit

/// Use case: Store OCR text from drawings in frontmatter.
///
/// Automatically performs OCR after drawing and stores
/// the recognized text in the `ocr_text` field of the frontmatter.
/// The text is invisible to the user but searchable.
public actor OCRFrontmatterUseCase {
    private let ocrService: HandwritingOCRService
    private let vaultProvider: any VaultProviding
    private let drawingStorage: DrawingStorageService

    public init(
        vaultProvider: any VaultProviding,
        ocrService: HandwritingOCRService? = nil,
        drawingStorage: DrawingStorageService? = nil,
        languages: [String] = ["de-DE", "en-US"]
    ) {
        self.ocrService = ocrService ?? HandwritingOCRService(languages: languages)
        self.vaultProvider = vaultProvider
        self.drawingStorage = drawingStorage ?? DrawingStorageService()
    }

    /// Performs OCR on a drawing and updates the frontmatter.
    ///
    /// - Parameters:
    ///   - drawing: The PencilKit drawing
    ///   - drawingID: ID of the drawing
    ///   - noteURL: URL of the associated note
    public func processDrawing(
        _ drawing: sending PKDrawing,
        drawingID: String,
        noteURL: URL
    ) async throws {
        // 1. Perform OCR
        let result = try await ocrService.recognizeText(in: drawing)

        // 2. Read note
        var note = try await vaultProvider.readNote(at: noteURL)

        // 3. Store OCR text in frontmatter
        let existingOCR = note.frontmatter.ocrText ?? ""
        let drawingMarker = "[\(drawingID)]"

        // Replace existing OCR text for this drawing or append
        let updatedOCR: String
        if existingOCR.contains(drawingMarker) {
            // Replace existing block
            updatedOCR = replaceOCRBlock(
                in: existingOCR,
                marker: drawingMarker,
                newText: result.fullText
            )
        } else {
            // Append new block
            if existingOCR.isEmpty {
                updatedOCR = "\(drawingMarker) \(result.fullText)"
            } else {
                updatedOCR = "\(existingOCR)\n\(drawingMarker) \(result.fullText)"
            }
        }

        note.frontmatter.ocrText = updatedOCR

        // 4. Write note back
        try await vaultProvider.saveNote(note)
    }

    /// Result of a batch OCR processing.
    public struct BatchResult: Sendable {
        /// Number of successfully processed drawings.
        public let succeeded: Int
        /// Errors per drawing ID, if any occurred.
        public let failures: [(drawingID: String, error: String)]

        public var hasFailures: Bool { !failures.isEmpty }
    }

    /// Performs OCR on all drawings of a note.
    ///
    /// - Returns: BatchResult with success/failure counts.
    @discardableResult
    public func processAllDrawings(for noteURL: URL) async throws -> BatchResult {
        let drawingIDs = try await drawingStorage.listDrawings(for: noteURL)
        var succeeded = 0
        var failures: [(drawingID: String, error: String)] = []

        for drawingID in drawingIDs {
            do {
                let drawing = try await drawingStorage.load(drawingID: drawingID, noteURL: noteURL)
                try await processDrawing(drawing, drawingID: drawingID, noteURL: noteURL)
                succeeded += 1
            } catch {
                failures.append((drawingID: drawingID, error: error.localizedDescription))
            }
        }

        return BatchResult(succeeded: succeeded, failures: failures)
    }

    /// Removes OCR text for a deleted drawing.
    public func removeOCR(drawingID: String, noteURL: URL) async throws {
        var note = try await vaultProvider.readNote(at: noteURL)

        guard let existingOCR = note.frontmatter.ocrText else { return }

        let drawingMarker = "[\(drawingID)]"
        let updatedOCR = removeOCRBlock(in: existingOCR, marker: drawingMarker)

        note.frontmatter.ocrText = updatedOCR.isEmpty ? nil : updatedOCR
        try await vaultProvider.saveNote(note)
    }

    // MARK: - Private

    private func replaceOCRBlock(in text: String, marker: String, newText: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var replaced = false

        for line in lines {
            if line.hasPrefix(marker) {
                result.append("\(marker) \(newText)")
                replaced = true
            } else {
                result.append(line)
            }
        }

        if !replaced {
            result.append("\(marker) \(newText)")
        }

        return result.joined(separator: "\n")
    }

    private func removeOCRBlock(in text: String, marker: String) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines
            .filter { !$0.hasPrefix(marker) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
