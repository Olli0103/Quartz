import Foundation

/// Shared settings boundary for knowledge-analysis features.
///
/// KG5 keeps note-to-note related-note similarity separate from AI concept extraction.
/// The systems are still not fully converged, but they no longer share one ambiguous
/// persisted toggle or one ambiguous vocabulary boundary.
public enum KnowledgeAnalysisSettings {
    /// Legacy combined key kept for safe migration/fallback.
    public static let legacyCombinedAnalysisEnabledKey = "semanticAutoLinkingEnabled"

    /// Controls embedding-based note-to-note similarity:
    /// - inspector Related Notes
    /// - background related-note analysis
    /// - graph-view similarity edges
    public static let relatedNotesSimilarityEnabledKey = "relatedNotesSimilarityEnabled"

    /// Controls AI note-to-concept extraction:
    /// - inspector AI Concepts
    /// - graph concept hubs
    public static let aiConceptExtractionEnabledKey = "aiConceptExtractionEnabled"

    public static func migrateLegacyDefaultsIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        let legacyValue = defaults.object(forKey: legacyCombinedAnalysisEnabledKey) as? Bool

        if defaults.object(forKey: relatedNotesSimilarityEnabledKey) == nil {
            defaults.set(legacyValue ?? true, forKey: relatedNotesSimilarityEnabledKey)
        }

        if defaults.object(forKey: aiConceptExtractionEnabledKey) == nil {
            defaults.set(legacyValue ?? true, forKey: aiConceptExtractionEnabledKey)
        }
    }

    public static func relatedNotesSimilarityEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let value = defaults.object(forKey: relatedNotesSimilarityEnabledKey) as? Bool {
            return value
        }
        if let legacyValue = defaults.object(forKey: legacyCombinedAnalysisEnabledKey) as? Bool {
            return legacyValue
        }
        return true
    }

    public static func aiConceptExtractionEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let value = defaults.object(forKey: aiConceptExtractionEnabledKey) as? Bool {
            return value
        }
        if let legacyValue = defaults.object(forKey: legacyCombinedAnalysisEnabledKey) as? Bool {
            return legacyValue
        }
        return true
    }

    public static func setRelatedNotesSimilarityEnabled(
        _ isEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: relatedNotesSimilarityEnabledKey)
    }

    public static func setAIConceptExtractionEnabled(
        _ isEnabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: aiConceptExtractionEnabledKey)
    }
}
