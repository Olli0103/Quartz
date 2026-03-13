import Testing
import Foundation
@testable import QuartzKit

@Suite("DefaultFeatureGate")
struct FeatureGateTests {
    @Test("Free features are enabled by default")
    func freeFeatures() {
        let gate = DefaultFeatureGate()

        #expect(gate.isEnabled(.markdownEditor))
        #expect(gate.isEnabled(.focusMode))
        #expect(gate.isEnabled(.typewriterMode))
        #expect(gate.isEnabled(.biDirectionalLinks))
        #expect(gate.isEnabled(.tagSystem))
        #expect(gate.isEnabled(.fullTextSearch))
        #expect(gate.isEnabled(.audioRecording))
        #expect(gate.isEnabled(.transcription))
    }

    @Test("Pro features are disabled by default")
    func proFeaturesDisabled() {
        let gate = DefaultFeatureGate()

        #expect(!gate.isEnabled(.aiChat))
        #expect(!gate.isEnabled(.aiSummarize))
        #expect(!gate.isEnabled(.vaultSearch))
        #expect(!gate.isEnabled(.meetingMinutes))
        #expect(!gate.isEnabled(.speakerDiarization))
    }

    @Test("Pro features enabled when pro is unlocked")
    func proUnlocked() {
        let gate = DefaultFeatureGate()
        gate.isProUnlocked = true

        #expect(gate.isEnabled(.aiChat))
        #expect(gate.isEnabled(.aiSummarize))
        #expect(gate.isEnabled(.vaultSearch))
        #expect(gate.isEnabled(.meetingMinutes))
        #expect(gate.isEnabled(.speakerDiarization))
    }

    @Test("Free features remain enabled with pro unlocked")
    func freeStillEnabled() {
        let gate = DefaultFeatureGate()
        gate.isProUnlocked = true

        #expect(gate.isEnabled(.markdownEditor))
        #expect(gate.isEnabled(.tagSystem))
    }

    @Test("Tier correctly categorizes features")
    func tierMapping() {
        let gate = DefaultFeatureGate()

        #expect(gate.tier(for: .markdownEditor) == .free)
        #expect(gate.tier(for: .aiChat) == .pro)
        #expect(gate.tier(for: .audioRecording) == .free)
        #expect(gate.tier(for: .meetingMinutes) == .pro)
    }

    @Test("setTier changes feature tier at runtime")
    func dynamicTierChange() {
        let gate = DefaultFeatureGate()

        // Focus mode starts as free
        #expect(gate.tier(for: .focusMode) == .free)
        #expect(gate.isEnabled(.focusMode))

        // Move to pro
        gate.setTier(.pro, for: .focusMode)
        #expect(gate.tier(for: .focusMode) == .pro)
        #expect(!gate.isEnabled(.focusMode))

        // Unlock pro
        gate.isProUnlocked = true
        #expect(gate.isEnabled(.focusMode))
    }

    @Test("Every feature has a tier mapping")
    func allFeaturesMapped() {
        let gate = DefaultFeatureGate()
        for feature in Feature.allCases {
            let tier = gate.tier(for: feature)
            #expect(tier == .free || tier == .pro)
        }
    }
}
