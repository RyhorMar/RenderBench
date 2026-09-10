import XCTest

/// A draft sweep across the nine backends, for a device.
///
/// **This is not the benchmark runner.** It has no warm-up, one repeat, a fixed order and no
/// preconditions, so what it produces is a set of readings from a real device rather than a
/// measurement that belongs in a results file. It exists to answer the question nobody can answer
/// from a simulator: whether the instrument behaves on real hardware at all — whether the display
/// link reaches 120 Hz, whether the GPU-timing backends report anything, and which readings stay
/// absent because the backend cannot know them.
///
/// Every figure it prints is an observation. The values are read out of the on-screen overlay by
/// identifier, which is why `HUDView` labels its value cells.
@MainActor
final class DeviceSweepTests: XCTestCase {
    private static let backendIDs = [
        "canvas", "core-animation", "metal", "swift-charts", "shape-path",
        "core-image", "scenekit", "shader", "metal-compute",
    ]

    /// Rows worth reading. `frames` climbs, so it is read twice to derive an observed rate.
    private static let readings = [
        "hud.fps", "hud.policy", "hud.prep-p50", "hud.prep-p95",
        "hud.draw-p50", "hud.draw-p95", "hud.gpu-p50", "hud.gpu-p95",
        "hud.points", "hud.dropped",
    ]

    /// Seconds each backend draws before its overlay is read. Long enough for the percentile sink to
    /// hold more than a handful of frames, short enough that nine of them stay under a minute and a
    /// half — thermal state is recorded either side precisely because that is not guaranteed.
    private static let dwell: TimeInterval = 6

    func testSweepEveryBackendAndPrintReadings() throws {
        let app = XCUIApplication()

        var lines: [String] = []
        for id in Self.backendIDs {
            // Relaunched per backend rather than popped back to the list. Two reasons, and the
            // first was found by this sweep failing: popping back after a heavyweight teardown
            // leaves the list unreachable often enough to lose the rest of the run. The second is
            // better for the readings themselves — every backend starts from a cold process instead
            // of inheriting whatever the previous one left warm.
            app.terminate()
            app.launch()
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(id) row missing from the root list")
            row.tap()

            let frames = app.staticTexts["hud.frames"]
            XCTAssertTrue(frames.waitForExistence(timeout: 10), "\(id) never showed a frame counter")
            let framesBefore = Int(frames.label) ?? 0
            let started = Date()
            Thread.sleep(forTimeInterval: Self.dwell)
            let elapsed = Date().timeIntervalSince(started)
            let framesAfter = Int(frames.label) ?? 0

            var fields: [String] = [
                "backend=\(id)",
                "frames=\(framesAfter - framesBefore)",
                "seconds=\(String(format: "%.2f", elapsed))",
                "observedHz=\(String(format: "%.1f", Double(framesAfter - framesBefore) / elapsed))",
            ]
            for identifier in Self.readings {
                let element = app.staticTexts[identifier]
                let value = element.exists ? element.label : "absent"
                fields.append("\(identifier.replacingOccurrences(of: "hud.", with: ""))=\(value)")
            }
            let line = fields.joined(separator: " · ")
            lines.append(line)
            print("SWEEP \(line)")

        }
        app.terminate()

        let report = lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "device-sweep"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SWEEP-REPORT-BEGIN\n\(report)\nSWEEP-REPORT-END")
    }
}
