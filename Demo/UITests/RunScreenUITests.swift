import XCTest

/// The measure screen, seen from a simulator — which is exactly the case it has to refuse.
///
/// Running this on a device would be a different test: there the run starts and takes half an
/// hour. Here the interesting behaviour is the refusal, and a simulator is the one machine
/// guaranteed to trigger it, so the check that the reason reaches the screen is free.
@MainActor
final class RunScreenUITests: XCTestCase {
    func testTheRunIsRefusedOnASimulatorAndSaysWhy() throws {
        let app = XCUIApplication()
        app.launch()

        let measure = app.buttons["Measure"]
        XCTAssertTrue(measure.waitForExistence(timeout: 5), "Measure row missing from the root list")
        let status = app.staticTexts["run.status"]
        for _ in 1...3 where !status.exists { measure.tap() }
        XCTAssertTrue(status.waitForExistence(timeout: 5), "the measure screen never appeared")
        XCTAssertEqual(status.label, "Not started")

        // The disabled button carries the reason, and the reason names the conditions rather than
        // counting them. Both violations are real on a simulator and both must be named.
        let reason = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'blocked:'")
        ).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 5), "no reason under the disabled button")
        XCTAssertTrue(reason.label.contains("simulator"), reason.label)
        XCTAssertTrue(reason.label.contains("release configuration"), reason.label)

        // The row for a condition nobody can check stays unchecked rather than counting as met.
        let unobservable = app.staticTexts["Aeroplane mode on, brightness fixed"]
        XCTAssertTrue(unobservable.exists, "the unobservable conditions were dropped from the list")
    }
}
