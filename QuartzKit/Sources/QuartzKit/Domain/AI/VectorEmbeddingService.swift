import Foundation
import NaturalLanguage
import Accelerate

// MARK: - Embedding Entry

/// Ein Eintrag im Vektor-Index.
public struct EmbeddingEntry: Codable, Sendable {
    public let noteID: UUID
    public let chunkIndex: Int
    public let chunkText: String
    public let embedding: [Float]
    public let lastUpdated: Date

    public init(noteID: UUID, chunkIndex: Int, chunkText: String, embedding: [Float], lastUpdated: Date = Date()) {
        self.noteID = noteID
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
        self.embedding = embedding
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Vector Embedding Service

/// Service für lokale Vektor-Embeddings und semantische Suche.
///
/// Nutzt `NLEmbedding` für On-Device-Embeddings und
/// `Accelerate` für effiziente Cosine Similarity.
/// Speicherung als binärer Index in `.quartz/embeddings.idx`.
public actor VectorEmbeddingService {
    private var index: [EmbeddingEntry] = []
    private let indexURL: URL
    private let chunkSize: Int
    private let language: NLLanguage

    /// Dimension der Embedding-Vektoren.
    public var embeddingDimension: Int { 512 }

    public init(
        vaultURL: URL,
        chunkSize: Int = 512,
        language: NLLanguage = .german
    ) {
        self.indexURL = vaultURL
            .appending(path: ".quartz")
            .appending(path: "embeddings.idx")
        self.chunkSize = chunkSize
        self.language = language
    }

    // MARK: - Index Management

    /// Lädt den Embedding-Index von Disk.
    public func loadIndex() throws {
        guard FileManager.default.fileExists(atPath: indexURL.path()) else {
            index = []
            return
        }

        let data = try Data(contentsOf: indexURL)
        index = try JSONDecoder().decode([EmbeddingEntry].self, from: data)
    }

    /// Speichert den Embedding-Index auf Disk.
    public func saveIndex() throws {
        let dir = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    /// Indexiert eine Notiz: Text chunken → Embeddings erzeugen → speichern.
    public func indexNote(noteID: UUID, content: String) throws {
        // Alte Einträge entfernen
        index.removeAll { $0.noteID == noteID }

        // Text in Chunks aufteilen
        let chunks = chunkText(content)

        // Embeddings erzeugen
        for (i, chunk) in chunks.enumerated() {
            if let embedding = generateEmbedding(for: chunk) {
                let entry = EmbeddingEntry(
                    noteID: noteID,
                    chunkIndex: i,
                    chunkText: chunk,
                    embedding: embedding
                )
                index.append(entry)
            }
        }
    }

    /// Entfernt alle Embeddings einer Notiz.
    public func removeNote(_ noteID: UUID) {
        index.removeAll { $0.noteID == noteID }
    }

    // MARK: - Semantic Search

    /// Sucht semantisch ähnliche Chunks.
    ///
    /// - Parameters:
    ///   - query: Die Suchanfrage
    ///   - limit: Maximale Anzahl Ergebnisse
    ///   - threshold: Minimale Cosine Similarity (0.0-1.0)
    /// - Returns: Sortierte Ergebnisse (höchste Similarity zuerst)
    public func search(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.3
    ) -> [SearchResult] {
        guard let queryEmbedding = generateEmbedding(for: query) else {
            return []
        }

        var results: [SearchResult] = []

        for entry in index {
            let similarity = cosineSimilarity(queryEmbedding, entry.embedding)
            if similarity >= threshold {
                results.append(SearchResult(
                    entry: entry,
                    similarity: similarity
                ))
            }
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    /// Anzahl der indexierten Chunks.
    public var entryCount: Int { index.count }

    /// Alle indexierten Notiz-IDs.
    public var indexedNoteIDs: Set<UUID> {
        Set(index.map(\.noteID))
    }

    // MARK: - Search Result

    public struct SearchResult: Sendable {
        public let entry: EmbeddingEntry
        public let similarity: Float

        public init(entry: EmbeddingEntry, similarity: Float) {
            self.entry = entry
            self.similarity = similarity
        }
    }

    // MARK: - Private

    /// Teilt Text in Chunks von ca. `chunkSize` Zeichen auf.
    private func chunkText(_ text: String) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentLength = 0

        for word in words {
            if currentLength + word.count + 1 > chunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: " "))
                // Overlap: letzte 20% behalten
                let overlapCount = max(1, currentChunk.count / 5)
                currentChunk = Array(currentChunk.suffix(overlapCount))
                currentLength = currentChunk.joined(separator: " ").count
            }
            currentChunk.append(word)
            currentLength += word.count + 1
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }

        return chunks
    }

    /// Erzeugt ein Embedding mit NLEmbedding.
    private var cachedEmbedding: NLEmbedding?

    private func getEmbedding() -> NLEmbedding? {
        if let cached = cachedEmbedding { return cached }
        cachedEmbedding = NLEmbedding.sentenceEmbedding(for: language)
        return cachedEmbedding
    }

    private func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = getEmbedding(),
              let vector = embedding.vector(for: text) else {
            return nil
        }
        return vector.map { Float($0) }
    }

    /// Berechnet Cosine Similarity via Accelerate Framework.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
