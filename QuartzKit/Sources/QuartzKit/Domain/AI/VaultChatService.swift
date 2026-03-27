import Foundation

/// "Chat with the Vault": Semantic search + AI response with source citations.
///
/// Flow: Question → relevant chunks via vector search → context to AI → response with sources.
public actor VaultChatService {
    private let embeddingService: VectorEmbeddingService
    private let providerRegistry: AIProviderRegistry

    /// Maximum number of chunks as context.
    private let maxContextChunks = 8

    public init(
        embeddingService: VectorEmbeddingService,
        providerRegistry: AIProviderRegistry
    ) {
        self.embeddingService = embeddingService
        self.providerRegistry = providerRegistry
    }

    /// Asks a question to the entire vault.
    ///
    /// - Parameters:
    ///   - question: The user's question
    ///   - chatHistory: Previous chat messages
    ///   - noteResolver: Closure that resolves noteID → title
    /// - Returns: VaultAnswer with response and sources
    public func ask(
        _ question: String,
        chatHistory: [AIMessage] = [],
        noteResolver: @Sendable (UUID) -> String?
    ) async throws -> VaultAnswer {
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else {
            throw VaultChatError.noProviderConfigured
        }

        // 1. Semantic search — uses low threshold for NLEmbedding compatibility
        let indexedCount = await embeddingService.entryCount
        guard indexedCount > 0 else {
            throw VaultChatError.indexEmpty
        }

        var searchResults = await embeddingService.search(
            query: question,
            limit: maxContextChunks,
            threshold: 0.1
        )

        // Fallback: take top chunks regardless of threshold
        if searchResults.isEmpty {
            searchResults = await embeddingService.search(
                query: question,
                limit: 5,
                threshold: 0.0
            )
        }

        guard !searchResults.isEmpty else {
            throw VaultChatError.noRelevantContent
        }

        // 2. Collect sources
        let sources = buildSources(from: searchResults, noteResolver: noteResolver)

        // 3. Build context
        let contextString = searchResults.enumerated().map { i, result in
            let title = noteResolver(result.entry.noteID) ?? String(localized: "Unknown Note", bundle: .module)
            return """
            [Source \(i + 1): \(title)]
            \(result.entry.chunkText)
            """
        }.joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You are a helpful assistant for a note-taking app called Quartz.
        The user is asking a question about their notes vault.

        ## Relevant Notes Context
        \(contextString)

        ## Instructions
        - Answer based ONLY on the provided context from the user's notes.
        - Reference sources using [Source N] notation.
        - If the context doesn't contain enough information, say so.
        - Respond in the same language the user writes in.
        - Use Markdown formatting.
        - Keep responses concise and well-structured.
        """

        // 4. Generate AI response
        var messages: [AIMessage] = [
            AIMessage(role: .system, content: systemPrompt)
        ]
        messages.append(contentsOf: chatHistory)
        messages.append(AIMessage(role: .user, content: question))

        let response = try await provider.chat(
            messages: messages,
            model: modelID,
            temperature: 0.5
        )

        return VaultAnswer(
            answer: response.content,
            sources: sources,
            searchResults: searchResults
        )
    }

    // MARK: - Private

    /// Estimates token count from character count (1 token ≈ 4 chars).
    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Streaming variant — returns the citation array and a token stream.
    ///
    /// Performs retrieval + prompt construction synchronously within this actor,
    /// then calls `provider.streamChat()`. Citations are known before streaming
    /// begins because they are built from the search results.
    ///
    /// Uses token budgeting: context gets 40% of available window, history 30%,
    /// response headroom is 4096 tokens, 5% safety margin.
    public func streamAsk(
        _ question: String,
        chatHistory: [AIMessage] = [],
        noteResolver: @Sendable (UUID) -> String?
    ) async throws -> (citations: [Citation], stream: AsyncThrowingStream<String, Error>) {
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else {
            throw VaultChatError.noProviderConfigured
        }

        // 1. Semantic search — uses low threshold for NLEmbedding compatibility
        let indexedCount = await embeddingService.entryCount
        guard indexedCount > 0 else {
            throw VaultChatError.indexEmpty
        }

        var searchResults = await embeddingService.search(
            query: question,
            limit: maxContextChunks,
            threshold: 0.1
        )

        // Fallback: take top chunks regardless of threshold
        if searchResults.isEmpty {
            searchResults = await embeddingService.search(
                query: question,
                limit: 5,
                threshold: 0.0
            )
        }

        guard !searchResults.isEmpty else {
            throw VaultChatError.noRelevantContent
        }

        // 2. Deduplicate: max 2 chunks per note, take top 5
        var chunksByNote: [UUID: Int] = [:]
        var filteredResults: [VectorEmbeddingService.SearchResult] = []
        for result in searchResults {
            let noteID = result.entry.noteID
            let count = chunksByNote[noteID, default: 0]
            guard count < 2 else { continue }
            chunksByNote[noteID] = count + 1
            filteredResults.append(result)
            if filteredResults.count >= 5 { break }
        }

        // 3. Build Citation array (known before streaming starts)
        let citations: [Citation] = filteredResults.enumerated().map { i, result in
            Citation(
                id: i + 1,
                noteID: result.entry.noteID,
                noteTitle: noteResolver(result.entry.noteID) ?? "Unknown Note",
                excerpt: String(result.entry.chunkText.prefix(200)),
                similarity: result.similarity
            )
        }

        // 4. Build context string with [Source N] labels
        let contextString = filteredResults.enumerated().map { i, result in
            let title = noteResolver(result.entry.noteID) ?? "Unknown Note"
            return """
            [Source \(i + 1): \(title)]
            \(result.entry.chunkText)
            """
        }.joined(separator: "\n\n---\n\n")

        // 5. System prompt
        let systemInstructions = """
        You are a helpful assistant for a note-taking app called Quartz.
        The user is asking a question about their notes vault.

        ## Retrieved Notes

        \(contextString)

        ## Instructions
        - Answer based ONLY on the provided context from the user's notes.
        - When using information from a source, cite it as [Source N].
        - You may cite multiple sources in one statement: [Source 1][Source 3].
        - If the context does not contain enough information, say so clearly.
        - Respond in the same language the user writes in.
        - Use Markdown formatting.
        - Keep responses concise and well-structured.
        - Do NOT fabricate information not present in the sources.
        """

        // 6. Token budget management
        let allModels = await providerRegistry.allModels(for: provider.id)
        let contextWindow = allModels.first(where: { $0.id == (modelID ?? "") })?.contextWindow ?? 128_000
        let responseReserve = 4096
        let safetyMargin = contextWindow / 20 // 5%
        let systemTokens = estimateTokens(systemInstructions)
        let available = contextWindow - systemTokens - responseReserve - safetyMargin
        let historyBudget = available * 30 / 100 // 30%

        // Trim history: newest first, drop oldest if over budget
        var trimmedHistory: [AIMessage] = []
        var historyTokensUsed = 0
        for message in chatHistory.reversed() {
            let msgTokens = estimateTokens(message.content)
            if historyTokensUsed + msgTokens > historyBudget { break }
            trimmedHistory.insert(message, at: 0)
            historyTokensUsed += msgTokens
        }

        // 7. Assemble messages
        var messages: [AIMessage] = [
            AIMessage(role: .system, content: systemInstructions)
        ]
        messages.append(contentsOf: trimmedHistory)
        messages.append(AIMessage(role: .user, content: question))

        // 8. Stream
        let stream = provider.streamChat(
            messages: messages,
            model: modelID,
            temperature: 0.5
        )

        return (citations: citations, stream: stream)
    }

    private func buildSources(
        from results: [VectorEmbeddingService.SearchResult],
        noteResolver: (UUID) -> String?
    ) -> [VaultSource] {
        var seenNotes = Set<UUID>()
        var sources: [VaultSource] = []

        for result in results {
            let noteID = result.entry.noteID
            guard !seenNotes.contains(noteID) else { continue }
            seenNotes.insert(noteID)

            sources.append(VaultSource(
                noteID: noteID,
                noteTitle: noteResolver(noteID) ?? String(localized: "Unknown", bundle: .module),
                relevance: result.similarity,
                excerpt: String(result.entry.chunkText.prefix(200))
            ))
        }

        return sources
    }
}

// MARK: - Models

/// Response to a vault question.
public struct VaultAnswer: Sendable {
    /// The AI-generated response.
    public let answer: String
    /// Source citations (referenced notes).
    public let sources: [VaultSource]
    /// The underlying search results.
    public let searchResults: [VectorEmbeddingService.SearchResult]

    public init(
        answer: String,
        sources: [VaultSource],
        searchResults: [VectorEmbeddingService.SearchResult]
    ) {
        self.answer = answer
        self.sources = sources
        self.searchResults = searchResults
    }
}

/// A source in a vault response.
public struct VaultSource: Identifiable, Sendable {
    public let id = UUID()
    public let noteID: UUID
    public let noteTitle: String
    public let relevance: Float
    public let excerpt: String

    public init(noteID: UUID, noteTitle: String, relevance: Float, excerpt: String) {
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.relevance = relevance
        self.excerpt = excerpt
    }
}

/// A message in the vault chat.
public struct VaultChatMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: Role
    public let content: String
    public let sources: [VaultSource]
    public let timestamp = Date()

    public enum Role: Sendable {
        case user
        case assistant
    }

    public init(role: Role, content: String, sources: [VaultSource]) {
        self.role = role
        self.content = content
        self.sources = sources
    }
}

// MARK: - Errors

public enum VaultChatError: LocalizedError, Sendable {
    case noProviderConfigured
    case noRelevantContent
    case indexEmpty
    case providerError(String)

    public var errorDescription: String? {
        switch self {
        case .noProviderConfigured: String(localized: "No AI provider configured. Add an API key in Settings.", bundle: .module)
        case .noRelevantContent: String(localized: "No relevant notes found for your question. Try rephrasing.", bundle: .module)
        case .indexEmpty: String(localized: "No notes have been indexed yet. Please index your vault first.", bundle: .module)
        case .providerError(let msg): String(localized: "AI error: \(msg)", bundle: .module)
        }
    }
}
