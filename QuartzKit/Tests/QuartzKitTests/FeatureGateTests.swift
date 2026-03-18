import Testing
import Foundation
@testable import QuartzKit

@Suite("DefaultFeatureGate")
struct FeatureGateTests {
    @Test("All features are enabled – open-source, no Pro gate")
    func allFeaturesEnabled() {
        let gate = DefaultFeatureGate()

        for feature in Feature.allCases {
            #expect(gate.isEnabled(feature), "Feature \(feature) should be enabled")
        }
    }

    @Test("Every feature tier is free")
    func allTiersFree() {
        let gate = DefaultFeatureGate()

        for feature in Feature.allCases {
            #expect(gate.tier(for: feature) == .free, "Feature \(feature) should be .free")
        }
    }
}
