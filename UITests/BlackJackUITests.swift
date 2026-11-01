import XCTest

@MainActor
final class BlackJackUITests: XCTestCase {
    func testBankrollDiscoveryAndRecharge() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-progress", "--ui-testing-reset", "-ladyMode", "0"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €500")
        app.buttons["openProfile"].tap()
        app.buttons["Decks"].tap()
        XCTAssertEqual(app.buttons["deck_1"].label, "Blue deck, active")
        XCTAssertFalse(app.buttons["deck_2"].isEnabled)
        screenshot("Blue default and locked Pro", app)
        app.buttons["Close"].tap()
        app.buttons["PLAY NOW"].tap()
        let ten = app.buttons["chip_1000"]
        XCTAssertTrue(ten.waitForExistence(timeout: 5))
        ten.tap()
        app.buttons["chip_2500"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €465")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "pot").firstMatch.label, "Chips in pot €35")
        screenshot("Reserved chips and separate pot", app)
        app.buttons["Reset"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €500")
        app.buttons["All In"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €0")
        XCTAssertTrue(app.buttons["Deal"].isEnabled)
        XCTAssertTrue(app.buttons["chip_1000"].exists)
        XCTAssertFalse(app.buttons["chip_1000"].isEnabled)
        app.buttons["Back to lobby"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €500")
        app.buttons["PLAY NOW"].tap()
        app.buttons["chip_1000"].tap()
        app.terminate()
        app.launchArguments = ["-ladyMode", "0"]
        app.launch()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €500")
        let mode = app.buttons["modeSwitch"]
        mode.tap(withNumberOfTaps: 5, numberOfTouches: 1)
        let toast = app.descendants(matching: .any).matching(identifier: "modeToast").firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("PRO DECK UNLOCKED"))
        screenshot("First discovery reward", app)
        toast.tap()
        XCTAssertTrue(toast.waitForNonExistence(timeout: 4))
        app.buttons["openProfile"].tap()
        app.buttons["Decks"].tap()
        XCTAssertTrue(app.buttons["deck_2"].isEnabled)
        app.buttons["deck_2"].tap()
        XCTAssertEqual(app.buttons["deck_2"].label, "Pro deck, active")
        app.buttons["Recharge"].tap()
        let recharge = app.buttons["Recharge +€1,000"]
        XCTAssertTrue(recharge.isEnabled)
        recharge.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €1,500")
        XCTAssertFalse(recharge.isEnabled)
        XCTAssertTrue(app.staticTexts["Ready in"].exists)
        screenshot("Recharge cooldown", app)
        app.terminate()
        app.launch()
        app.buttons["openProfile"].tap()
        app.buttons["Recharge"].tap()
        XCTAssertFalse(app.buttons["Recharge +€1,000"].isEnabled)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch.label, "Balance €1,500")
        app.buttons["Close"].tap()
        app.buttons["modeSwitch"].tap(withNumberOfTaps: 5, numberOfTouches: 1)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "modeToast").firstMatch.waitForExistence(timeout: 3))
        app.descendants(matching: .any).matching(identifier: "modeToast").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "modeToast").firstMatch.waitForNonExistence(timeout: 4))
        app.buttons["openProfile"].tap()
        app.buttons["Decks"].tap()
        XCTAssertTrue(app.buttons["deck_2"].isEnabled)
        XCTAssertEqual(app.buttons["deck_2"].label, "Pro deck, active")
        app.buttons["Bonus"].tap()
        XCTAssertFalse(app.buttons["Recharge +€1,000"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "30-minute")).firstMatch.exists)
        screenshot("Normal rescue retained", app)
    }

    func testDealAndRebetDebitOnlyOnce() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-progress", "--ui-testing-reset", "-ladyMode", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["PLAY NOW"].waitForExistence(timeout: 10))
        app.buttons["PLAY NOW"].tap()
        XCTAssertTrue(app.buttons["chip_1000"].waitForExistence(timeout: 5))
        app.buttons["chip_1000"].tap()
        app.buttons["chip_2500"].tap()
        let bankroll = app.descendants(matching: .any).matching(identifier: "bankroll").firstMatch
        XCTAssertEqual(bankroll.label, "Balance €465")
        app.buttons["Deal"].tap()
        XCTAssertEqual(bankroll.label, "Balance €465", "Deal must not debit the reserved pot again")
        let playable = NSPredicate { _, _ in (app.buttons["Stand"].exists && app.buttons["Stand"].isEnabled) || app.buttons["New Bet"].exists }
        expectation(for: playable, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        if app.buttons["Stand"].exists && app.buttons["Stand"].isEnabled { app.buttons["Stand"].tap() }
        let next = app.buttons["New Bet"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: next)
        waitForExpectations(timeout: 10)
        let outcomes = ["Balance €465", "Balance €500", "Balance €535", "Balance €552.50"]
        XCTAssertTrue(outcomes.contains(bankroll.label), "The visible bankroll must match exactly one valid payout")
        screenshot("Completed hand with single payout", app)
        let before = Double(bankroll.label.replacingOccurrences(of: "Balance €", with: "").replacingOccurrences(of: ",", with: ""))!
        app.buttons["Rebet €35"].tap()
        let after = Double(bankroll.label.replacingOccurrences(of: "Balance €", with: "").replacingOccurrences(of: ",", with: ""))!
        XCTAssertEqual(after, before - 35, accuracy: 0.001, "Rebet reserves its stake exactly once")
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
