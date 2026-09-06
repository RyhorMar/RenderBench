import BenchCore
import BenchHost
import BenchRuntime
import SwiftUI
import Testing
@testable import CanvasBackend

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
    let renderer = CanvasRenderer()
    let frame = onePointFrame()

    let beforeRevision = renderer.encodedRevision
    let report = renderer.encode(frame)

    #expect(report.pointsDrawn == 100)
    // One background fill, one group of chrome lines (both axis lines share a colour and width,
    // and there are no grid lines in this fixture), one stroke for the one series.
    #expect(report.drawCalls == 3)
    // `encodedRevision` is the handle `surface` and `takeDeferredTimes` both key off; a renderer
    // that stops advancing it looks, to everything downstream, exactly like one that froze.
    #expect(renderer.encodedRevision == beforeRevision + 1)

    let revisionBeforeTeardown = renderer.encodedRevision
    renderer.teardown()
    // A torn-down renderer is inert, not crashing, and must not keep advancing the counter that
    // exists to prove it is still alive.
    let afterTeardown = renderer.encode(frame)
    #expect(afterTeardown.pointsDrawn == 0)
    #expect(renderer.encodedRevision == revisionBeforeTeardown)
}

/// The mutation this exists to catch reports `pointsSubmitted` where `pointsDrawn` belongs. A
/// frame with a break makes the two numbers differ, so the swap does not disappear by coincidence
/// the way it would on a gap-free fixture.
@MainActor @Test
func pointsDrawnCountsWhatWasActuallyStrokedNotWhatWasSubmitted() {
    let renderer = CanvasRenderer()
    var frame = onePointFrame(pointCount: 10)
    var points = frame.series[0].points
    points[5] = PlottedPoint(x: points[5].x, y: points[5].y, isBreak: true)
    frame.series = [PreparedSeries(index: 0, colour: frame.series[0].colour, points: points)]
    frame.pointsSubmitted = 999

    let report = renderer.encode(frame)
    // Nine, not ten: the break consumes a point without contributing a stroked segment.
    #expect(report.pointsDrawn == 9)
    #expect(report.pointsDrawn != frame.pointsSubmitted)
}

/// This backend's whole claim is that it can time its own draw pass — `reportsRasterTime` says so
/// — and that claim is only true if a real draw actually reaches `RasterTimeRecorder`.
/// `ImageRenderer` forces the `Canvas` closure to run, the way `CanvasChartViewTests` already does
/// for the plain view.
@MainActor @Test
func takeDeferredTimesReportsARealRasterTimeAfterTheViewDraws() {
    let renderer = CanvasRenderer()
    _ = renderer.encode(onePointFrame())
    let expectedRevision = renderer.encodedRevision

    let imageRenderer = ImageRenderer(content: renderer.surface.frame(width: 1024, height: 768))
    imageRenderer.scale = 1
    _ = imageRenderer.cgImage

    let deferred = renderer.takeDeferredTimes()
    #expect(deferred.raster != nil, "no raster time collected after the surface drew")
    #expect(deferred.raster?.encodedRevision == expectedRevision)
}
