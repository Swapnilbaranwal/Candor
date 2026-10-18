import XCTest

/// Measures the delay between tapping the login phone field and the keyboard
/// becoming visible, for the first tap (cold) and second tap (warm).
final class LoginKeyboardDelayUITests: XCTestCase {

    @MainActor
    func testFirstTapKeyboardDelay() throws {
        let app = XCUIApplication()
        // Force the signed-out login screen via the UserDefaults argument domain.
        app.launchArguments += ["-candor.signedIn", "NO"]
        app.launch()

        // The landing page opens the sign-in sheet.
        let getStarted = app.buttons["getStarted"].firstMatch
        if getStarted.waitForExistence(timeout: 15) { getStarted.tap() }

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Login text field not found")
        // Let the intro spring animations settle so tap() doesn't stall waiting for quiescence.
        Thread.sleep(forTimeInterval: 2.5)

        let keyboard = app.keyboards.firstMatch

        let firstStart = Date()
        field.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 30), "Keyboard never appeared on first tap")
        let firstDelay = Date().timeIntervalSince(firstStart)
        NSLog("CANDOR_MEASURE first_tap_to_keyboard_seconds=%.3f", firstDelay)

        // Dismiss via the keyboard toolbar's Done button, then measure a warm second tap.
        // Found by identifier, not title: the title is translated into the app's language.
        let done = app.buttons["keyboardDone"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 10), "Keyboard did not dismiss")
        Thread.sleep(forTimeInterval: 1.0)

        let secondStart = Date()
        field.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 30), "Keyboard never appeared on second tap")
        let secondDelay = Date().timeIntervalSince(secondStart)
        NSLog("CANDOR_MEASURE second_tap_to_keyboard_seconds=%.3f", secondDelay)
    }
}
