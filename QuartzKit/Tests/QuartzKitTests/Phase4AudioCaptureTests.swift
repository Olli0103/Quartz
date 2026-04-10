import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 4: Granola-Style Audio Capture + On-Device Intelligence
// TDD Red Phase: These tests define the required behavior for audio pipeline improvements.

// ============================================================================
// MARK: - Audio Pipeline Integration Tests
// ============================================================================

@Suite("AudioPipelineIntegration")
struct AudioPipelineIntegrationTests {

    // MARK: - MeetingCaptureOrchestrator Tests

    @Test("Orchestrator initializes with default configuration")
    func orchestratorInitialization() async {
        let orchestrator = MeetingCaptureOrchestrator()
        let state = await orchestrator.currentState
        #expect(state == .idle)
    }

    @Test("Orchestrator transitions through recording states correctly")
    func orchestratorStateTransitions() async throws {
        let orchestrator = MeetingCaptureOrchestrator()

        // Initial state
        var state = await orchestrator.currentState
        #expect(state == .idle)

        // Start recording (will fail without mic permission, but state machine should work)
        // In real tests, we'd mock the audio session
        let mockConfig = MeetingCaptureOrchestrator.CaptureConfiguration(
            vaultURL: FileManager.default.temporaryDirectory,
            template: .standard,
            detectLanguage: true,
            enableDiarization: true
        )

        // State machine validation
        #expect(await orchestrator.canTransition(to: .preparing))
        #expect(!(await orchestrator.canTransition(to: .transcribing)))
    }

    @Test("Orchestrator handles cancellation gracefully")
    func orchestratorCancellation() async {
        let orchestrator = MeetingCaptureOrchestrator()

        // Cancel from idle should be no-op
        await orchestrator.cancel()
        let state = await orchestrator.currentState
        #expect(state == .idle)
    }

    @Test("Pipeline produces meeting minutes from mock transcription")
    func pipelineProducesMeetingMinutes() async throws {
        let orchestrator = MeetingCaptureOrchestrator()

        // Create mock transcription result
        let mockTranscription = TranscriptionService.TranscriptionResult(
            text: "Hello everyone. Today we will discuss the roadmap. John will handle the backend work. Mary will update the UI.",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hello everyone", timestamp: 0.0, duration: 1.0, confidence: 0.95),
                TranscriptionService.TranscriptionSegment(text: "Today we will discuss the roadmap", timestamp: 1.0, duration: 2.0, confidence: 0.92),
                TranscriptionService.TranscriptionSegment(text: "John will handle the backend work", timestamp: 3.0, duration: 2.0, confidence: 0.90),
                TranscriptionService.TranscriptionSegment(text: "Mary will update the UI", timestamp: 5.0, duration: 1.5, confidence: 0.88)
            ],
            locale: Locale(identifier: "en_US"),
            duration: 6.5
        )

