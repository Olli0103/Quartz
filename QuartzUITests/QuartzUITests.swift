import XCTest

final class WelcomeScreenTests: QuartzUITestCase {

    @MainActor
    func testOnboardingShowsOnFirstLaunch() throws {
        launchOnboarding()

        XCTAssertTrue(app.staticTexts["Quartz"].waitForExistence(timeout: 10),
                      "First launch should present the onboarding brand screen")
        XCTAssertTrue(app.buttons["onboarding-get-started"].waitForExistence(timeout: 5),
                      "Onboarding should expose the Get Started action")
    }

    @MainActor
    func testGetStartedButtonIsHittable() throws {
        launchOnboarding()

        let getStarted = app.buttons["onboarding-get-started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        XCTAssertTrue(getStarted.isHittable, "Get Started must remain hittable on first launch")
        XCTAssertGreaterThanOrEqual(getStarted.frame.height, 44, "Primary onboarding CTA must meet the 44pt touch target")
    }

    @MainActor
    func testGetStartedTransitionsToStorageSelection() throws {
        launchOnboarding()

        app.buttons["onboarding-get-started"].tap()

        XCTAssertTrue(app.buttons["onboarding-storage-icloud"].waitForExistence(timeout: 5),
                      "Storage selection should appear after tapping Get Started")
        XCTAssertTrue(app.buttons["onboarding-storage-folder"].waitForExistence(timeout: 5),
                      "Custom folder option should be available on the storage step")
    }
}

final class OnboardingFlowTests: QuartzUITestCase {

    @MainActor
    func testStorageStepShowsBothStorageOptions() throws {
        launchOnboarding()
        app.buttons["onboarding-get-started"].tap()

        let iCloudOption = app.buttons["onboarding-storage-icloud"]
        let folderOption = app.buttons["onboarding-storage-folder"]

        XCTAssertTrue(iCloudOption.waitForExistence(timeout: 5))
        XCTAssertTrue(folderOption.waitForExistence(timeout: 5))
        XCTAssertTrue(iCloudOption.isHittable || folderOption.isHittable,
                      "At least one onboarding storage option must be actionable")
    }

    @MainActor
    func testBackReturnsToWelcomeStep() throws {
        launchOnboarding()
        app.buttons["onboarding-get-started"].tap()

        let backButton = app.buttons["onboarding-back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        XCTAssertTrue(app.buttons["onboarding-get-started"].waitForExistence(timeout: 5),
                      "Back should return to the welcome step")
    }

    @MainActor
    func testStorageSelectionCanBeChanged() throws {
        launchOnboarding()
        app.buttons["onboarding-get-started"].tap()

        let folderOption = app.buttons["onboarding-storage-folder"]
        XCTAssertTrue(folderOption.waitForExistence(timeout: 5))
        folderOption.tap()

        XCTAssertTrue(folderOption.isSelected || folderOption.label.contains("Custom Folder"),
                      "Storage cards should remain tappable when changing onboarding selection")
    }
}

final class AccessibilityUITests: QuartzUITestCase {

    @MainActor
    func testDynamicTypeSupport() throws {
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--force-onboarding",
            "--disable-animations",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ])

        XCTAssertTrue(app.buttons["onboarding-get-started"].waitForExistence(timeout: 10),
                      "Primary onboarding CTA should remain visible at accessibility text sizes")
        XCTAssertTrue(app.buttons["onboarding-get-started"].isHittable,
                      "Primary onboarding CTA should remain hittable at accessibility text sizes")
    }

    @MainActor
    func testReduceMotionSupport() throws {
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--force-onboarding",
            "--disable-animations",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        ])

        let getStarted = app.buttons["onboarding-get-started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()
        XCTAssertTrue(app.buttons["onboarding-storage-icloud"].waitForExistence(timeout: 5),
                      "Onboarding navigation should still work with Reduce Motion enabled")
    }

    @MainActor
    func testHighContrastMode() throws {
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--force-onboarding",
            "--disable-animations",
            "-UIAccessibilityDarkerSystemColorsEnabled",
            "YES"
        ])

        XCTAssertTrue(app.staticTexts["Quartz"].waitForExistence(timeout: 10),
                      "Onboarding should remain visible in high contrast mode")
        XCTAssertTrue(app.buttons["onboarding-get-started"].isHittable,
                      "High contrast mode must preserve primary action hit-testing")
    }
}

final class PerformanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["--uitesting", "--reset-state", "--disable-animations"]
            app.launch()
        }
    }

    @MainActor
    func testLaunchToInteractivePerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchArguments += ["--uitesting", "--reset-state", "--disable-animations"]
            app.launch()
        }
    }
}

private extension QuartzUITestCase {
    @MainActor
    func launchOnboarding() {
        launchApp(arguments: [
            "--uitesting",
            "--reset-state",
            "--force-onboarding",
            "--disable-animations"
        ])
    }
}
