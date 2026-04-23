import Foundation
import NaturalLanguage
import os
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.quartz", category: "OnDeviceWritingTools")

/// On-device writing tools using Apple’s Foundation Models framework (iOS 26+/macOS 26+),
/// Natural Language, spell checking, and optional configured AI providers.
///
/// Priority:
/// 1. Foundation Models (on-device Apple Intelligence) when available
/// 2. Configured AI provider (OpenAI, Claude, Ollama, etc.)
/// 3. On-device NLP fallback (NLTokenizer, UITextChecker)
public actor OnDeviceWritingToolsService {
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
        case featureUnavailable(String)
        case foundationModelUnavailable
        case noAIProviderConfigured

        public var errorDescription: String? {
            switch self {
            case .notAvailable:
                String(
                    localized: "Writing tools require iOS 18.1, iPadOS 18.1, or macOS 15.1 or later.",
                    bundle: .module
                )
            case .processingFailed(let msg): String(localized: "AI processing failed: \(msg)", bundle: .module)
            case .featureUnavailable(let msg): msg
            case .emptyInput: String(localized: "No text provided for AI processing.", bundle: .module)
            case .foundationModelUnavailable:
                String(
                    localized: "Apple Intelligence is not available on this device. Please configure an AI provider in Settings, or use a device that supports Apple Intelligence.",
                    bundle: .module
                )
            case .noAIProviderConfigured:
                String(
                    localized: "Please configure an AI provider in Settings, or use a device that supports Apple Intelligence.",
                    bundle: .module
                )
            }
        }
    }

    /// Result of an AI processing operation.
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

    // MARK: - Dual-Path Inline AI Router

    /// Routes an inline AI request through the dual-path architecture:
    /// 1. If a custom API key is configured → use AIProvider
    /// 2. Else if Apple Intelligence is available → use Foundation Models
    /// 3. Else → throw noAIProviderConfigured
    ///
    /// - Parameters:
    ///   - instruction: The user's instruction (e.g. "Make it shorter", "Fix grammar")
    ///   - selectedText: The text to transform
    /// - Returns: The transformed text
    public func invokeInlineAI(instruction: String, selectedText: String) async throws -> String {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyInput
        }

        // Path 1: Custom API key available — route to AIProvider
        let hasCustomProvider = await isSelectedProviderUsableForWritingTools()
        if hasCustomProvider {
            logger.info("Inline AI: routing to custom AIProvider")
            let prompt = """
            You are a writing assistant inside a markdown notes app. \
            Apply the following instruction to the text below and return ONLY the modified text. \
            Do not include any explanation, preamble, or formatting beyond the result.

            Instruction: \(instruction)

            Text:
            \(selectedText)
            """
            return try await fallbackToAIProvider(prompt: prompt)
        }

        // Path 2: Apple Intelligence available — route to Foundation Models
        if isAppleIntelligenceAvailable {
            logger.info("Inline AI: routing to Apple Intelligence (Foundation Models)")
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                do {
                    let session = LanguageModelSession()
                    let prompt = """
                    Apply the following instruction to the text below and return ONLY the modified text. \
                    Do not include any explanation.

                    Instruction: \(instruction)

                    Text:
                    \(selectedText)
                    """
                    let response = try await session.respond(to: prompt)
                    return response.content
                } catch {
                    logger.error("Foundation Models inline AI failed: \(error.localizedDescription, privacy: .public)")
                    QuartzDiagnostics.error(
                        category: "OnDeviceWritingTools",
                        "Foundation Models inline AI failed: \(error.localizedDescription)"
                    )
                    throw AIError.foundationModelUnavailable
                }
            }
            #endif
        }

        // Path 3: Nothing available
        logger.warning("Inline AI: no provider or Apple Intelligence available")
        QuartzDiagnostics.warning(
            category: "OnDeviceWritingTools",
            "Inline AI unavailable: no provider or Apple Intelligence available"
        )
        throw AIError.noAIProviderConfigured
    }

    /// Minimum OS version for the bundled writing-tools pipeline (matches availability checks below).
    public var isAvailable: Bool {
        if #available(iOS 18.1, macOS 15.1, *) {
            return true
        }
        return false
    }

    /// Returns true if Apple's Foundation Models (on-device Apple Intelligence) is available.
    /// Checks both OS version and actual model availability on the device.
    public var isFoundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let available = SystemLanguageModel.default.isAvailable
                if available {
                    logger.info("Foundation Models available on this device")
                }
                return available
            }
        }
        #endif
        return false
    }

    /// Returns true if on-device Apple Intelligence can be used for inline AI.
    /// Verifies OS version AND device capability. Safe to call on any platform/version.
    public var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 15.2, iOS 18.2, *) else {
            return false
        }
        return isFoundationModelsAvailable
        #else
        return false
        #endif
    }

    /// Performs an AI action on the given text.
    ///
    /// - Parameters:
    ///   - action: The desired AI action
    ///   - text: The text to process
    ///   - tone: Optional tone (only for .rewrite)
    /// - Returns: AIResult with original and processed text
    public func process(
        action: AIAction,
        text: String,
        tone: Tone? = nil
    ) async throws -> AIResult {
        try await processWithVaultContext(action: action, text: text, tone: tone, contextChunks: [])
    }

    /// Performs an AI action with optional Vault Memory (RAG) context.
    /// Context chunks from semantically similar notes are included in the prompt.
    public func processWithVaultContext(
        action: AIAction,
        text: String,
        tone: Tone? = nil,
        contextChunks: [String] = []
    ) async throws -> AIResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyInput
        }

        guard isAvailable else {
            throw AIError.notAvailable
        }

        let processedText = try await performWritingTools(
            action: action,
            text: text,
            tone: tone,
            contextChunks: contextChunks
        )

        return AIResult(
            originalText: text,
            processedText: processedText,
            action: action,
            tone: tone
        )
    }

    /// Summarizes a long text into bullet points.
    public func summarize(_ text: String) async throws -> AIResult {
        try await process(action: .summarize, text: text)
    }

    /// Rewrites text with an optional tone.
    public func rewrite(_ text: String, tone: Tone = .professional) async throws -> AIResult {
        try await process(action: .rewrite, text: text, tone: tone)
    }

    /// Proofreads text.
    public func proofread(_ text: String) async throws -> AIResult {
        try await process(action: .proofread, text: text)
    }

    // MARK: - Private

    private func performWritingTools(
        action: AIAction,
        text: String,
        tone: Tone?,
        contextChunks: [String] = []
    ) async throws -> String {
        // Priority 1: Try Foundation Models (Apple Intelligence) when available.
        // Wrapped in strict availability + do-catch to handle macOS 26 beta crashes.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                do {
                    logger.info("Attempting Foundation Models for action: \(action.rawValue)")
                    let result = try await performWithFoundationModels(
                        action: action,
                        text: text,
                        tone: tone
                    )
                    logger.info("Foundation Models succeeded for action: \(action.rawValue)")
                    return result
                } catch {
                    // Log the failure but don't crash — fall through to provider path.
                    logger.error("Foundation Models failed: \(error.localizedDescription, privacy: .public). Falling back to AI provider.")
                    QuartzDiagnostics.error(
                        category: "OnDeviceWritingTools",
                        "Foundation Models failed: \(error.localizedDescription). Falling back to AI provider."
                    )
                }
            }
        }
        #endif

        // Priority 2: Try configured AI provider
        let useProvider = await isSelectedProviderUsableForWritingTools()

        if useProvider {
            do {
                return try await performWithAIProvider(
                    action: action,
                    text: text,
                    tone: tone,
                    contextChunks: contextChunks
                )
            } catch {
                if Self.supportsOnDeviceFallback(for: action) {
                    return try await onDeviceProcessingWithoutProvider(action: action, text: text)
                }
                throw error
            }
        }

        // Priority 3: On-device NLP fallback
        return try await onDeviceProcessingWithoutProvider(action: action, text: text)
    }

    // MARK: - Foundation Models (Apple Intelligence)

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func performWithFoundationModels(
        action: AIAction,
        text: String,
        tone: Tone?
    ) async throws -> String {
        let session = LanguageModelSession()

        let prompt: String
        switch action {
        case .summarize:
            prompt = "Summarize the following text into concise bullet points. Keep the same language. Return only the summary:\n\n\(text)"
        case .rewrite:
            let t = tone ?? .professional
            prompt = "Rewrite the following text in a \(t.rawValue) tone. Keep the same language and meaning. Return only the rewritten text:\n\n\(text)"
        case .proofread:
            prompt = "Proofread and correct any grammar, spelling, and punctuation errors in the following text. Keep the same language and meaning. Return only the corrected text:\n\n\(text)"
        case .makeConcise:
            prompt = "Make the following text more concise while preserving all key information. Keep the same language. Return only the concise text:\n\n\(text)"
        case .makeDetailed:
            prompt = "Expand and make the following text more detailed. Keep the same language and tone. Return only the expanded text:\n\n\(text)"
        }

        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    /// Actions that can degrade to Natural Language / spell-check when the provider path fails or is skipped.
    private static func supportsOnDeviceFallback(for action: AIAction) -> Bool {
        switch action {
        case .summarize, .proofread, .makeConcise: true
        case .rewrite, .makeDetailed: false
        }
    }

    private func onDeviceProcessingWithoutProvider(
        action: AIAction,
        text: String
    ) async throws -> String {
        switch action {
        case .summarize:
            return summarizeTextOnDevice(text)
        case .proofread:
            return await proofreadTextOnDevice(text)
        case .makeConcise:
            return makeConciseTextOnDevice(text)
        case .makeDetailed:
            throw AIError.featureUnavailable(
                String(localized: "Text expansion requires an AI provider. Please configure one in Settings.", bundle: .module)
            )
        case .rewrite:
            throw AIError.featureUnavailable(
                String(localized: "Tone rewriting requires an AI provider. Please configure one in Settings.", bundle: .module)
            )
        }
    }

    // MARK: - AI Provider Path

    /// Uses the provider only when it is configured and expected to work: API-key providers need a key;
    /// **Ollama** must be reachable (cached probe or live check when unknown).
    private func isSelectedProviderUsableForWritingTools() async -> Bool {
        let registry = await AIProviderRegistry.shared
        guard let provider = await registry.selectedProvider else { return false }
        guard provider.isConfigured else { return false }
        if provider.id == "ollama" {
            switch provider.reachability {
            case .reachable: return true
            case .unreachable: return false
            case .unknown: return await provider.checkConnection()
            }
        }
        return true
    }

    private func performWithAIProvider(
        action: AIAction,
        text: String,
        tone: Tone?,
        contextChunks: [String] = []
    ) async throws -> String {
        let contextPrefix: String
        if !contextChunks.isEmpty {
            let contextBlock = contextChunks.prefix(10).joined(separator: "\n\n")
            contextPrefix = """
            ## Vault Memory (RAG Context)
            Relevant excerpts from the user's notes vault:
            \(contextBlock)

            ---

            """
        } else {
            contextPrefix = ""
        }

        let prompt: String
        switch action {
        case .summarize:
            prompt = "\(contextPrefix)Summarize the following text into concise bullet points. Keep the same language. Return only the summary:\n\n\(text)"
        case .rewrite:
            let t = tone ?? .professional
            prompt = "\(contextPrefix)Rewrite the following text in a \(t.rawValue) tone. Keep the same language and meaning. Return only the rewritten text:\n\n\(text)"
        case .proofread:
            prompt = "\(contextPrefix)Proofread and correct any grammar, spelling, and punctuation errors in the following text. Keep the same language and meaning. Return only the corrected text:\n\n\(text)"
        case .makeConcise:
            prompt = "\(contextPrefix)Make the following text more concise while preserving all key information. Keep the same language. Return only the concise text:\n\n\(text)"
        case .makeDetailed:
            prompt = "\(contextPrefix)Expand and make the following text more detailed. Keep the same language and tone. Return only the expanded text:\n\n\(text)"
        }
        return try await fallbackToAIProvider(prompt: prompt)
    }

    // MARK: - On-Device NLP Fallback

    private func summarizeTextOnDevice(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }

        let keepCount = max(1, sentences.count * 3 / 10)
        let summary = sentences.prefix(keepCount).joined(separator: " ")
        let header = String(localized: "Summary", bundle: .module)
        return "**\(header):**\n\n\(summary)"
    }

    private func proofreadTextOnDevice(_ text: String) async -> String {
        #if canImport(UIKit)
        return await MainActor.run {
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

            for (corrRange, correction) in corrections.reversed() {
                if let swiftRange = Range(corrRange, in: mutableText) {
                    mutableText.replaceSubrange(swiftRange, with: correction)
                }
            }

            return mutableText
        }
        #elseif canImport(AppKit)
        return await MainActor.run {
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
        }
        #else
        return text
        #endif
    }

    private func makeConciseTextOnDevice(_ text: String) -> String {
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

        let filtered = sentences.filter { $0.count > 15 }
        return (filtered.isEmpty ? sentences : filtered).joined(separator: " ")
    }

    private func fallbackToAIProvider(prompt: String) async throws -> String {
        let registry = await AIProviderRegistry.shared
        guard let provider = await registry.selectedProvider else {
            throw AIError.featureUnavailable(
                String(localized: "This feature requires an AI provider. Please configure one in Settings.", bundle: .module)
            )
        }
        let modelID = await registry.selectedModelID
        let response = try await provider.chat(
            messages: [AIMessage(role: .user, content: prompt)],
            model: modelID,
            temperature: 0.7
        )
        return response.content
    }
}
