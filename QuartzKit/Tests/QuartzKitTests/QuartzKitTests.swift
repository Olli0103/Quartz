import Testing
@testable import QuartzKit

@Suite("QuartzKit")
struct QuartzKitTests {
    @Test("Version is set")
    func versionExists() {
        #expect(!QuartzKit.version.isEmpty)
    }
}
