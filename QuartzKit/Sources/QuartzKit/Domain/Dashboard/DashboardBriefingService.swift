import Foundation

/// Cache duration for the AI briefing to avoid battery drain and API limits.
private let briefingCacheDuration: TimeInterval = 4 * 60 * 60 // 4 hours

/// Generates an AI-powered weekly briefing from recent vault notes.
/// Caches results for 4 hours to avoid regenerating on every view appear.
public actor DashboardBriefingService {
    private let vaultProvider: any VaultProviding
    private let providerRegistry: AIProviderRegistry
    private var cachedBriefing: String?
    private var cachedAt: Date?

    public init(
        vaultProvider: any VaultProviding,
        providerRegistry: AIProviderRegistry = .shared
    ) {
        self.vaultProvider = vaultProvider
        self.providerRegistry = providerRegistry
    }

    /// Generates a brief summary of recent work for the morning command center.
    /// Returns cached briefing if within 4 hours; otherwise generates and caches.
    /// Returns nil if no AI provider is configured or no notes to summarize.
    public func generateWeeklyBriefing(recentNoteContents: [(title: String, body: String)]) async throws -> String? {
        if let cached = cachedBriefing, let at = cachedAt, Date().timeIntervalSince(at) < briefingCacheDuration {
            return cached
        }
        let provider = await providerRegistry.selectedProvider
        let modelID = await providerRegistry.selectedModelID

        guard let provider else { return nil }
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
        cachedBriefing = response.content
        cachedAt = Date()
        return response.content
    }
}
