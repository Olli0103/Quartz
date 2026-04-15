import XCTest
import SnapshotTesting

#if canImport(UIKit) && !os(macOS)
import UIKit
@testable import QuartzKit

@MainActor
final class EditorRealitySnapshotTests_iPhone: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: Self.snapshotRecordMode()) {
            super.invokeTest()
        }
    }

    private nonisolated static func snapshotRecordMode() -> SnapshotTestingConfiguration.Record {
        if ProcessInfo.processInfo.environment["QUARTZ_RECORD_EDITOR_SNAPSHOTS"] == "1" {
            return .all
        }
        if UserDefaults.standard.bool(forKey: "QUARTZ_RECORD_EDITOR_SNAPSHOTS") {
            return .all
        }
        if FileManager.default.fileExists(atPath: "/tmp/quartz_record_editor_snapshots.flag") {
            return .all
        }
        return .never
    }

    func testRealityCorpusSnapshots_iPhone() async throws {
        try requireMobileDevice(.phone)
        try await assertRealitySnapshots(for: .phone)
    }
}

@MainActor
final class EditorRealitySnapshotTests_iPad: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: Self.snapshotRecordMode()) {
            super.invokeTest()
        }
    }

    private nonisolated static func snapshotRecordMode() -> SnapshotTestingConfiguration.Record {
        if ProcessInfo.processInfo.environment["QUARTZ_RECORD_EDITOR_SNAPSHOTS"] == "1" {
            return .all
        }
        if UserDefaults.standard.bool(forKey: "QUARTZ_RECORD_EDITOR_SNAPSHOTS") {
            return .all
        }
        if FileManager.default.fileExists(atPath: "/tmp/quartz_record_editor_snapshots.flag") {
            return .all
        }
        return .never
    }

    func testRealityCorpusSnapshots_iPad() async throws {
        try requireMobileDevice(.pad)
        try await assertRealitySnapshots(for: .pad)
    }
}

@MainActor
private func assertRealitySnapshots(for target: MobileEditorTargetDevice) async throws {
    let concealmentFixture = try EditorRealityFixture.concealmentBoundaries.load()
    let offLineCaret = (concealmentFixture as NSString).range(of: "Second line plain.").location
    let onLineCaret = (concealmentFixture as NSString).range(of: "bold").location
    let plainTextCaret = (concealmentFixture as NSString).range(of: "Paragraph").location

    XCTAssertNotEqual(offLineCaret, NSNotFound)
    XCTAssertNotEqual(onLineCaret, NSNotFound)
    XCTAssertNotEqual(plainTextCaret, NSNotFound)

    let headingHarness = try await makeMobileSnapshotHarness(
        fixture: .headingParagraphDrift,
        target: target,
        syntaxVisibilityMode: .full
    )
    assertSnapshot(
        of: headingHarness.controller,
        as: snapshotStrategy(for: target),
        named: "EditorReality_HeadingParagraph_Full_\(target.platformSuffix)"
    )

    let roundtripHarness = try await makeMobileSnapshotHarness(
        fixture: .editorStateRoundtrip,
        target: target,
        syntaxVisibilityMode: .full
    )
    assertSnapshot(
        of: roundtripHarness.controller,
        as: snapshotStrategy(for: target),
        named: "EditorReality_StateRoundtrip_Full_\(target.platformSuffix)"
    )

    let offLineHarness = try await makeMobileSnapshotHarness(
        fixture: .concealmentBoundaries,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret,
        selection: NSRange(location: offLineCaret, length: 0)
    )
    assertSnapshot(
        of: offLineHarness.controller,
        as: snapshotStrategy(for: target),
        named: "EditorReality_Concealment_OffLine_\(target.platformSuffix)"
    )

    let onLineHarness = try await makeMobileSnapshotHarness(
        fixture: .concealmentBoundaries,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret,
        selection: NSRange(location: onLineCaret, length: 0)
    )
    assertSnapshot(
        of: onLineHarness.controller,
        as: snapshotStrategy(for: target),
        named: "EditorReality_Concealment_OnLine_\(target.platformSuffix)"
    )

    let plainTextHarness = try await makeMobileSnapshotHarness(
        fixture: .concealmentBoundaries,
        target: target,
        syntaxVisibilityMode: .hiddenUntilCaret,
        selection: NSRange(location: plainTextCaret, length: 0)
    )
    assertSnapshot(
        of: plainTextHarness.controller,
        as: snapshotStrategy(for: target),
        named: "EditorReality_Concealment_PlainTextSameLine_\(target.platformSuffix)"
    )
}

private func snapshotStrategy(
    for target: MobileEditorTargetDevice
) -> Snapshotting<UIViewController, UIImage> {
    switch target {
    case .phone:
        return .image(precision: 0.995, perceptualPrecision: 0.99)
    case .pad:
        // iPad simulator rasterization shows low-level antialias jitter across runs
        // even when the semantic/editor state is identical.
        return .image(precision: 0.995, perceptualPrecision: 0.99)
    }
}
#endif
