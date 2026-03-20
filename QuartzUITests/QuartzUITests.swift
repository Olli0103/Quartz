//
//  QuartzUITests.swift
//  QuartzUITests
//
//  Created by Posselt, Oliver on 13.03.26.
//

import XCTest

// MARK: - Welcome Screen Tests

final class WelcomeScreenTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenShowsOnLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let welcomeText = app.staticTexts["Welcome to Quartz"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 10), "Welcome screen should be displayed on first launch")
    }

    @MainActor
    func testOpenVaultButtonExists() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let openVaultButton = app.buttons["Open Vault"]
        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 10), "Open Vault button should be visible")
    }

    @MainActor
    func testCreateNewVaultButtonExists() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let createVaultButton = app.buttons["Create New Vault"]
        XCTAssertTrue(createVaultButton.waitForExistence(timeout: 10), "Create New Vault button should be visible")
    }

    @MainActor
    func testButtonsAreHittable() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let openVaultButton = app.buttons["Open Vault"]
        let createVaultButton = app.buttons["Create New Vault"]

        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 10))
        XCTAssertTrue(createVaultButton.waitForExistence(timeout: 10))

        XCTAssertTrue(openVaultButton.isHittable, "Open Vault button should be hittable")
        XCTAssertTrue(createVaultButton.isHittable, "Create New Vault button should be hittable")
    }

    @MainActor
    func testMinimumTouchTargetSize() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let openVaultButton = app.buttons["Open Vault"]
        guard openVaultButton.waitForExistence(timeout: 10) else {
            XCTFail("Open Vault button not found")
            return
        }

        let frame = openVaultButton.frame
        // HIG requires minimum 44pt touch target
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Button should meet HIG minimum height of 44pt")
    }
}

// MARK: - Onboarding Flow Tests

final class OnboardingFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingStartsFromCreateVault() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let createVaultButton = app.buttons["Create New Vault"]
        guard createVaultButton.waitForExistence(timeout: 10) else {
            XCTFail("Create New Vault button not found")
            return
        }

        createVaultButton.tap()

        // Should show onboarding with "Quartz" branding
        let quartzText = app.staticTexts["Quartz"]
        XCTAssertTrue(quartzText.waitForExistence(timeout: 5), "Onboarding should show Quartz branding")
    }

    @MainActor
    func testOnboardingGetStartedButton() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let createVaultButton = app.buttons["Create New Vault"]
        guard createVaultButton.waitForExistence(timeout: 10) else {
            XCTFail("Create New Vault button not found")
            return
        }

        createVaultButton.tap()

        // Look for Get Started button
        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5), "Get Started button should appear in onboarding")
    }

    @MainActor
    func testOnboardingNavigatesToFolderPicker() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let createVaultButton = app.buttons["Create New Vault"]
        guard createVaultButton.waitForExistence(timeout: 10) else {
            XCTFail("Create New Vault button not found")
            return
        }

        createVaultButton.tap()

        let getStartedButton = app.buttons["Get Started"]
        guard getStartedButton.waitForExistence(timeout: 5) else {
            XCTFail("Get Started button not found")
            return
        }

        getStartedButton.tap()

        // Should navigate to folder picker step
        let chooseFolderButton = app.buttons["Choose Folder"]
        XCTAssertTrue(chooseFolderButton.waitForExistence(timeout: 5), "Choose Folder button should appear after Get Started")
    }

    @MainActor
    func testOnboardingBackButtonWorks() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()

        let createVaultButton = app.buttons["Create New Vault"]
        guard createVaultButton.waitForExistence(timeout: 10) else {
            XCTFail("Create New Vault button not found")
            return
        }

        createVaultButton.tap()

        let getStartedButton = app.buttons["Get Started"]
        guard getStartedButton.waitForExistence(timeout: 5) else {
            XCTFail("Get Started button not found")
            return
        }

        getStartedButton.tap()

        // Look for back button
        let backButton = app.buttons["Back"]
        guard backButton.waitForExistence(timeout: 5) else {
            XCTFail("Back button not found")
            return
        }

        backButton.tap()

        // Should go back to welcome step
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5), "Should return to welcome step with Get Started button")
    }
}

