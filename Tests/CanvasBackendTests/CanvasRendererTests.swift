import BenchCore
import BenchHost
import BenchRuntime
import SwiftUI
import Testing
@testable import CanvasBackend

/// The concrete `View` type an `AnyView` erases, found by reflection.
///
/// `type(of: someAnyView) == AnyView.self` is always true and proves nothing: `AnyView` erases to
/// itself by definition. The actual risk the contract calls out — a conformer whose `surface`
/// sometimes wraps a different concrete type — only shows up in the boxed value `AnyView` hides,
/// which is why this reaches for `Mirror` rather than comparing `AnyView` values directly.
private func erasedViewTypeName(_ view: AnyView) -> String {
    guard let boxed = Mirror(reflecting: view).children.first?.value else { return "AnyView" }
    return String(reflecting: type(of: boxed))
}

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
func encodeReportsWhatItDrewAndSurfaceIsStable() {
    let renderer = CanvasRenderer()
    let frame = onePointFrame()

    let beforeRevision = renderer.encodedRevision
    let firstSurfaceType = erasedViewTypeName(renderer.surface)
    let report = renderer.encode(frame)

    #expect(report.pointsDrawn == 100)
    #expect(report.drawCalls >= 1)
    // `encodedRevision` is the handle `surface` and `takeDeferredTimes` both key off; a renderer
    // that stops advancing it looks, to everything downstream, exactly like one that froze.
    #expect(renderer.encodedRevision == beforeRevision + 1)
    // Same wrapped type before and after a real frame: SwiftUI recreates a `UIViewRepresentable`
    // coordinator — and, for the Metal backend, recompiles a shader — whenever this changes.
    #expect(erasedViewTypeName(renderer.surface) == firstSurfaceType)

    renderer.teardown()
    // A torn-down renderer is inert, not crashing.
    let afterTeardown = renderer.encode(frame)
    #expect(afterTeardown.pointsDrawn == 0)
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