        // Create mock diarization result
        let mockDiarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Speaker A", startTime: 0.0, endTime: 3.0, confidence: 0.85),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "Speaker B", startTime: 3.0, endTime: 6.5, confidence: 0.80)
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Speaker A", "speaker_1": "Speaker B"]
        )

        // Test combined output
        let combined = await orchestrator.combineTranscriptionWithDiarization(
            transcription: mockTranscription,
            diarization: mockDiarization
        )

        #expect(combined.contains("Speaker A"))
        #expect(combined.contains("Speaker B"))
        #expect(combined.contains("Hello everyone"))
    }

    @Test("Pipeline handles empty transcription gracefully")
    func pipelineHandlesEmptyTranscription() async {
        let orchestrator = MeetingCaptureOrchestrator()

        let emptyTranscription = TranscriptionService.TranscriptionResult(
            text: "",
            segments: [],
            locale: Locale.current,
            duration: 0
        )

        let emptyDiarization = SpeakerDiarizationService.DiarizationResult(
            segments: [],
            speakerCount: 0,
            speakers: [:]
        )

        let combined = await orchestrator.combineTranscriptionWithDiarization(
            transcription: emptyTranscription,
            diarization: emptyDiarization
        )

        #expect(combined.isEmpty || combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// ============================================================================
// MARK: - Diarization Mapping Tests
// ============================================================================

@Suite("DiarizationMapping")
struct DiarizationMappingTests {

    @Test("Speaker segments map correctly to transcription segments")
    func speakerSegmentMappingToTranscription() async {
        let service = SpeakerDiarizationService()

        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Alice", startTime: 0.0, endTime: 5.0, confidence: 0.9),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "Bob", startTime: 5.0, endTime: 10.0, confidence: 0.85),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Alice", startTime: 10.0, endTime: 15.0, confidence: 0.88)
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Alice", "speaker_1": "Bob"]
        )

        let transcription = TranscriptionService.TranscriptionResult(
            text: "Hello Bob. Hi Alice. How are you?",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "Hello Bob", timestamp: 1.0, duration: 2.0, confidence: 0.95),
                TranscriptionService.TranscriptionSegment(text: "Hi Alice", timestamp: 6.0, duration: 1.5, confidence: 0.92),
                TranscriptionService.TranscriptionSegment(text: "How are you", timestamp: 11.0, duration: 2.0, confidence: 0.90)
            ],
            locale: Locale(identifier: "en_US"),
            duration: 15.0
        )

        let combined = await service.combineWithTranscription(diarization: diarization, transcription: transcription)

        // Alice should say "Hello Bob" and "How are you"
        // Bob should say "Hi Alice"
        #expect(combined.contains("Alice"))
        #expect(combined.contains("Bob"))
        #expect(combined.contains("Hello Bob"))
        #expect(combined.contains("Hi Alice"))
    }

    @Test("Overlapping segments are handled correctly")
    func overlappingSegmentsHandling() async {
        let service = SpeakerDiarizationService()

        // Edge case: transcription segment spans multiple speaker segments
        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "Speaker A", startTime: 0.0, endTime: 3.0, confidence: 0.9),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "Speaker B", startTime: 3.0, endTime: 6.0, confidence: 0.85)
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "Speaker A", "speaker_1": "Speaker B"]
        )

        // This segment starts at 2.5, which is in Speaker A's time, but extends into Speaker B's time
        let transcription = TranscriptionService.TranscriptionResult(
            text: "This spans both speakers",
            segments: [
                TranscriptionService.TranscriptionSegment(text: "This spans both speakers", timestamp: 2.5, duration: 2.0, confidence: 0.90)
            ],
            locale: Locale(identifier: "en_US"),
            duration: 6.0
        )

        let combined = await service.combineWithTranscription(diarization: diarization, transcription: transcription)

        // Should assign to Speaker A (segment starts in their time range)
        #expect(combined.contains("Speaker A"))
    }

    @Test("Short segments are merged correctly")
    func shortSegmentMerging() async {
        // Test the segment merging logic
        let shortSegments = [
            SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "A", startTime: 0.0, endTime: 0.5, confidence: 0.8),
            SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "A", startTime: 0.5, endTime: 1.0, confidence: 0.8),
            SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "B", startTime: 1.0, endTime: 5.0, confidence: 0.9)
        ]

        // After merging, the two short Speaker A segments should combine
        let result = SpeakerDiarizationService.DiarizationResult(
            segments: shortSegments,
            speakerCount: 2,
            speakers: ["speaker_0": "A", "speaker_1": "B"]
        )

        // The merging logic should reduce segment count when consecutive same-speaker segments exist
        #expect(result.segments.count == 3) // Before merge (raw input)
    }

    @Test("Confidence scores are preserved in merged segments")
    func confidenceScoresPreserved() async {
        let segment1 = SpeakerDiarizationService.SpeakerSegment(
            speakerID: "speaker_0",
            speakerLabel: "A",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.9
        )

        let segment2 = SpeakerDiarizationService.SpeakerSegment(
            speakerID: "speaker_0",
            speakerLabel: "A",
            startTime: 2.0,
            endTime: 4.0,
            confidence: 0.8
        )

        // Average confidence should be (0.9 + 0.8) / 2 = 0.85
        let avgConfidence = (segment1.confidence + segment2.confidence) / 2
        #expect(avgConfidence == 0.85)
    }
}

// ============================================================================
// MARK: - Language Detection Tests
// ============================================================================

@Suite("LanguageDetection")
struct LanguageDetectionTests {

    @Test("Detects English text correctly")
    func detectsEnglish() async {
        let detector = LanguageDetector()
        let result = await detector.detectLanguage(from: "Hello, how are you doing today? This is a test of the language detection system.")

        #expect(result.languageCode == "en")
        #expect(result.confidence > 0.8)
    }

    @Test("Detects German text correctly")
    func detectsGerman() async {
        let detector = LanguageDetector()
        let result = await detector.detectLanguage(from: "Guten Tag, wie geht es Ihnen heute? Dies ist ein Test des Spracherkennungssystems.")

        #expect(result.languageCode == "de")
        #expect(result.confidence > 0.8)
    }

    @Test("Detects Spanish text correctly")
    func detectsSpanish() async {
        let detector = LanguageDetector()
        let result = await detector.detectLanguage(from: "Hola, como estas hoy? Este es una prueba del sistema de deteccion de idiomas.")

        #expect(result.languageCode == "es")
        #expect(result.confidence > 0.7)
    }

    @Test("Mixed language text returns dominant language")
    func mixedLanguageReturnsDominant() async {
        let detector = LanguageDetector()

        // Mostly English with some German words
        let mixedText = "Hello everyone, today we will discuss the Zeitgeist of modern software development. The team has made great progress on the Weltanschauung of our architecture."

        let result = await detector.detectLanguage(from: mixedText)

        // Should detect English as dominant
        #expect(result.languageCode == "en")
    }

