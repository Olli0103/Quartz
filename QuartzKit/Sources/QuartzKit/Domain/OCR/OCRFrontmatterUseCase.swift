#if canImport(PencilKit) && canImport(Vision)
import Foundation
import PencilKit

/// Use Case: OCR-Text aus Zeichnungen in Frontmatter speichern.
///
/// Führt automatisch nach dem Zeichnen OCR durch und speichert
/// den erkannten Text im `ocr_text` Feld der Frontmatter.
/// Der Text ist unsichtbar für den User, aber durchsuchbar.
public actor OCRFrontmatterUseCase {
    private let ocrService: HandwritingOCRService
    private let vaultProvider: any VaultProviding
    private let drawingStorage: DrawingStorageService

    public init(
        vaultProvider: any VaultProviding,
        languages: [String] = ["de-DE", "en-US"]
    ) {
        self.ocrService = HandwritingOCRService(languages: languages)
        self.vaultProvider = vaultProvider
        self.drawingStorage = DrawingStorageService()
    }

    /// Führt OCR auf einer Zeichnung durch und aktualisiert die Frontmatter.
    ///
    /// - Parameters:
    ///   - drawing: Die PencilKit-Zeichnung
    ///   - drawingID: ID der Zeichnung
    ///   - noteURL: URL der zugehörigen Notiz
    public func processDrawing(
        _ drawing: PKDrawing,
        drawingID: String,
        noteURL: URL
    ) async throws {
        // 1. OCR durchführen
        let result = try await ocrService.recognizeText(in: drawing)

        // 2. Notiz lesen
        var note = try await vaultProvider.readNote(at: noteURL)

        // 3. OCR-Text in Frontmatter speichern
        let existingOCR = note.frontmatter.ocrText ?? ""
        let drawingMarker = "[\(drawingID)]"

        // Bestehenden OCR-Text für diese Zeichnung ersetzen oder anhängen
        let updatedOCR: String
        if existingOCR.contains(drawingMarker) {
            // Ersetze bestehenden Block
            updatedOCR = replaceOCRBlock(
                in: existingOCR,
                marker: drawingMarker,
                newText: result.fullText
            )
        } else {
            // Neuen Block anhängen
            if existingOCR.isEmpty {
                updatedOCR = "\(drawingMarker) \(result.fullText)"
            } else {
                updatedOCR = "\(existingOCR)\n\(drawingMarker) \(result.fullText)"
            }
        }

        note.frontmatter.ocrText = updatedOCR

        // 4. Notiz zurückschreiben
        try await vaultProvider.saveNote(note)
    }

    /// Ergebnis einer Batch-OCR-Verarbeitung.
    public struct BatchResult: Sendable {
        /// Anzahl erfolgreich verarbeiteter Zeichnungen.
        public let succeeded: Int
        /// Fehler pro Zeichnungs-ID, falls aufgetreten.
        public let failures: [(drawingID: String, error: String)]

        public var hasFailures: Bool { !failures.isEmpty }
    }

    /// Führt OCR auf allen Zeichnungen einer Notiz durch.
    ///
    /// - Returns: BatchResult mit Erfolgs-/Fehlerzählung.
    @discardableResult
    public func processAllDrawings(for noteURL: URL) async throws -> BatchResult {
        let drawingIDs = await drawingStorage.listDrawings(for: noteURL)
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

    /// Entfernt OCR-Text für eine gelöschte Zeichnung.
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
