import XCTest

final class EditorRealityCorpusTests: XCTestCase {

    func testAllFixturesLoadAndAreNonEmpty() throws {
        for fixture in EditorRealityFixture.allCases {
            let text = try fixture.load()
            XCTAssertFalse(text.isEmpty, "Fixture \(fixture.rawValue) should not be empty")
        }
    }

    func testHeadingParagraphDriftFixtureMatchesKnownRegressionShape() throws {
        let text = try EditorRealityFixture.headingParagraphDrift.load()

        XCTAssertTrue(text.contains("# Welcome"))
        XCTAssertTrue(text.contains("## Test"))
        XCTAssertTrue(text.contains("### Test"))
        XCTAssertTrue(text.contains("Das ist ein Test..."))
    }
}