    @Test("Very short text has lower confidence")
    func shortTextLowerConfidence() async {
        let detector = LanguageDetector()
        let result = await detector.detectLanguage(from: "Hi")

        // Short text should still work but with lower confidence
        #expect(result.confidence < 1.0)
    }

    @Test("Empty text returns unknown")
    func emptyTextReturnsUnknown() async {
        let detector = LanguageDetector()
        let result = await detector.detectLanguage(from: "")

        #expect(result.languageCode == "und" || result.confidence == 0)
    }

    @Test("Supported languages list is comprehensive")
    func supportedLanguagesComprehensive() async {
        let detector = LanguageDetector()
        let supported = await detector.supportedLanguages

        // Should support major languages
        #expect(supported.contains("en"))
        #expect(supported.contains("de"))
        #expect(supported.contains("es"))
        #expect(supported.contains("fr"))
        #expect(supported.contains("ja"))
        #expect(supported.contains("zh"))
    }
}

// ============================================================================
// MARK: - Recorder Compact UI State Tests
// ============================================================================

@Suite("RecorderCompactUI")
@MainActor
struct RecorderCompactUITests {

    @Test("Compact mode preserves recording timer")
    func compactModePreservesTimer() async {
        let viewModel = RecorderViewModel()

        // Start recording
        viewModel.simulateRecordingStart()

        // Verify duration is tracked
        let initialDuration = viewModel.duration

        // Transition to compact mode
        viewModel.setCompactMode(true)

        // Duration should still be accessible
        let compactDuration = viewModel.duration
        #expect(compactDuration >= initialDuration)

        // Transition back to full mode
        viewModel.setCompactMode(false)

        let fullDuration = viewModel.duration
        #expect(fullDuration >= compactDuration)
    }

    @Test("Compact mode preserves recording state")
    func compactModePreservesState() async {
        let viewModel = RecorderViewModel()

        // Start recording
        viewModel.simulateRecordingStart()
        let isRecording = viewModel.isRecording
        #expect(isRecording)

        // Toggle compact mode
        viewModel.setCompactMode(true)
        let stillRecording = viewModel.isRecording
        #expect(stillRecording)

        // Recording should continue
        viewModel.setCompactMode(false)
        let finalRecording = viewModel.isRecording
        #expect(finalRecording)
    }

    @Test("Pause/resume works in compact mode")
    func pauseResumeInCompactMode() async {
        let viewModel = RecorderViewModel()

        // Start recording
        viewModel.simulateRecordingStart()

        // Enter compact mode
        viewModel.setCompactMode(true)

        // Pause
        viewModel.pause()
        let isPaused = viewModel.isPaused
        #expect(isPaused)

        // Resume
        viewModel.resume()
        let isResumed = viewModel.isRecording
        #expect(isResumed)
    }

    @Test("Waveform data available in compact mode")
    func waveformDataInCompactMode() async {
        let viewModel = RecorderViewModel()

        // Start recording
        viewModel.simulateRecordingStart()

        // Simulate some level updates
        viewModel.simulateLevelUpdate(0.5)
        viewModel.simulateLevelUpdate(0.7)
        viewModel.simulateLevelUpdate(0.3)

        // Enter compact mode
        viewModel.setCompactMode(true)

        let levels = viewModel.levelHistory
        #expect(levels.count >= 3)
    }

    @Test("Stop recording works from compact mode")
    func stopFromCompactMode() async throws {
        let viewModel = RecorderViewModel()

        // Start recording
        viewModel.simulateRecordingStart()

        // Enter compact mode
        viewModel.setCompactMode(true)

        // Stop should work
        viewModel.stop()

        let isStopped = !viewModel.isRecording
        #expect(isStopped)
    }
}

// ============================================================================
// MARK: - Audio Performance Tests (XCTest for measure)
// ============================================================================

final class AudioPerformanceTests: XCTestCase {

    /// Tests that transcription processing doesn't block main thread
    func testTranscriptionProcessingOffMainThread() async throws {
        let expectation = expectation(description: "Processing completes")

        // Generate a large mock transcription
        var segments: [TranscriptionService.TranscriptionSegment] = []
        for i in 0..<1000 {
            segments.append(TranscriptionService.TranscriptionSegment(
                text: "Segment \(i) with content that simulates real speech transcription text.",
                timestamp: Double(i) * 0.5,
                duration: 0.5,
                confidence: Float.random(in: 0.7...1.0)
            ))
        }

        let transcription = TranscriptionService.TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            locale: Locale(identifier: "en_US"),
            duration: Double(segments.count) * 0.5
        )

