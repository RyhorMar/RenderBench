import XCTest

/// The backend control on Compare: nine chips, every name whole, every one reachable.
@MainActor
final class CompareUITests: XCTestCase {
    /// `Catalogue.rows`' own order and the names its descriptors carry. A UI test drives a
    /// separate process and cannot import them, so this is the one place they are retyped; a
    /// rename that does not reach here fails the test rather than passing quietly.
    private static let backends = [
        ("canvas", "Canvas"),
        ("core-animation", "Core Animation"),
        ("metal", "Metal"),
        ("swift-charts", "Swift Charts"),
        ("shape-path", "Shape + Path"),
        ("core-image", "Core Image"),
        ("scenekit", "SceneKit"),
        ("shader", "SwiftUI Shader"),
        ("metal-compute", "Metal compute"),
    ]

    func testEveryBackendChipCarriesItsWholeNameAndCanBeSelected() throws {
        let app = XCUIApplication()
        app.launch()

        let compare = app.buttons["Compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5), "Compare row missing from the root list")
        let firstChip = app.buttons["compare.backend.canvas"]
        tap(compare, until: { firstChip.exists }, describing: "Compare screen never appeared")

        for (id, name) in Self.backends {
            let chip = app.buttons["compare.backend.\(id)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "no chip for \(id)")
            XCTAssertEqual(chip.label, name, "\(id)'s chip does not carry its whole name")
        }

        // The chip a nine-segment control would have pushed off the end. Selecting it proves the
        // row scrolls to it and that the selection actually reaches the scene.
        let last = app.buttons["compare.backend.metal-compute"]
        XCTAssertFalse(last.isHittable, "the row fits on screen, so it does not need to scroll")
        last.tap()
        XCTAssertTrue(last.isHittable, "the last chip did not come into view")
        tap(last, until: { last.isSelected }, describing: "metal-compute never became the selection")
        XCTAssertFalse(app.buttons["compare.backend.canvas"].isSelected, "two chips selected at once")
    }

    /// Same reason as `NavigationUITests`: about one tap in twenty is not acted on, so the test
    /// waits for the state it asserts and says how many taps that took.
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
}
