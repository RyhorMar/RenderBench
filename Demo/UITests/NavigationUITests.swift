import XCTest

/// Pushes every method screen by its catalogue identifier, confirms its frame counter is
/// actually advancing while the screen is on screen, and pops back — plus a second test that
/// backgrounds and returns to the one GPU-driven backend and checks the counter resumed rather
/// than staying at whatever it read when the app was suspended.
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
        for id in Self.backendIDs {
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(id) row missing from the root list")
            row.tap()

            let counter = app.staticTexts["hud.frames"]
            XCTAssertTrue(counter.waitForExistence(timeout: 5), "\(id) never showed a frame counter")
            let before = try framesDrawn(counter)
            Thread.sleep(forTimeInterval: 0.5)
            let after = try framesDrawn(counter)
            XCTAssertGreaterThan(after, before, "\(id) frame counter did not advance")

            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(
                app.buttons[id].waitForExistence(timeout: 3),
                "\(id) did not pop back to the root list"
            )
        }
    }

    func testMetalKeepsCountingAfterBackgroundAndReturn() throws {
        let row = app.buttons["metal"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let counter = app.staticTexts["hud.frames"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()

        let before = try framesDrawn(counter)
        Thread.sleep(forTimeInterval: 0.5)
        let after = try framesDrawn(counter)
        XCTAssertGreaterThan(after, before, "metal's frame counter stayed put after returning from background")
    }

    /// `hud.frames`'s label is `ChartScene.framesDrawn` interpolated raw — no separator, no
    /// unit suffix — see `HUDView.swift`.
    private func framesDrawn(_ counter: XCUIElement) throws -> Int {
        try XCTUnwrap(Int(counter.label), "hud.frames label wasn't a plain integer: \(counter.label)")
    }
}
