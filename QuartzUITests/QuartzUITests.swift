//
//  QuartzUITests.swift
//  QuartzUITests
//
//  Created by Posselt, Oliver on 13.03.26.
//

import XCTest

final class QuartzUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenShowsOnLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Welcome screen should be visible with the "Welcome to Quartz" text
        let welcomeText = app.staticTexts["Welcome to Quartz"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 5), "Welcome screen should be displayed on first launch")
    }

    @MainActor
    func testOpenVaultButtonExists() throws {
        let app = XCUIApplication()
        app.launch()

        // The "Open Vault" button should be present on the welcome screen
        let openVaultButton = app.buttons["Open Vault"]
        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 5), "Open Vault button should be visible")
    }

    @MainActor
    func testSettingsButtonExists() throws {
        let app = XCUIApplication()
        app.launch()

        // Settings gear button should be available in the toolbar
        let settingsButton = app.buttons["gearshape"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should be visible in toolbar")
    }

    @MainActor
    func testOpenVaultShowsVaultPicker() throws {
        let app = XCUIApplication()
        app.launch()

        let openVaultButton = app.buttons["Open Vault"]
        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 5))
        openVaultButton.tap()

        // VaultPickerView should appear as a sheet
        let vaultTitle = app.staticTexts["Open a Vault"]
        XCTAssertTrue(vaultTitle.waitForExistence(timeout: 5), "Vault picker sheet should appear")
    }

    @MainActor
    func testVaultPickerCancelDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let openVaultButton = app.buttons["Open Vault"]
        XCTAssertTrue(openVaultButton.waitForExistence(timeout: 5))
        openVaultButton.tap()

        // Cancel button should dismiss the picker
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button should be visible")
        cancelButton.tap()

        // Welcome screen should be visible again
        let welcomeText = app.staticTexts["Welcome to Quartz"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 5), "Welcome screen should reappear after cancel")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
