import XCTest

/// Walks Candor for the pitch deck: saves screenshots, timings and a verdict-accuracy report
/// to `deck-capture/` next to the project. Run it on an iOS Simulator, because it writes to the Mac's disk.
///
/// Each launch injects its own persona through the UserDefaults argument domain, so the runs
/// start from a known state whatever is saved in the simulator.
@MainActor
final class DeckCaptureUITests: XCTestCase {

    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("deck-capture", isDirectory: true)

    private var notes: [String] = []

    // MARK: - Launching

    /// JSON for `Persona`, as old-style property-list data (`<hex>`), which UserDefaults reads as Data.
    private func personaArgument(language: String, name: String, currency: String, complete: Bool) -> String {
        let json = "{\"name\":\"\(name)\",\"phone\":\"\",\"signInMethod\":\"guest\",\"homeCurrency\":\"\(currency)\","
            + "\"languageCode\":\"\(language)\",\"travelStyle\":\"comfort\",\"interests\":[\"Heritage\",\"Street food\"],"
            + "\"tripDays\":3,\"isComplete\":\(complete ? "true" : "false")}"
        return "<" + json.utf8.map { String(format: "%02x", $0) }.joined() + ">"
    }

    private func launchApp(language: String = "en", name: String = "Emma", currency: String = "EUR",
                           signedIn: Bool = true, complete: Bool = true, offline: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-candor.signedIn", signedIn ? "YES" : "NO",
            "-candor.persona", personaArgument(language: language, name: name, currency: currency, complete: complete),
            "-candor.records", "<5b5d>",
            "-candor.forceOffline", offline ? "YES" : "NO",
            "-candor.uiTesting", "YES"
        ]
        app.launch()
        if signedIn && complete { allowLocationIfAsked() }
        return app
    }

    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    // MARK: - Output

    private func note(_ text: String) {
        notes.append(text)
        NSLog("CANDOR_DECK note: %@", text)
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: Self.outputDir.appendingPathComponent(name + ".png"))
        } catch {
            note("could not save \(name).png: \(error.localizedDescription)")
        }
    }

    private func save(_ object: [String: Any], as file: String) {
        var payload = object
        payload["notes"] = notes
        do {
            try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Self.outputDir.appendingPathComponent(file))
        } catch {
            NSLog("CANDOR_DECK could not save %@: %@", file, error.localizedDescription)
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            NSLog("CANDOR_DECK %@ %@", file, text)
        }
    }

    // MARK: - Small helpers

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @discardableResult
    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval = 6, what: String) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            note("not found: \(what)")
            return false
        }
        element.tap()
        return true
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    /// Taps a tab by its English title.
    private func tab(_ app: XCUIApplication, _ title: String) {
        let inBar = app.tabBars.buttons[title]
        if inBar.waitForExistence(timeout: 4) {
            inBar.tap()
            return
        }
        let anywhere = app.buttons[title].firstMatch
        if anywhere.waitForExistence(timeout: 3) { anywhere.tap() } else { note("tab not found: \(title)") }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 4) { back.tap() } else { note("back button not found") }
    }

    // MARK: - Agent helpers

    private func agentState(_ app: XCUIApplication) -> String {
        (app.buttons["agentSend"].value as? String) ?? ""
    }

    /// Waits for the agent to finish and returns the run time and mode reported by the app itself.
    private func waitForAgent(_ app: XCUIApplication, previous: String, timeout: TimeInterval = 150) -> (seconds: Double, mode: String)? {
        let deadline = Date().addingTimeInterval(timeout)
        var sawWorking = false
        while Date() < deadline {
            let value = agentState(app)
            if value == "working" {
                sawWorking = true
            } else if value.hasPrefix("idle"), sawWorking || value != previous {
                let parts = value.split(separator: " ")
                let seconds = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
                let mode = parts.count > 2 ? String(parts[2]) : "unknown"
                return (seconds, mode)
            }
            pause(0.25)
        }
        note("agent did not finish within \(Int(timeout)) s")
        return nil
    }

    /// Types a question on the Agent tab and waits for the answer.
    private func ask(_ app: XCUIApplication, _ prompt: String) -> (seconds: Double, mode: String)? {
        let newChat = app.buttons["agentNewChat"]
        if newChat.exists && newChat.isEnabled { newChat.tap() }
        let input = app.descendants(matching: .any).matching(identifier: "agentInput").firstMatch
        guard input.waitForExistence(timeout: 8) else {
            note("agent input not found")
            return nil
        }
        let before = agentState(app)
        input.tap()
        input.typeText(prompt)
        app.buttons["agentSend"].tap()
        return waitForAgent(app, previous: before)
    }

    /// "fair", "high", "overcharge" or "info", read from the verdict badge's identifier (language-independent).
    private func verdict(_ app: XCUIApplication) -> String? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'verdict.'"))
        let count = query.count
        guard count > 0 else { return nil }
        let identifier = query.element(boundBy: count - 1).identifier
        return String(identifier.dropFirst("verdict.".count))
    }

    // MARK: - 1. Screens, in English

    func test1_CaptureScreens() throws {
        continueAfterFailure = true

        // Sign-in and persona setup.
        var app = launchApp(name: "", signedIn: false, complete: false)
        pause(2.5)
        shot("01-sign-in")
        if tapIfPresent(app.buttons["Continue as guest"], what: "Continue as guest") {
            let name = app.textFields["Your name"]
            if name.waitForExistence(timeout: 8) {
                pause(1)
                shot("02-persona-setup")
                name.tap()
                name.typeText("Emma")
                if tapIfPresent(app.buttons["Build my travel persona"], what: "Build my travel persona") {
                    pause(1.8)
                    shot("03-agent-setup")
                }
            } else {
                note("persona setup did not appear")
            }
        }
        allowLocationIfAsked()

        // Start again from a known, complete persona.
        app.terminate()
        app = launchApp()
        let example = app.buttons["homeExample"]
        XCTAssertTrue(example.waitForExistence(timeout: 20), "Home did not appear")
        pause(1.5)
        shot("04-home")

        // One-tap example: the agent's live trail, then the verdict card.
        let before = agentState(app)
        example.tap()
        pause(3)
        shot("05a-agent-working")
        if let run = waitForAgent(app, previous: before) {
            note("example run: \(run.seconds) s, \(run.mode)")
        }
        pause(1.6)
        shot("05b-agent-verdict")
        let steps = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Steps:'")).firstMatch
        if steps.exists {
            steps.tap()
            pause(0.8)
            shot("05c-agent-trail")
        }
        app.swipeUp()
        pause(0.8)
        shot("05d-agent-answer")

        // Ride fare.
        tab(app, "Home")
        if tapIfPresent(app.buttons["Check a ride"], what: "Check a ride") {
            if tapIfPresent(app.buttons["India Gate"], what: "India Gate chip") {
                _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'verdict.'")).firstMatch.waitForExistence(timeout: 20)
                let quote = app.textFields["Driver's quote (optional)"]
                if quote.waitForExistence(timeout: 4) {
                    quote.tap()
                    quote.typeText("300")
                    let done = app.buttons["keyboardDone"].exists ? app.buttons["keyboardDone"] : app.buttons["Done"]
                    if done.exists { done.tap() }
                }
                pause(1)
                shot("06a-ride-fare")
                app.swipeUp()
                pause(1)
                shot("06b-ride-verdict")
                let saveCheck = app.buttons["Save this check"]
                if saveCheck.exists && saveCheck.isHittable { saveCheck.tap() }
            }
            goBack(app)
        }

        // Scam radar.
        let scamTile = app.buttons["Scam radar"]
        scrollTo(scamTile, in: app)
        if tapIfPresent(scamTile, what: "Scam radar tile") {
            let first = app.buttons.matching(NSPredicate(format: "label CONTAINS 'hotel is closed'")).firstMatch
            if first.waitForExistence(timeout: 6) { first.tap() }
            pause(1)
            shot("07-scam-radar")
            goBack(app)
        }

        // Interpreter and the "show the driver" card.
        let interpreterTile = app.buttons["Interpreter"]
        scrollTo(interpreterTile, in: app)
        if tapIfPresent(interpreterTile, what: "Interpreter tile") {
            pause(1)
            app.swipeUp()
            pause(0.8)
            shot("08-interpreter")
            let phrase = app.staticTexts["Yeh kitne ka hai?"]
            if phrase.exists {
                // The "show full screen" button is the last button in the phrase's row.
                let rowButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'expand'"))
                if rowButtons.count > 0 {
                    rowButtons.element(boundBy: 0).tap()
                    pause(1.2)
                    shot("09-show-the-driver")
                    let close = app.buttons["Close"]
                    if close.exists { close.tap() }
                } else {
                    note("show-phrase button not found")
                }
            }
            goBack(app)
        }

        // Home again, now with a saved check.
        app.swipeDown()
        app.swipeDown()
        pause(1)
        shot("10-home-with-checks")

        // Explore, Scan, Me.
        tab(app, "Explore")
        pause(4)
        shot("11-explore")
        let marker = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Red Fort'")).firstMatch
        if marker.exists && marker.isHittable {
            marker.tap()
            pause(2)
            shot("11b-explore-place")
        }
        tab(app, "Scan")
        pause(1.5)
        shot("12-scan")
        tab(app, "Me")
        pause(1.5)
        shot("13-me")

        save(["test": "screens"], as: "capture-screens.json")
    }

    // MARK: - 2. Other languages

    func test2_CaptureLanguages() throws {
        continueAfterFailure = true
        let runs: [(code: String, name: String, currency: String, agent: Bool)] = [
            ("ja", "Yuki", "JPY", true),
            ("ar", "Omar", "AED", true),
            ("es", "Lucía", "EUR", false),
            ("de", "Jonas", "EUR", false)
        ]
        for run in runs {
            let app = launchApp(language: run.code, name: run.name, currency: run.currency)
            let example = app.buttons["homeExample"]
            guard example.waitForExistence(timeout: 20) else {
                note("\(run.code): Home did not appear")
                app.terminate()
                continue
            }
            pause(1.5)
            shot("20-home-\(run.code)")
            if run.agent {
                let before = agentState(app)
                example.tap()
                if let result = waitForAgent(app, previous: before) {
                    note("\(run.code) example run: \(result.seconds) s, \(result.mode)")
                }
                pause(1.6)
                shot("21-agent-\(run.code)")
            }
            app.terminate()
        }
        save(["test": "languages"], as: "capture-languages.json")
    }

    // MARK: - 3. Timings and verdict accuracy

    /// Scripted price questions with the verdict that Candor's own reference data implies.
    /// This checks that the agent reaches the right verdict from that data; it does not audit the data itself.
    private let scenarios: [(prompt: String, expected: String)] = [
        ("Is Rs 40 fair for a 1 litre water bottle?", "overcharge"),
        ("Is Rs 20 fair for a 1 litre water bottle?", "fair"),
        ("Is Rs 60 fair for a samosa?", "overcharge"),
        ("A street stall wants Rs 20 for a masala chai. Is that fair?", "fair"),
        ("Auto to India Gate, driver wants Rs 300", "overcharge"),
        ("Auto to India Gate, driver wants Rs 50", "fair"),
        ("Taxi to IGI Airport T3, driver asks Rs 2500", "overcharge"),
        ("Lassi for Rs 70 in Old Delhi, is that fair?", "fair"),
        ("Veg thali at a local restaurant for Rs 700, fair?", "overcharge"),
        ("Cycle rickshaw for 1 km in Old Delhi, he wants Rs 100", "high"),
        ("Bananas for Rs 90 a dozen, fair price?", "high"),
        ("Metro token for Rs 40, is that fair?", "fair")
    ]

    private func runScenarios(offline: Bool) -> [[String: Any]] {
        let app = launchApp(offline: offline)
        var rows: [[String: Any]] = []
        guard app.buttons["homeExample"].waitForExistence(timeout: 20) else {
            note("benchmark: Home did not appear (offline=\(offline))")
            return rows
        }
        tab(app, "Agent")
        for scenario in scenarios {
            var row: [String: Any] = ["prompt": scenario.prompt, "expected": scenario.expected]
            if let run = ask(app, scenario.prompt) {
                let got = verdict(app) ?? "none"
                row["seconds"] = run.seconds
                row["mode"] = run.mode
                row["verdict"] = got
                row["correct"] = got == scenario.expected
            } else {
                row["verdict"] = "timeout"
                row["correct"] = false
            }
            rows.append(row)
            NSLog("CANDOR_DECK scenario %@", String(describing: row))
        }
        app.terminate()
        return rows
    }

    func test3_Benchmark() throws {
        continueAfterFailure = true
        var report: [String: Any] = [
            "device": "iOS Simulator",
            "date": ISO8601DateFormatter().string(from: Date())
        ]

        // Launch to an interactive Home screen, timed by the test harness (so it includes harness overhead).
        var launches: [Double] = []
        for _ in 0..<5 {
            let app = XCUIApplication()
            app.terminate()
            app.launchArguments = [
                "-candor.signedIn", "YES",
                "-candor.persona", personaArgument(language: "en", name: "Emma", currency: "EUR", complete: true),
                "-candor.records", "<5b5d>",
                "-candor.uiTesting", "YES"
            ]
            let started = Date()
            app.launch()
            if app.buttons["homeExample"].waitForExistence(timeout: 20) {
                launches.append(Date().timeIntervalSince(started))
            }
            app.terminate()
        }
        report["launchSeconds"] = launches
        save(report, as: "benchmark.json")

        // Ride fare: tap a destination, wait for the verdict card.
        let rideApp = launchApp()
        var rides: [[String: Any]] = []
        if rideApp.buttons["Check a ride"].waitForExistence(timeout: 20) {
            rideApp.buttons["Check a ride"].tap()
            for place in ["India Gate", "Red Fort", "Qutub Minar", "Lotus Temple", "Khan Market"] {
                let chip = rideApp.buttons[place]
                guard chip.waitForExistence(timeout: 6) else {
                    note("ride chip not found: \(place)")
                    continue
                }
                let started = Date()
                chip.tap()
                // The distance label changes when the new route arrives.
                let deadline = Date().addingTimeInterval(20)
                var seconds: Double?
                while Date() < deadline {
                    if rideApp.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to \(place)")).firstMatch.exists {
                        seconds = Date().timeIntervalSince(started)
                        break
                    }
                    pause(0.1)
                }
                rides.append(["place": place, "seconds": seconds ?? -1])
            }
        } else {
            note("benchmark: ride screen not reachable")
        }
        rideApp.terminate()
        report["rideChecks"] = rides
        save(report, as: "benchmark.json")

        // Agent, with Gemini and with the on-device agent.
        report["geminiScenarios"] = runScenarios(offline: false)
        save(report, as: "benchmark.json")
        report["offlineScenarios"] = runScenarios(offline: true)
        save(report, as: "benchmark.json")
    }
}
