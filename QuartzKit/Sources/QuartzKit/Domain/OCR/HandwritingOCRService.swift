#if canImport(Vision) && canImport(PencilKit)
import Foundation
import Vision
import PencilKit
import CoreGraphics
import os
#if canImport(AppKit)
import AppKit
#endif

/// Service für Handschrift-Erkennung auf PencilKit-Zeichnungen.
///
/// Nutzt `VNRecognizeTextRequest` im Hintergrund um
/// handschriftlichen Text aus Zeichnungen zu extrahieren.
public actor HandwritingOCRService {
    public enum OCRError: LocalizedError, Sendable {
        case renderingFailed
        case recognitionFailed(String)
        case noTextFound

        public var errorDescription: String? {
            switch self {
            case .renderingFailed: String(localized: "Failed to render drawing for OCR.", bundle: .module)
            case .recognitionFailed(let msg): String(localized: "Text recognition failed: \(msg)", bundle: .module)
            case .noTextFound: String(localized: "No text found in drawing.", bundle: .module)
            }
        }
    }

    /// Ergebnis einer OCR-Erkennung.
    public struct OCRResult: Sendable {
        /// Der erkannte Text (alle Zeilen zusammengefügt).
        public let fullText: String
        /// Einzelne erkannte Textblöcke mit Konfidenz.
        public let observations: [TextObservation]

        public init(fullText: String, observations: [TextObservation]) {
            self.fullText = fullText
            self.observations = observations
        }
    }

    /// Ein einzelner erkannter Textblock.
    public struct TextObservation: Sendable {
        public let text: String
        public let confidence: Float

        public init(text: String, confidence: Float) {
            self.text = text
            self.confidence = confidence
        }
    }

    /// Unterstützte Sprachen für die Erkennung.
    public let supportedLanguages: [String]

    public init(languages: [String] = ["de-DE", "en-US"]) {
        self.supportedLanguages = languages
    }

    /// Erkennt Text in einer PencilKit-Zeichnung.
    ///
    /// - Parameter drawing: Die zu analysierende Zeichnung
    /// - Returns: OCRResult mit erkanntem Text
    public func recognizeText(in drawing: PKDrawing) async throws -> OCRResult {
        guard !drawing.bounds.isEmpty else {
            throw OCRError.noTextFound
        }

        // Zeichnung als Bild rendern
        let image = drawing.image(from: drawing.bounds, scale: 2.0)
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else {
            throw OCRError.renderingFailed
        }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.renderingFailed
        }
        #endif

        return try await performOCR(on: cgImage)
    }

    /// Erkennt Text in einem Bild (z.B. gescanntes Dokument).
    public func recognizeText(in cgImage: CGImage) async throws -> OCRResult {
        try await performOCR(on: cgImage)
    }

    // MARK: - Private

    private func performOCR(on cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let didResume = OSAllocatedUnfairLock(initialState: false)

            let request = VNRecognizeTextRequest { request, error in
                let alreadyResumed = didResume.withLock { resumed -> Bool in
                    if resumed { return true }
                    resumed = true
                    return false
                }
                guard !alreadyResumed else { return }

                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                let textObservations = observations.compactMap { observation -> TextObservation? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    return TextObservation(
                        text: topCandidate.string,
                        confidence: topCandidate.confidence
                    )
                }

                let fullText = textObservations.map(\.text).joined(separator: "\n")

                continuation.resume(returning: OCRResult(
                    fullText: fullText,
                    observations: textObservations
                ))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = supportedLanguages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                let alreadyResumed = didResume.withLock { resumed -> Bool in
                    if resumed { return true }
                    resumed = true
                    return false
                }
                guard !alreadyResumed else { return }
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}
#endif
