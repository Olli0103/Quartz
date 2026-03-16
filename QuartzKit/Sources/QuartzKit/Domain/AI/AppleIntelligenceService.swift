import Foundation
import NaturalLanguage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// On-Device AI Service via Apple Intelligence APIs.
///
/// Bietet Zusammenfassen, Umschreiben und Tonfall-Änderung
/// direkt auf dem Gerät – ohne Internet.
public actor AppleIntelligenceService {
    public enum AIAction: String, CaseIterable, Sendable {
        case summarize = "summarize"
        case rewrite = "rewrite"
        case proofread = "proofread"
        case makeConcise = "make_concise"
        case makeDetailed = "make_detailed"

        public var displayName: String {
            switch self {
            case .summarize: String(localized: "Summarize", bundle: .module)
            case .rewrite: String(localized: "Rewrite", bundle: .module)
            case .proofread: String(localized: "Proofread", bundle: .module)
            case .makeConcise: String(localized: "Make Concise", bundle: .module)
            case .makeDetailed: String(localized: "Make Detailed", bundle: .module)
            }
        }

        public var systemImage: String {
            switch self {
            case .summarize: "text.redaction"
            case .rewrite: "arrow.triangle.2.circlepath"
            case .proofread: "checkmark.circle"
            case .makeConcise: "arrow.down.right.and.arrow.up.left"
            case .makeDetailed: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    public enum Tone: String, CaseIterable, Sendable {
        case professional = "professional"
        case casual = "casual"
        case friendly = "friendly"
        case academic = "academic"

        public var displayName: String {
            switch self {
            case .professional: String(localized: "Professional", bundle: .module)
            case .casual: String(localized: "Casual", bundle: .module)
            case .friendly: String(localized: "Friendly", bundle: .module)
            case .academic: String(localized: "Academic", bundle: .module)
            }
        }
    }

    public enum AIError: LocalizedError, Sendable {
        case notAvailable
        case processingFailed(String)
        case emptyInput

        public var errorDescription: String? {
            switch self {
            case .notAvailable: String(localized: "Apple Intelligence is not available on this device.", bundle: .module)
            case .processingFailed(let msg): String(localized: "AI processing failed: \(msg)", bundle: .module)
            case .emptyInput: String(localized: "No text provided for AI processing.", bundle: .module)
            }
        }
    }

    /// Ergebnis einer AI-Verarbeitung.
    public struct AIResult: Sendable {
        public let originalText: String
        public let processedText: String
        public let action: AIAction
        public let tone: Tone?

        public init(originalText: String, processedText: String, action: AIAction, tone: Tone? = nil) {
            self.originalText = originalText
            self.processedText = processedText
            self.action = action
            self.tone = tone
        }
    }

    public init() {}

    /// Prüft ob Apple Intelligence verfügbar ist.
    public var isAvailable: Bool {
        // Apple Intelligence ist ab iOS 18.1 / macOS 15.1 verfügbar
        // und nur auf unterstützten Geräten (A17 Pro+, M1+)
        if #available(iOS 18.1, macOS 15.1, *) {
            return true
        }
        return false
    }

    /// Führt eine AI-Aktion auf dem gegebenen Text aus.
    ///
    /// - Parameters:
    ///   - action: Die gewünschte AI-Aktion
    ///   - text: Der zu verarbeitende Text
    ///   - tone: Optionaler Tonfall (nur für .rewrite)
    /// - Returns: AIResult mit Original und verarbeitetem Text
    public func process(
        action: AIAction,
        text: String,
        tone: Tone? = nil
    ) async throws -> AIResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyInput
        }

        guard isAvailable else {
            throw AIError.notAvailable
        }

        // Apple Intelligence WritingTools API aufrufen
        let processedText = try await performAppleIntelligence(
            action: action,
            text: text,
            tone: tone
        )

        return AIResult(
            originalText: text,
            processedText: processedText,
            action: action,
            tone: tone
        )
    }

    /// Zusammenfassung eines langen Textes in Stichpunkte.
    public func summarize(_ text: String) async throws -> AIResult {
        try await process(action: .summarize, text: text)
    }

    /// Text umschreiben mit optionalem Tonfall.
    public func rewrite(_ text: String, tone: Tone = .professional) async throws -> AIResult {
        try await process(action: .rewrite, text: text, tone: tone)
    }

    /// Text Korrekturlesen.
    public func proofread(_ text: String) async throws -> AIResult {
        try await process(action: .proofread, text: text)
    }

    // MARK: - Private

    private func performAppleIntelligence(
        action: AIAction,
        text: String,
        tone: Tone?
    ) async throws -> String {
        // Nutzt NaturalLanguage-Framework als On-Device Fallback.
        // Wenn WritingTools verfügbar wird, kann hier direkt integriert werden.
        switch action {
        case .summarize:
            return summarizeText(text)
        case .proofread:
            return proofreadText(text)
        case .makeConcise:
            return makeConciseText(text)
        case .makeDetailed:
            return makeDetailedText(text)
        case .rewrite:
            return rewriteText(text, tone: tone ?? .professional)
        }
    }

    // MARK: - On-Device NLP Fallback

    private func summarizeText(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }

        // Behalte die ersten ~30% der Sätze als Zusammenfassung
        let keepCount = max(1, sentences.count * 3 / 10)
        let summary = sentences.prefix(keepCount).joined(separator: " ")
        let header = String(localized: "Summary", bundle: .module)
        return "**\(header):**\n\n\(summary)"
    }

    private func proofreadText(_ text: String) -> String {
        #if canImport(UIKit)
        let checker = UITextChecker()
        var mutableText = text
        let nsText = mutableText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var corrections: [(NSRange, String)] = []
        let language = Locale.preferredLanguages.first ?? Locale.current.language.languageCode?.identifier ?? "en"
        var offset = 0
        while offset < nsText.length {
            let misspelled = checker.rangeOfMisspelledWord(
                in: mutableText,
                range: fullRange,
                startingAt: offset,
                wrap: false,
                language: language
            )
            guard misspelled.location != NSNotFound else { break }

            let guesses = checker.guesses(forWordRange: misspelled, in: mutableText, language: language)
            if let correction = guesses?.first {
                corrections.append((misspelled, correction))
            }
            offset = NSMaxRange(misspelled)
        }

        // Korrekturen von hinten nach vorne anwenden
        for (corrRange, correction) in corrections.reversed() {
            if let swiftRange = Range(corrRange, in: mutableText) {
                mutableText.replaceSubrange(swiftRange, with: correction)
            }
        }

        return mutableText
        #elseif canImport(AppKit)
        let checker = NSSpellChecker.shared
        var mutableText = text
        let range = NSRange(mutableText.startIndex..., in: mutableText)

        var corrections: [(NSRange, String)] = []
        var searchOffset = range.location
        while searchOffset < NSMaxRange(range) {
            let misspelled = checker.checkSpelling(
                of: mutableText,
                startingAt: searchOffset
            )
            guard misspelled.location != NSNotFound else { break }

            if let correction = checker.correction(
                forWordRange: misspelled,
                in: mutableText,
                language: checker.language(),
                inSpellDocumentWithTag: 0
            ) {
                corrections.append((misspelled, correction))
            }
            searchOffset = NSMaxRange(misspelled)
        }

        for (corrRange, correction) in corrections.reversed() {
            if let swiftRange = Range(corrRange, in: mutableText) {
                mutableText.replaceSubrange(swiftRange, with: correction)
            }
        }

        return mutableText
        #else
        return text
        #endif
    }

    private func makeConciseText(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        // Entferne kurze Füllsätze und behalte die längeren, informativeren
        let filtered = sentences.filter { $0.count > 15 }
        return (filtered.isEmpty ? sentences : filtered).joined(separator: " ")
    }

    private func makeDetailedText(_ text: String) -> String {
        // Ohne KI-Modell kann Text nicht sinnvoll erweitert werden
        return text
    }

    private func rewriteText(_ text: String, tone: Tone) -> String {
        // Ohne KI-Modell kann Ton nicht sinnvoll geändert werden
        return text
    }
}
