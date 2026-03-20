import Foundation

/// Cache duration for the AI briefing to avoid battery drain and API limits.
private let briefingCacheDuration: TimeInterval = 4 * 60 * 60 // 4 hours

/// Generates an AI-powered weekly briefing from recent vault notes.
/// Caches results for 4 hours per vault (process-wide) so reopening the Dashboard does not discard the cache.
public actor DashboardBriefingService {
    private let providerRegistry: AIProviderRegistry

    private static var sharedCachedBriefing: String?
    private static var sharedCachedAt: Date?
    private static var sharedCachedVaultKey: String?

    public init(providerRegistry: AIProviderRegistry = .shared) {
        self.providerRegistry = providerRegistry
    }

    /// Generates a brief summary of recent work for the morning command center.
    /// Returns cached briefing if within 4 hours for the same vault; otherwise generates and caches.
    /// Returns nil if no usable AI provider or no notes to summarize.
    public func generateWeeklyBriefing(
        recentNoteContents: [(title: String, body: String)],
        vaultRoot: URL
    ) async throws -> String? {
        let vaultKey = vaultRoot.standardizedFileURL.path(percentEncoded: false)
        if let cached = Self.sharedCachedBriefing,
           let at = Self.sharedCachedAt,
           Self.sharedCachedVaultKey == vaultKey,
           Date().timeIntervalSince(at) < briefingCacheDuration {
            return cached
        }
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider, provider.isConfigured else { return nil }
        guard !recentNoteContents.isEmpty else { return nil }

        let contextLimit = 8_000
        var contextLines: [String] = []
        var totalLen = 0
        for (title, body) in recentNoteContents {
            let preview = String(body.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
            let block = "[\(title)]\n\(preview)\n"
            if totalLen + block.count > contextLimit { break }
            contextLines.append(block)
            totalLen += block.count
        }
        let context = contextLines.joined(separator: "\n---\n\n")

        let systemPrompt = """
        You are a helpful assistant for a note-taking app. The user wants a brief "morning briefing" summarizing their recent work from their notes vault.

        ## Recent Notes (excerpts)
        \(context)

        ## Instructions
        - Write a concise 2–4 paragraph summary of what the user has been working on.
        - Highlight key themes, projects, or ideas.
        - Use a warm, encouraging tone.
        - Respond in the same language as the notes.
        - Do not invent content; only summarize what is present.
        """

        let messages: [AIMessage] = [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user, content: "Generate my morning briefing based on these recent notes.")
        ]

        let response = try await provider.chat(
            messages: messages,
            model: modelID,
            temperature: 0.4
        )
        Self.sharedCachedBriefing = response.content
        Self.sharedCachedAt = Date()
        Self.sharedCachedVaultKey = vaultKey
        return response.content
    }
}
