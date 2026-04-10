import Foundation
import AVFoundation
import SoundAnalysis
import Accelerate

/// Service for speaker recognition in audio recordings.
///
/// Uses `SoundAnalysis` and audio feature extraction to
/// identify different speakers in a recording.
/// Result: "Speaker A said..." in the transcription.
public actor SpeakerDiarizationService {
    public enum DiarizationError: LocalizedError, Sendable {
        case fileNotFound
        case analysisUnavailable
        case analysisFailed(String)
        case insufficientAudio

        public var errorDescription: String? {
            switch self {
            case .fileNotFound: String(localized: "Audio file not found.", bundle: .module)
            case .analysisUnavailable: String(localized: "Audio analysis is not available.", bundle: .module)
            case .analysisFailed(let msg): String(localized: "Speaker analysis failed: \(msg)", bundle: .module)
            case .insufficientAudio: String(localized: "Audio too short for speaker detection.", bundle: .module)
            }
        }
    }

    /// A detected speaker segment.
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

    /// Result of the diarization.
    public struct DiarizationResult: Sendable {
        /// Detected speaker segments, sorted chronologically.
        public let segments: [SpeakerSegment]
        /// Number of detected speakers.
        public let speakerCount: Int
        /// Speaker IDs with labels.
        public let speakers: [String: String]

        public init(segments: [SpeakerSegment], speakerCount: Int, speakers: [String: String]) {
            self.segments = segments
            self.speakerCount = speakerCount
            self.speakers = speakers
        }
    }

    /// Minimum segment length in seconds.
    private let minSegmentDuration: TimeInterval = 1.0
    /// Window size for feature extraction (seconds).
    private let windowSize: TimeInterval = 2.0

    public init() {}

    // MARK: - Public API

    /// Analyzes an audio file for different speakers.
    ///
    /// - Parameter audioURL: Path to the audio file
    /// - Returns: DiarizationResult with speaker segments
    public func analyze(audioURL: URL) async throws -> DiarizationResult {
        guard FileManager.default.fileExists(atPath: audioURL.path()) else {
            throw DiarizationError.fileNotFound
        }

        // 1. Load audio and extract features
        let features = try await extractAudioFeatures(from: audioURL)

        guard features.count >= 2 else {
            throw DiarizationError.insufficientAudio
        }

        // 2. Cluster features to identify speakers (returns distances for confidence)
        let (clusterAssignments, clusterDistances) = clusterFeatures(features)

        // Compute max distance for confidence normalization
        let maxDistance = clusterDistances.max() ?? 1.0

        // 3. Create segments
        let speakerCount = Set(clusterAssignments).count
        let speakers = generateSpeakerLabels(count: speakerCount)

        var segments: [SpeakerSegment] = []
        var currentSpeaker = clusterAssignments[0]
        var segmentStart: TimeInterval = 0
        var segmentDistances: [Float] = [clusterDistances[0]]

        for (i, cluster) in clusterAssignments.enumerated() {
            let time = Double(i) * windowSize

            if cluster != currentSpeaker {
                // Compute confidence: closer to centroid = higher confidence
                let avgDist = segmentDistances.reduce(0, +) / Float(segmentDistances.count)
                let confidence = maxDistance > 0 ? max(0.1, 1.0 - (avgDist / maxDistance)) : 0.5

                let speakerID = "speaker_\(currentSpeaker)"
                segments.append(SpeakerSegment(
                    speakerID: speakerID,
                    speakerLabel: speakers[speakerID] ?? "Speaker \(currentSpeaker + 1)",
                    startTime: segmentStart,
                    endTime: time,
                    confidence: confidence
                ))
                segmentStart = time
                currentSpeaker = cluster
                segmentDistances = []
            }
            if i < clusterDistances.count {
                segmentDistances.append(clusterDistances[i])
            }
        }

        // Last segment
        let lastTime = Double(clusterAssignments.count) * windowSize
        let avgDist = segmentDistances.isEmpty ? 0 : segmentDistances.reduce(0, +) / Float(segmentDistances.count)
        let lastConfidence = maxDistance > 0 ? max(0.1, 1.0 - (avgDist / maxDistance)) : 0.5
        let speakerID = "speaker_\(currentSpeaker)"
        segments.append(SpeakerSegment(
            speakerID: speakerID,
            speakerLabel: speakers[speakerID] ?? "Speaker \(currentSpeaker + 1)",
            startTime: segmentStart,
            endTime: lastTime,
            confidence: lastConfidence
        ))

        // Merge segments that are too short
        let mergedSegments = mergeShortSegments(segments)

        return DiarizationResult(
            segments: mergedSegments,
            speakerCount: speakerCount,
            speakers: speakers
        )
    }

    /// Combines diarization with transcription.
    public func combineWithTranscription(
        diarization: DiarizationResult,
        transcription: TranscriptionService.TranscriptionResult
    ) -> String {
        var result = ""

        for segment in diarization.segments {
            // Find transcription segments that fall within this time range
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

    /// Extracts audio features (energy, zero-crossing rate, spectral centroid) per window.
    /// Uses chunked reading to avoid loading the entire file into memory.
    private func extractAudioFeatures(from url: URL) async throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let totalFrames = AVAudioFrameCount(file.length)

        let windowFrames = AVAudioFrameCount(windowSize * Double(sampleRate))

        // Chunked reading: one window at a time to bound memory
        guard let windowBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
            throw DiarizationError.analysisFailed("Could not create audio buffer.")
        }

        var features: [[Float]] = []
        var framesRead: AVAudioFrameCount = 0

        while framesRead + windowFrames <= totalFrames {
            file.framePosition = AVAudioFramePosition(framesRead)
            windowBuffer.frameLength = 0
            try file.read(into: windowBuffer, frameCount: windowFrames)

            guard let channelData = windowBuffer.floatChannelData?[0] else {
                throw DiarizationError.analysisFailed("Could not read audio data.")
            }

            let count = Int(windowBuffer.frameLength)
            let window = Array(UnsafeBufferPointer(start: channelData, count: count))

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

            // Feature 3: Spectral Centroid (simplified via frequency weighting)
            var mean: Float = 0
            vDSP_meanv(window, 1, &mean, vDSP_Length(window.count))
            let centroid = abs(mean) * sampleRate

            features.append([rms, zcr, centroid])
            framesRead += windowFrames
        }

        return features
    }

    /// K-Means clustering of audio features.
    /// Returns (assignments, distances) where distances[i] is the distance
    /// from feature[i] to its assigned centroid (used for confidence).
    private func clusterFeatures(_ features: [[Float]], maxSpeakers: Int = 4) -> (assignments: [Int], distances: [Float]) {
        guard !features.isEmpty else { return ([], []) }

        let k = min(maxSpeakers, estimateSpeakerCount(features))

        // Initialization: First k distinct features as centroids
        var centroids: [[Float]] = Array(features.prefix(k))
        var assignments = [Int](repeating: 0, count: features.count)
        var distances = [Float](repeating: 0, count: features.count)

        // K-Means iterations with early stopping on convergence
        let epsilon: Float = 1e-4
        for _ in 0..<20 {
            // Assign
            for (i, feature) in features.enumerated() {
                var minDist: Float = .infinity
                for (j, centroid) in centroids.enumerated() {
                    let dist = euclideanDistance(feature, centroid)
                    if dist < minDist {
                        minDist = dist
                        assignments[i] = j
                    }
                }
                distances[i] = minDist
            }

            // Update centroids and check convergence
            var maxDelta: Float = 0
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

                let delta = euclideanDistance(centroids[j], newCentroid)
                maxDelta = max(maxDelta, delta)
                centroids[j] = newCentroid
            }

            // Early stopping when centroids are stable
            if maxDelta < epsilon { break }
        }

        return (assignments, distances)
    }

    /// Estimates the number of speakers based on feature variance.
    private func estimateSpeakerCount(_ features: [[Float]]) -> Int {
        guard features.count > 4 else { return 2 }

        // Simplified heuristic: feature variance determines count
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
        let labels = [
            String(localized: "Speaker A", bundle: .module),
            String(localized: "Speaker B", bundle: .module),
            String(localized: "Speaker C", bundle: .module),
            String(localized: "Speaker D", bundle: .module),
        ]
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
                // Merge with previous
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