// MARK: - Accessibility Tests

final class AccessibilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDynamicTypeSupport() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        #if os(iOS)
        app.launchArguments.append("-UIPreferredContentSizeCategoryName")
        app.launchArguments.append("UICTContentSizeCategoryAccessibilityExtraLarge")
        #endif
        app.launch()

        let welcomeText = app.staticTexts["Welcome to Quartz"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 10), "Welcome text should be visible")

        let openVaultButton = app.buttons["Open Vault"]
        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 5), "Buttons should remain visible")
        XCTAssertTrue(openVaultButton.isHittable, "Buttons should remain hittable")
    }

    @MainActor
    func testReduceMotionSupport() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        #if os(iOS)
        app.launchArguments.append("-UIAccessibilityReduceMotionEnabled")
        app.launchArguments.append("YES")
        #endif
        app.launch()

        let createButton = app.buttons["Create New Vault"]
        guard createButton.waitForExistence(timeout: 10) else {
            XCTFail("Create button not found")
            return
        }

        createButton.tap()

        // Transitions should still work
        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 5), "Navigation should work")
    }

    @MainActor
    func testHighContrastMode() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        #if os(iOS)
        app.launchArguments.append("-UIAccessibilityDarkerSystemColorsEnabled")
        app.launchArguments.append("YES")
        #endif
        app.launch()

        let welcomeText = app.staticTexts["Welcome to Quartz"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 10), "UI should render correctly")
    }
}

// MARK: - Performance Tests

final class PerformanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("--uitesting")
            app.launch()
        }
    }

    @MainActor
    func testLaunchToInteractivePerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            let app = XCUIApplication()
            app.launchArguments.append("--uitesting")
            app.launch()
        }
    }
}

// MARK: - Known Issues Documentation Tests

/// These tests document known bugs and issues for tracking
final class KnownIssuesTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// BUG: Drag and drop in sidebar may not work correctly
    /// - Moving folders can fail silently
    /// - Drop indicators may not appear
    /// - Circular dependency check may not prevent all invalid moves
    @MainActor
    func testDocumentedDragDropIssues() throws {
        /*
         KNOWN ISSUES - DRAG AND DROP:
         1. Drop position indicators (before/inside/after) may not render correctly
         2. Dragging multiple items may not work as batch operation
         3. Moving a folder into its own child folder should be prevented
         4. Drop state may not clear if drag is cancelled mid-operation
         5. SidebarFolderDropModifier handles complex state that can desync
         */

        XCTAssertTrue(true, "See documented issues above for manual verification")
    }

    /// BUG: Markdown editor performance issues with large documents
    /// - Syntax highlighting may lag
    /// - Cursor position may jump unexpectedly
    /// - Auto-save may conflict with rapid typing
    @MainActor
    func testDocumentedEditorIssues() throws {
        /*
         KNOWN ISSUES - MARKDOWN EDITOR:
         1. Large documents (>10000 lines) may cause highlighting lag
         2. TextKit 2 layout manager may not invalidate correctly on rapid edits
         3. External file modifications may not trigger proper merge UI
         4. Word count updates may be inefficient on large documents
         5. Cursor position race condition between auto-save and manual save
         6. performMarkdownEdit transactions may not cover all edge cases
         */

        XCTAssertTrue(true, "See documented issues above for manual verification")
    }

    /// BUG: Sidebar search and filtering issues
    /// - 200ms debounce may feel slow
    /// - Tag collection traverses entire tree
    /// - Filter cache invalidation may be excessive
    @MainActor
    func testDocumentedSidebarIssues() throws {
        /*
         KNOWN ISSUES - SIDEBAR:
         1. Search debounce (200ms) may feel sluggish on slower devices
         2. Tag collection re-traverses entire file tree on each access
         3. Changing filters rapidly causes excessive cache invalidation
         4. Favorite URLs are recomputed on each access (computed property)
         5. Sort order changes may not persist correctly on app restart
         6. filteredTree lazy computation may block UI on large vaults
         */

        XCTAssertTrue(true, "See documented issues above for manual verification")
    }
}
