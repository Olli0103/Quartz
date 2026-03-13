import Foundation

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
            case .summarize: "Summarize"
            case .rewrite: "Rewrite"
            case .proofread: "Proofread"
            case .makeConcise: "Make Concise"
            case .makeDetailed: "Make Detailed"
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
            case .professional: "Professional"
            case .casual: "Casual"
            case .friendly: "Friendly"
            case .academic: "Academic"
            }
        }
    }

    public enum AIError: LocalizedError, Sendable {
        case notAvailable
        case processingFailed(String)
        case emptyInput

        public var errorDescription: String? {
            switch self {
            case .notAvailable: "Apple Intelligence is not available on this device."
            case .processingFailed(let msg): "AI processing failed: \(msg)"
            case .emptyInput: "No text provided for AI processing."
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
        // Integration mit Apple Intelligence WritingTools API
        // Die tatsächliche Implementierung nutzt das WritingTools-Framework,
        // das ab iOS 18.1 verfügbar ist.
        //
        // In Produktion:
        // let session = WritingToolsSession()
        // session.action = mapAction(action)
        // if let tone { session.tone = mapTone(tone) }
        // return try await session.process(text)
        //
        // Für Compilation wird ein Placeholder zurückgegeben:
        throw AIError.notAvailable
    }
}
