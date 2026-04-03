import Testing
import Foundation
@testable import QuartzKit

// MARK: - Design Token Consistency Tests

@Suite("DesignTokenConsistency")
struct DesignTokenConsistencyTests {

    @Test("QuartzHIG.minTouchTarget equals 44")
    func minTouchTarget() {
        #expect(QuartzHIG.minTouchTarget == 44)
    }

    @Test("GraphLayoutPolicy constants are sensible")
    func graphLayoutConstants() {
        #expect(GraphLayoutPolicy.maxNodesPerGraph == 280)
        #expect(GraphLayoutPolicy.semanticLinkingMaxNodes == 200)

        // semanticLinkingMaxNodes should be less than maxNodesPerGraph
        #expect(GraphLayoutPolicy.semanticLinkingMaxNodes < GraphLayoutPolicy.maxNodesPerGraph)

        // Layout iterations scale inversely with node count (above the cap threshold)
        let lowCount = GraphLayoutPolicy.layoutIterations(forNodeCount: 50)
        let highCount = GraphLayoutPolicy.layoutIterations(forNodeCount: 500)
        #expect(lowCount >= highCount)
        #expect(lowCount >= 24)
        #expect(highCount >= 24)
    }
}
