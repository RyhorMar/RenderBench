import BenchCore
import BenchHost
import BenchRuntime
import Testing
@testable import ShaderBackend

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
    let descriptor = ShaderRenderer.descriptor
    #expect(descriptor.identifier == "shader")
    #expect(descriptor.displayName == "SwiftUI Shader")
    #expect(descriptor.reportsRasterTime == false)
    #expect(descriptor.reportsGPUTime == false)
}

@MainActor
@Test
func pointsDrawnMatchesPointsSubmittedWhenNoPointIsABreak() {
    let renderer = ShaderRenderer()
    let frame = manyPointsFrame()
    let report = renderer.encode(frame)
    #expect(report.pointsDrawn == frame.pointsSubmitted)
}

/// SwiftUI's compositor submits `colorEffect`'s own draw commands on a thread this process does
/// not observe, active or not — reporting any number here, including `0` once torn down, would be
/// a guess wearing a measurement's clothes.
@MainActor
@Test
func drawCallsIsAlwaysNilRegardlessOfTeardown() {
    let renderer = ShaderRenderer()
    #expect(renderer.encode(manyPointsFrame()).drawCalls == nil)
    renderer.teardown()
    #expect(renderer.encode(manyPointsFrame()).drawCalls == nil)
}

@MainActor
@Test
func encodeAdvancesEncodedRevisionByOneEachCall() {
    let renderer = ShaderRenderer()
    #expect(renderer.encodedRevision == 0)
    _ = renderer.encode(manyPointsFrame())
    #expect(renderer.encodedRevision == 1)
    _ = renderer.encode(manyPointsFrame())
    #expect(renderer.encodedRevision == 2)
}

@MainActor
@Test
func teardownIsIdempotentAndLeavesTheRendererInert() {
    let renderer = ShaderRenderer()
    _ = renderer.encode(manyPointsFrame())
    renderer.teardown()
    renderer.teardown()
    let revisionAfterTeardown = renderer.encodedRevision

    let report = renderer.encode(manyPointsFrame())
    #expect(report.encodeNs == 0)
    #expect(report.pointsDrawn == 0)
    #expect(report.drawCalls == nil)
    #expect(renderer.encodedRevision == revisionAfterTeardown, "a torn-down renderer must not advance further")
}

@MainActor
@Test
func suspendAndResumeAreHarmlessWhenCalledRepeatedly() {
    let renderer = ShaderRenderer()
    renderer.suspend()
    renderer.suspend()
    renderer.resume()
    renderer.resume()
    let report = renderer.encode(manyPointsFrame())
    #expect(report.pointsDrawn == manyPointsFrame().pointsSubmitted)
}
