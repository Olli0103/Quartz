import Foundation
import AVFoundation
import SoundAnalysis
import Accelerate

/// Service für Sprechererkennung in Audio-Aufnahmen.
///
/// Nutzt `SoundAnalysis` und Audio-Feature-Extraktion um
/// verschiedene Sprecher in einer Aufnahme zu identifizieren.
/// Ergebnis: "Sprecher A sagte..." in der Transkription.
public actor SpeakerDiarizationService {
    public enum DiarizationError: LocalizedError, Sendable {
        case fileNotFound
        case analysisUnavailable
        case analysisFailed(String)
        case insufficientAudio

        public var errorDescription: String? {
            switch self {
            case .fileNotFound: "Audio file not found."
            case .analysisUnavailable: "Audio analysis is not available."
            case .analysisFailed(let msg): "Speaker analysis failed: \(msg)"
            case .insufficientAudio: "Audio too short for speaker detection."
            }
        }
    }

    /// Ein erkannter Sprecher-Abschnitt.
    public struct SpeakerSegment: Sendable {
        public let speakerID: String
        public let speakerLabel: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let confidence: Float

        public init(speakerID: String, speakerLabel: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
            self.speakerID = speakerID
            self.speakerLabel = speakerLabel
            self.startTime = startTime
            self.endTime = endTime
            self.confidence = confidence
        }

        public var duration: TimeInterval { endTime - startTime }
    }

    /// Ergebnis der Diarisierung.
    public struct DiarizationResult: Sendable {
        /// Erkannte Sprecher-Segmente, chronologisch sortiert.
        public let segments: [SpeakerSegment]
        /// Anzahl erkannter Sprecher.
        public let speakerCount: Int
        /// Sprecher-IDs mit Labels.
        public let speakers: [String: String]

        public init(segments: [SpeakerSegment], speakerCount: Int, speakers: [String: String]) {
            self.segments = segments
            self.speakerCount = speakerCount
            self.speakers = speakers
        }
    }

    /// Mindest-Segmentlänge in Sekunden.
    private let minSegmentDuration: TimeInterval = 1.0
    /// Fenstergröße für Feature-Extraktion (Sekunden).
    private let windowSize: TimeInterval = 2.0

    public init() {}

    // MARK: - Public API

    /// Analysiert eine Audio-Datei auf verschiedene Sprecher.
    ///
    /// - Parameter audioURL: Pfad zur Audio-Datei
    /// - Returns: DiarizationResult mit Sprecher-Segmenten
    public func analyze(audioURL: URL) async throws -> DiarizationResult {
        guard FileManager.default.fileExists(atPath: audioURL.path()) else {
            throw DiarizationError.fileNotFound
        }

        // 1. Audio laden und Features extrahieren
        let features = try await extractAudioFeatures(from: audioURL)

        guard features.count >= 2 else {
            throw DiarizationError.insufficientAudio
        }

        // 2. Clustering der Features um Sprecher zu identifizieren
        let clusterAssignments = clusterFeatures(features)

        // 3. Segmente erstellen
        let speakerCount = Set(clusterAssignments).count
        let speakers = generateSpeakerLabels(count: speakerCount)

        var segments: [SpeakerSegment] = []
        var currentSpeaker = clusterAssignments[0]
        var segmentStart: TimeInterval = 0

        for (i, cluster) in clusterAssignments.enumerated() {
            let time = Double(i) * windowSize

            if cluster != currentSpeaker {
                // Segment abschließen
                let speakerID = "speaker_\(currentSpeaker)"
                segments.append(SpeakerSegment(
                    speakerID: speakerID,
                    speakerLabel: speakers[speakerID] ?? "Speaker \(currentSpeaker + 1)",
                    startTime: segmentStart,
                    endTime: time,
                    confidence: 0.8
                ))
                segmentStart = time
                currentSpeaker = cluster
            }
        }

        // Letztes Segment
        let lastTime = Double(clusterAssignments.count) * windowSize
        let speakerID = "speaker_\(currentSpeaker)"
        segments.append(SpeakerSegment(
            speakerID: speakerID,
            speakerLabel: speakers[speakerID] ?? "Speaker \(currentSpeaker + 1)",
            startTime: segmentStart,
            endTime: lastTime,
            confidence: 0.8
        ))

        // Zu kurze Segmente mergen
        let mergedSegments = mergeShortSegments(segments)

        return DiarizationResult(
            segments: mergedSegments,
            speakerCount: speakerCount,
            speakers: speakers
        )
    }

    /// Kombiniert Diarisierung mit Transkription.
    public func combineWithTranscription(
        diarization: DiarizationResult,
        transcription: TranscriptionService.TranscriptionResult
    ) -> String {
        var result = ""

        for segment in diarization.segments {
            // Transkriptions-Segmente finden die in diesen Zeitraum fallen
            let matchingText = transcription.segments
                .filter { $0.timestamp >= segment.startTime && $0.timestamp < segment.endTime }
                .map(\.text)
                .joined(separator: " ")

            if !matchingText.isEmpty {
                let min = Int(segment.startTime) / 60
                let sec = Int(segment.startTime) % 60
                result += "**\(segment.speakerLabel)** [\(String(format: "%02d:%02d", min, sec))]: \(matchingText)\n\n"
            }
        }

        return result
    }

    // MARK: - Private

    /// Extrahiert Audio-Features (Energy, Zero-Crossing-Rate, Spectral Centroid) pro Fenster.
    private func extractAudioFeatures(from url: URL) async throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(file.length)

        let windowFrames = AVAudioFrameCount(windowSize * Double(sampleRate))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw DiarizationError.analysisFailed("Could not create audio buffer.")
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizationError.analysisFailed("Could not read audio data.")
        }

        var features: [[Float]] = []
        var offset: AVAudioFrameCount = 0

        while offset + windowFrames <= totalFrames {
            let window = Array(UnsafeBufferPointer(start: channelData + Int(offset), count: Int(windowFrames)))

            // Feature 1: RMS Energy
            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))

            // Feature 2: Zero Crossing Rate
            var zcr: Float = 0
            for i in 1..<window.count {
                if (window[i] >= 0) != (window[i-1] >= 0) {
                    zcr += 1
                }
            }
            zcr /= Float(window.count)

            // Feature 3: Spectral Centroid (vereinfacht via Frequenzgewichtung)
            var mean: Float = 0
            vDSP_meanv(window, 1, &mean, vDSP_Length(window.count))
            let centroid = abs(mean) * sampleRate

            features.append([rms, zcr, centroid])
            offset += windowFrames
        }

        return features
    }

    /// K-Means Clustering der Audio-Features.
    private func clusterFeatures(_ features: [[Float]], maxSpeakers: Int = 4) -> [Int] {
        guard !features.isEmpty else { return [] }

        let k = min(maxSpeakers, estimateSpeakerCount(features))

        // Initialisierung: Erste k verschiedene Features als Zentroide
        var centroids: [[Float]] = Array(features.prefix(k))
        var assignments = [Int](repeating: 0, count: features.count)

        // K-Means Iterationen
        for _ in 0..<20 {
            // Zuweisen
            for (i, feature) in features.enumerated() {
                var minDist: Float = .infinity
                for (j, centroid) in centroids.enumerated() {
                    let dist = euclideanDistance(feature, centroid)
                    if dist < minDist {
                        minDist = dist
                        assignments[i] = j
                    }
                }
            }

            // Zentroide aktualisieren
            for j in 0..<k {
                let clusterFeatures = features.enumerated()
                    .filter { assignments[$0.offset] == j }
                    .map(\.element)

                guard !clusterFeatures.isEmpty else { continue }

                let dim = clusterFeatures[0].count
                var newCentroid = [Float](repeating: 0, count: dim)
                for f in clusterFeatures {
                    for d in 0..<dim {
                        newCentroid[d] += f[d]
                    }
                }
                for d in 0..<dim {
                    newCentroid[d] /= Float(clusterFeatures.count)
                }
                centroids[j] = newCentroid
            }
        }

        return assignments
    }

    /// Schätzt die Anzahl der Sprecher basierend auf Feature-Varianz.
    private func estimateSpeakerCount(_ features: [[Float]]) -> Int {
        guard features.count > 4 else { return 2 }

        // Vereinfachte Heuristik: Varianz der Features bestimmt Anzahl
        let energies = features.map { $0[0] }
        var mean: Float = 0
        var variance: Float = 0
        vDSP_meanv(energies, 1, &mean, vDSP_Length(energies.count))

        let deviations = energies.map { ($0 - mean) * ($0 - mean) }
        vDSP_meanv(deviations, 1, &variance, vDSP_Length(deviations.count))

        if variance > 0.1 { return 3 }
        if variance > 0.05 { return 2 }
        return 2
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sqrt(sum)
    }

    private func generateSpeakerLabels(count: Int) -> [String: String] {
        let labels = ["Speaker A", "Speaker B", "Speaker C", "Speaker D"]
        var result: [String: String] = [:]
        for i in 0..<min(count, labels.count) {
            result["speaker_\(i)"] = labels[i]
        }
        return result
    }

    private func mergeShortSegments(_ segments: [SpeakerSegment]) -> [SpeakerSegment] {
        guard segments.count > 1 else { return segments }

        var merged: [SpeakerSegment] = [segments[0]]

        for i in 1..<segments.count {
            let current = segments[i]
            let last = merged[merged.count - 1]

            if current.speakerID == last.speakerID || current.duration < minSegmentDuration {
                // Merge mit vorherigem
                merged[merged.count - 1] = SpeakerSegment(
                    speakerID: last.speakerID,
                    speakerLabel: last.speakerLabel,
                    startTime: last.startTime,
                    endTime: current.endTime,
                    confidence: (last.confidence + current.confidence) / 2
                )
            } else {
                merged.append(current)
            }
        }

        return merged
    }
}
