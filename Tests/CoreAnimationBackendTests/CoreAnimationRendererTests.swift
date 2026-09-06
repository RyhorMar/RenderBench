import BenchCore
import BenchHost
import BenchRuntime
import SwiftUI
import Testing
@testable import CoreAnimationBackend

private func onePointFrame(pointCount: Int = 100) -> PreparedFrame {
    var frame = PreparedFrame(plotRect: PlotRect(x: 52, y: 10, width: 960, height: 736))
    frame.series = [
        PreparedSeries(
            index: 0,
            colour: Palette.colour(forSeries: 0, dark: false),
            points: (0..<pointCount).map { PlottedPoint(x: Double($0) / Double(pointCount - 1), y: 0.5, isBreak: false) }
        ),
    ]
    frame.chrome = ChromeLayout.build(plot: frame.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    return frame
}

@MainActor @Test
func encodeReportsWhatItDrew() {
    let renderer = CoreAnimationRenderer()
    let frame = onePointFrame()

    let beforeRevision = renderer.encodedRevision
    let report = renderer.encode(frame)

    #expect(report.pointsDrawn == 100)
    // The render server, not this process, decides how many submissions its own tessellation and
    // compositing cost — `nil` is the honest answer, not a layer count standing in for it.
    #expect(report.drawCalls == nil)
    #expect(renderer.encodedRevision == beforeRevision + 1)

    let revisionBeforeTeardown = renderer.encodedRevision
    renderer.teardown()
    // A torn-down renderer is inert, not crashing, and must not keep advancing the counter that
    // exists to prove it is still alive.
    let afterTeardown = renderer.encode(frame)
    #expect(afterTeardown.pointsDrawn == 0)
    #expect(renderer.encodedRevision == revisionBeforeTeardown)
}

/// This backend never observes rasterisation — the render server does that on its own thread,
/// after `encode(_:)` has returned — and `descriptor.reportsRasterTime == false` says so. A
/// non-`nil` reading here would be reporting a number nothing actually measured.
@MainActor @Test
func takeDeferredTimesNeverReportsAnythingItCannotObserve() {
    let renderer = CoreAnimationRenderer()
    _ = renderer.encode(onePointFrame())
    #expect(renderer.takeDeferredTimes() == .none)
}

/// `PreparedFrame.scale` reaches the layer, without a second, independently-sourced scale to
/// disagree with it: the render scale a retained-mode backend needs is already on the frame it is
/// handed, so `encode(_:)` is the only place it should come from.
@MainActor @Test
func encodeAppliesTheFramesScaleToTheLayer() {
    let renderer = CoreAnimationRenderer()
    var frame = onePointFrame()
    frame.scale = 3
    _ = renderer.encode(frame)

    #expect(renderer.layer.renderScale == 3)
}
