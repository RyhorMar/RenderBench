import BenchCore
import BenchHost
import BenchRuntime
import SwiftUI
import Testing
@testable import MetalBackend

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
    let renderer = MetalRenderer()
    let frame = onePointFrame()

    let beforeRevision = renderer.encodedRevision
    let firstSurfaceType = erasedViewTypeName(renderer.surface)
    let report = renderer.encode(frame)

    #expect(report.pointsDrawn == 100)
    #expect(report.drawCalls >= 1)
    #expect(renderer.encodedRevision == beforeRevision + 1)
    // Same wrapped type before and after a real frame: on iOS this is what keeps SwiftUI from
    // recreating the `MTKView` coordinator — and recompiling the shader, about 48 ms — on every
    // tick; on the host this test actually runs on it is the platform-branch fallback, but the
    // property being tested (one fixed type, never a second one) is the same either way.
    #expect(erasedViewTypeName(renderer.surface) == firstSurfaceType)

    renderer.teardown()
    // A torn-down renderer is inert, not crashing.
    let afterTeardown = renderer.encode(frame)
    #expect(afterTeardown.pointsDrawn == 0)
}

/// `pointsDrawn` counts samples, not vertices: `MetalChartGeometry.points` also holds the chrome's
/// vertices, so reading the count off it directly would report more points than any series
/// actually submitted.
@MainActor @Test
func pointsDrawnCountsSeriesSamplesNotTheSharedVertexBuffer() {
    let renderer = MetalRenderer()
    let frame = onePointFrame(pointCount: 100)
    let report = renderer.encode(frame)

    // Two batches — grid+axes share a style and merge into one, the series is the other — and
    // several times as many raw vertices once the chrome's own points are counted in.
    #expect(report.pointsDrawn == 100)
    #expect(report.pointsDrawn < renderer.geometry.points.count)
}

/// The mutation this exists to catch leaves `teardown()` setting the flag that makes `encode(_:)`
/// inert without actually releasing what it already built — a torn-down renderer that answers
/// `encode` with zeros while still holding the last frame's buffers alive underneath.
@MainActor @Test
func teardownActuallyReleasesTheEncodedGeometry() {
    let renderer = MetalRenderer()
    _ = renderer.encode(onePointFrame())
    #expect(!renderer.geometry.isEmpty)

    renderer.teardown()
    #expect(renderer.geometry.isEmpty, "teardown() left the previous frame's geometry in place")
}

/// Both channels are collected — the point of a backend that times its own upload as well as the
/// GPU that draws it — and each stays independently absent until its own recorder has something.
@MainActor @Test
func takeDeferredTimesStartsWithNothingToReport() {
    let renderer = MetalRenderer()
    _ = renderer.encode(onePointFrame())
    let deferred = renderer.takeDeferredTimes()
    #expect(deferred.raster == nil)
    #expect(deferred.gpu == nil)
}
