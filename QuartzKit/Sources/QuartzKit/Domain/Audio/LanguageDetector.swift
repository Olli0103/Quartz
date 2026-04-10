import Foundation
import NaturalLanguage

/// Language detection service using `NLLanguageRecognizer`.
///
/// Detects the dominant language and confidence from a text sample.
/// Used to auto-select speech recognition locale during recording.
///
/// - Linear: OLL-44 (Language detection for multi-language transcription)
public actor LanguageDetector {

    public struct DetectionResult: Sendable {
        public let languageCode: String
        public let confidence: Double

        public init(languageCode: String, confidence: Double) {
            self.languageCode = languageCode
            self.confidence = confidence
        }
    }

    public init() {}

    /// Common languages supported by NLLanguageRecognizer.
    public var supportedLanguages: [String] {
        ["en", "de", "es", "fr", "ja", "zh", "it", "pt", "ru", "ko", "ar", "nl"]
    }

    /// Detects the dominant language from the provided text.
    ///
    /// - Parameter text: Text sample to analyze
    /// - Returns: DetectionResult with language code and confidence
    public func detectLanguage(from text: String) -> DetectionResult {
        guard !text.isEmpty else {
            return DetectionResult(languageCode: "und", confidence: 0)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let language = recognizer.dominantLanguage {
            let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
            let confidence = hypotheses[language] ?? 0.5
            return DetectionResult(languageCode: language.rawValue, confidence: confidence)
        }

        return DetectionResult(languageCode: "und", confidence: 0)
    }
}
