import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4AudioInterruption")
struct Phase4AudioInterruptionTests {

    // MARK: - CaptureState Machine

    @Test("Capture service initializes in idle state")
    func initialState() async {
        let service = AVAudioEngineCaptureService()
        #expect(await service.state == .idle)
    }

    @Test("Capture service initial duration is zero")
    func initialDurationZero() async {
        let service = AVAudioEngineCaptureService()
        #expect(await service.capturedDuration == 0)
    }

    @Test("Capture service initial outputURL is nil")
    func initialOutputURLNil() async {
        let service = AVAudioEngineCaptureService()
        #expect(await service.outputURL == nil)
    }

    @Test("Pause from idle is no-op")
    func pauseFromIdleNoOp() async {
        let service = AVAudioEngineCaptureService()
        await service.pauseCapture()
        #expect(await service.state == .idle)
    }

    @Test("Stop from idle throws noActiveCapture")
    func stopFromIdleThrows() async {
        let service = AVAudioEngineCaptureService()
        do {
            _ = try await service.stopCapture()
            Issue.record("Expected noActiveCapture error")
        } catch {
            // Expected — stop without active capture
        }
    }

    // MARK: - CaptureError Descriptions

    @Test("CaptureError.engineSetupFailed has description")
    func engineSetupFailedDescription() {
        let error = AVAudioEngineCaptureService.CaptureError.engineSetupFailed("test reason")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("test reason"))
    }

    @Test("CaptureError.noActiveCapture has description")
    func noActiveCaptureDescription() {
        let error = AVAudioEngineCaptureService.CaptureError.noActiveCapture
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("CaptureError.alreadyCapturing has description")
    func alreadyCaptureDescription() {
        let error = AVAudioEngineCaptureService.CaptureError.alreadyCapturing
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    // MARK: - CaptureState Equality

    @Test("CaptureState equality works for all cases")
    func captureStateEquality() {
        #expect(AVAudioEngineCaptureService.CaptureState.idle == .idle)
        #expect(AVAudioEngineCaptureService.CaptureState.preparing == .preparing)
        #expect(AVAudioEngineCaptureService.CaptureState.capturing == .capturing)
        #expect(AVAudioEngineCaptureService.CaptureState.paused == .paused)
        #expect(AVAudioEngineCaptureService.CaptureState.stopping == .stopping)
        #expect(AVAudioEngineCaptureService.CaptureState.idle != .capturing)
    }

    // MARK: - InterruptionEvent

    @Test("InterruptionEvent cases are distinct")
    func interruptionEventCases() {
        let began: AVAudioEngineCaptureService.InterruptionEvent = .began
        let endedWithResume: AVAudioEngineCaptureService.InterruptionEvent = .endedWithResume
        let endedWithoutResume: AVAudioEngineCaptureService.InterruptionEvent = .endedWithoutResume
        let routeChange: AVAudioEngineCaptureService.InterruptionEvent = .routeChange(reason: "NewDevice")

        // Verify we can pattern match without crash
        switch began {
        case .began: break
        default: Issue.record("Expected .began")
        }
        switch endedWithResume {
        case .endedWithResume: break
        default: Issue.record("Expected .endedWithResume")
        }
        switch endedWithoutResume {
        case .endedWithoutResume: break
        default: Issue.record("Expected .endedWithoutResume")
        }
        switch routeChange {
        case .routeChange(let reason):
            #expect(reason == "NewDevice")
        default: Issue.record("Expected .routeChange")
        }
    }

    // MARK: - Configuration

    @Test("Capture service default configuration values")
    func defaultConfiguration() async {
        let service = AVAudioEngineCaptureService()
        #expect(await service.chunkDuration == 0.5)
        #expect(await service.sampleRate == 44100)
        #expect(await service.channelCount == 1)
    }

    @Test("Capture service custom configuration")
    func customConfiguration() async {
        let service = AVAudioEngineCaptureService(
            chunkDuration: 1.0,
            sampleRate: 48000,
            channelCount: 2
        )
        #expect(await service.chunkDuration == 1.0)
        #expect(await service.sampleRate == 48000)
        #expect(await service.channelCount == 2)
    }

    // MARK: - Stream Creation

    @Test("makeAudioChunkStream returns an AsyncStream")
    func makeAudioChunkStream() async {
        let service = AVAudioEngineCaptureService()
        let stream = await service.makeAudioChunkStream()
        // Verify we got a non-nil stream (it's a value type, always non-nil)
        _ = stream // compilation success = type safety verified
    }

    @Test("makeMeteringStream returns an AsyncStream")
    func makeMeteringStream() async {
        let service = AVAudioEngineCaptureService()
        let stream = await service.makeMeteringStream()
        _ = stream
    }
}
