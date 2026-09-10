import XCTest

/// Pushes every method screen by its catalogue identifier, confirms its frame counter is
/// actually advancing while the screen is on screen, and pops back — plus a second test that
/// backgrounds and returns to the one GPU-driven backend and checks the counter resumed rather
/// than staying at whatever it read when the app was suspended.
///
/// Navigation goes through ``tap(_:until:describing:)`` rather than a bare `tap()`. Measured on an
/// iPhone 16 Pro over 54 taps: roughly one in twenty is not acted on — the control is present,
/// hittable and at its settled frame, the app stays where it was, and an identical repeat works.
/// One sample caught the back button mid-transition, 6.9 pt wide in the middle of the screen
/// instead of 44 pt in the corner, which is what the automation was aiming at. The layer that
/// drops the tap is not identified, so the count of attempts is printed rather than swallowed:
/// a bare retry makes a gate green by luck, a recorded one makes the luck visible.
@MainActor
final class NavigationUITests: XCTestCase {
    /// `Catalogue.renderers`' own order — see that file. A UI test can't `@testable import` the
    /// app (it drives a separate process), so this list is the one place the set is retyped.
    private static let backendIDs = [
        "canvas", "core-animation", "metal", "swift-charts", "shape-path",
        "core-image", "scenekit", "shader", "metal-compute",
    ]

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testEveryMethodScreenPushesAndCountsFrames() throws {
        let counter = app.staticTexts["hud.frames"]
        for id in Self.backendIDs {
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(id) row missing from the root list")
            tap(row, until: { counter.exists }, describing: "\(id) never showed a frame counter")

            let before = try framesDrawn(counter)
            Thread.sleep(forTimeInterval: 0.5)
            let after = try framesDrawn(counter)
            XCTAssertGreaterThan(after, before, "\(id) frame counter did not advance")

            tap(
                app.navigationBars.buttons.element(boundBy: 0),
                until: { app.buttons[id].exists },
                describing: "\(id) did not pop back to the root list"
            )
        }
    }

    func testMetalKeepsCountingAfterBackgroundAndReturn() throws {
        let row = app.buttons["metal"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let counter = app.staticTexts["hud.frames"]
        tap(row, until: { counter.exists }, describing: "metal never showed a frame counter")

        XCUIDevice.shared.press(.home)
        app.activate()

        let before = try framesDrawn(counter)
        Thread.sleep(forTimeInterval: 0.5)
        let after = try framesDrawn(counter)
        XCTAssertGreaterThan(after, before, "metal's frame counter stayed put after returning from background")
    }

    /// Taps until the tap has been acted on, and says how many taps that took.
    ///
    /// Not a retry around the assertion: the condition is what the test is asserting, and a run
    /// that never reaches it still fails. What the repeat absorbs is a tap the interface does not
    /// act on at all — see this class's own note for the measurement.
    private func tap(
        _ element: XCUIElement,
        until condition: () -> Bool,
        describing failure: String,
        attempts: Int = 3,
        timeout: TimeInterval = 5
    ) {
        for attempt in 1...attempts {
            element.tap()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() {
                    if attempt > 1 { print("NAV took \(attempt) taps: \(failure)") }
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        XCTFail("\(failure) — after \(attempts) taps")
    }

    /// `hud.frames`'s label is `ChartScene.framesDrawn` interpolated raw — no separator, no
    /// unit suffix — see `HUDView.swift`.
    private func framesDrawn(_ counter: XCUIElement) throws -> Int {
        try XCTUnwrap(Int(counter.label), "hud.frames label wasn't a plain integer: \(counter.label)")
    }
}