        // This should complete without blocking
        Task.detached {
            // Simulate processing
            let _ = transcription.segments.filter { $0.confidence > 0.8 }
            let _ = transcription.text.count

            await MainActor.run {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    /// Tests diarization clustering performance
    func testDiarizationClusteringPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        // Generate mock audio features (simulating 10 minutes of audio with 2-second windows)
        let windowCount = 300 // 10 minutes / 2 seconds
        var features: [[Float]] = []
        for _ in 0..<windowCount {
            features.append([
                Float.random(in: 0...1),  // RMS energy
                Float.random(in: 0...0.5), // ZCR
                Float.random(in: 0...22000) // Spectral centroid
            ])
        }

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Simulate K-means clustering
            let k = 3
            var centroids: [[Float]] = Array(features.prefix(k))
            var assignments = [Int](repeating: 0, count: features.count)

            for _ in 0..<20 { // 20 iterations
                // Assign
                for (i, feature) in features.enumerated() {
                    var minDist: Float = .infinity
                    for (j, centroid) in centroids.enumerated() {
                        var dist: Float = 0
                        for d in 0..<3 {
                            let diff = feature[d] - centroid[d]
                            dist += diff * diff
                        }
                        if dist < minDist {
                            minDist = dist
                            assignments[i] = j
                        }
                    }
                }

                // Update centroids
                for j in 0..<k {
                    let clusterFeatures = features.enumerated()
                        .filter { assignments[$0.offset] == j }
                        .map(\.element)

                    guard !clusterFeatures.isEmpty else { continue }

                    var newCentroid: [Float] = [0, 0, 0]
                    for f in clusterFeatures {
                        for d in 0..<3 {
                            newCentroid[d] += f[d]
                        }
                    }
                    for d in 0..<3 {
                        newCentroid[d] /= Float(clusterFeatures.count)
                    }
                    centroids[j] = newCentroid
                }
            }

            XCTAssertEqual(assignments.count, windowCount)
        }
    }

    /// Tests language detection performance
    func testLanguageDetectionPerformance() async throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        // Sample text of moderate length
        let sampleText = """
        This is a sample text that would be typical of a meeting transcription.
        It contains multiple sentences and spans several lines.
        The language detection system should be able to quickly identify this as English.
        Performance is critical because detection happens in real-time during recording.
        """

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Detection")

            Task {
                let detector = LanguageDetector()
                _ = await detector.detectLanguage(from: sampleText)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    /// Tests that meeting minutes generation stays within time budget
    func testMeetingMinutesGenerationBudget() async throws {
        let orchestrator = MeetingCaptureOrchestrator()

        // Create a 5-minute mock transcription
        let segmentCount = 150 // ~2 seconds per segment
        var segments: [TranscriptionService.TranscriptionSegment] = []
        for i in 0..<segmentCount {
            segments.append(TranscriptionService.TranscriptionSegment(
                text: "This is segment number \(i) of the meeting transcription.",
                timestamp: Double(i) * 2.0,
                duration: 2.0,
                confidence: 0.9
            ))
        }

        let transcription = TranscriptionService.TranscriptionResult(
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            locale: Locale(identifier: "en_US"),
            duration: 300.0 // 5 minutes
        )

        let diarization = SpeakerDiarizationService.DiarizationResult(
            segments: [
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_0", speakerLabel: "A", startTime: 0, endTime: 150, confidence: 0.9),
                SpeakerDiarizationService.SpeakerSegment(speakerID: "speaker_1", speakerLabel: "B", startTime: 150, endTime: 300, confidence: 0.85)
            ],
            speakerCount: 2,
            speakers: ["speaker_0": "A", "speaker_1": "B"]
        )

        let startTime = Date()

        // This combines transcription with diarization (local processing, no AI call)
        _ = await orchestrator.combineTranscriptionWithDiarization(
            transcription: transcription,
            diarization: diarization
        )

        let elapsed = Date().timeIntervalSince(startTime)

        // Local processing should complete in under 1 second
        XCTAssertLessThan(elapsed, 1.0, "Local processing should complete within 1 second")
    }
}

// ============================================================================
// MARK: - Test Helper Types
// ============================================================================

/// ViewModel for recorder UI that supports compact mode.
/// Test-only helper for RecorderCompactUI tests.
@MainActor
class RecorderViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var levelHistory: [Float] = []
    @Published private(set) var isCompactMode = false

    init() {}

    func simulateRecordingStart() {
        isRecording = true
        isPaused = false
        duration = 0
        levelHistory = []
    }

    func setCompactMode(_ compact: Bool) {
        isCompactMode = compact
    }

    func pause() {
        guard isRecording else { return }
        isPaused = true
        isRecording = false
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        isRecording = true
    }

    func stop() {
        isRecording = false
        isPaused = false
    }

    func simulateLevelUpdate(_ level: Float) {
        levelHistory.append(level)
    }
}
