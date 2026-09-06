import BenchCore
import BenchHost
import BenchRuntime
import Testing
@testable import ShapePathBackend

/// A frame with no breaks, so every point handed in is a point this backend must report drawing.
private func manyPointsFrame(pointCount: Int = 100) -> PreparedFrame {
    var frame = PreparedFrame(plotRect: PlotRect(x: 52, y: 10, width: 960, height: 736))
    frame.series = [
        PreparedSeries(
            index: 0,
            colour: Palette.colour(forSeries: 0, dark: false),
            points: (0..<pointCount).map {
                PlottedPoint(x: Double($0) / Double(pointCount - 1), y: 0.5, isBreak: false)
            }
        ),
    ]
    frame.pointsSubmitted = pointCount
    frame.chrome = ChromeLayout.build(plot: frame.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    return frame
}

@MainActor
@Test
func descriptorReportsNeitherRasterNorGPUTime() {
    let descriptor = ShapePathRenderer.descriptor
    #expect(descriptor.identifier == "shape-path")
    #expect(descriptor.displayName == "Shape + Path")
    #expect(descriptor.reportsRasterTime == false)
    #expect(descriptor.reportsGPUTime == false)
}

@MainActor
@Test
func pointsDrawnMatchesPointsSubmittedWhenNoPointIsABreak() {
    let renderer = ShapePathRenderer()
    let frame = manyPointsFrame()
    let report = renderer.encode(frame)
    #expect(report.pointsDrawn == frame.pointsSubmitted)
}

/// SwiftUI's render server compiles and submits `PolylineShape`'s own draw commands on a thread
/// this process does not observe. Reporting any number here would be a guess wearing a
/// measurement's clothes.
@MainActor
@Test
func drawCallsIsNilBecauseTheRenderServerOwnsSubmission() {
    let renderer = ShapePathRenderer()
    let report = renderer.encode(manyPointsFrame())
    #expect(report.drawCalls == nil)
}

@MainActor
@Test
func encodeAdvancesEncodedRevisionByOneEachCall() {
    let renderer = ShapePathRenderer()
    #expect(renderer.encodedRevision == 0)
    _ = renderer.encode(manyPointsFrame())
    #expect(renderer.encodedRevision == 1)
    _ = renderer.encode(manyPointsFrame())
    #expect(renderer.encodedRevision == 2)
}

@MainActor
@Test
func teardownIsIdempotentAndLeavesTheRendererInert() {
    let renderer = ShapePathRenderer()
    _ = renderer.encode(manyPointsFrame())
    renderer.teardown()
    renderer.teardown()
    let revisionAfterTeardown = renderer.encodedRevision

    let report = renderer.encode(manyPointsFrame())
    #expect(report.encodeNs == 0)
    #expect(report.pointsDrawn == 0)
    // `drawCalls` was never a number this backend has, torn down or active — `nil` here, same as
    // `drawCallsIsNilBecauseTheRenderServerOwnsSubmission` above, not a `0` this process cannot
    // back.
    #expect(report.drawCalls == nil)
    #expect(renderer.encodedRevision == revisionAfterTeardown, "a torn-down renderer must not advance further")
}

@MainActor
@Test
func suspendAndResumeAreHarmlessWhenCalledRepeatedly() {
    let renderer = ShapePathRenderer()
    renderer.suspend()
    renderer.suspend()
    renderer.resume()
    renderer.resume()
    let report = renderer.encode(manyPointsFrame())
    #expect(report.pointsDrawn == manyPointsFrame().pointsSubmitted)
}
