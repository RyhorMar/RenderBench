import BenchCore
import BenchHost
import BenchRuntime
import Metal
import Testing
@testable import SceneKitBackend

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

@MainActor
@Test
func descriptorReportsNeitherRasterNorGPUTime() {
    let descriptor = SceneKitRenderer.descriptor
    #expect(descriptor.identifier == "scenekit")
    #expect(descriptor.displayName == "SceneKit")
    #expect(!descriptor.reportsRasterTime)
    #expect(!descriptor.reportsGPUTime)
}

@MainActor
@Test
func encodeAdvancesEncodedRevisionByOneEachCall() {
    let renderer = SceneKitRenderer()
    #expect(renderer.encodedRevision == 0)
    _ = renderer.encode(onePointFrame())
    #expect(renderer.encodedRevision == 1)
    _ = renderer.encode(onePointFrame())
    #expect(renderer.encodedRevision == 2)
}

/// This backend builds its own vertex array per series, so — unlike Core Animation or Swift
/// Charts, which hand a description to a render server that owns the count — it has a real
/// number of samples drawn to report.
@MainActor
@Test
func pointsDrawnIsTheRealCountWhenADeviceExists() {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let renderer = SceneKitRenderer()
    let report = renderer.encode(onePointFrame(pointCount: 100))
    #expect(report.pointsDrawn == 100)
}

/// A host with no Metal device cannot deliver anything through `SCNView`, so it cannot know a
/// count either — `nil`, not the real count this backend could otherwise report.
@MainActor
@Test
func pointsDrawnIsNilWithNoDevice() {
    let renderer = SceneKitRenderer(device: nil)
    let report = renderer.encode(onePointFrame())
    #expect(report.pointsDrawn == nil)
}

/// `SCNView` tessellates and submits this backend's geometry to the GPU on its own thread, after
/// `encode(_:)` has already returned — the same reason Core Animation and Swift Charts report
/// `nil` here regardless of device.
@MainActor
@Test
func drawCallsIsAlwaysNil() {
    let renderer = SceneKitRenderer()
    let report = renderer.encode(onePointFrame())
    #expect(report.drawCalls == nil)
}

@MainActor
@Test
func teardownIsIdempotentAndLeavesTheRendererInert() {
    let renderer = SceneKitRenderer()
    _ = renderer.encode(onePointFrame())
    renderer.teardown()
    renderer.teardown()
    let revisionAfterTeardown = renderer.encodedRevision

    let report = renderer.encode(onePointFrame())
    #expect(report.encodeNs == 0)
    #expect(report.pointsDrawn == nil)
    #expect(report.drawCalls == nil)
    #expect(renderer.encodedRevision == revisionAfterTeardown, "a torn-down renderer must not advance further")
}

@MainActor
@Test
func suspendAndResumeAreHarmlessWhenCalledRepeatedly() {
    let renderer = SceneKitRenderer()
    renderer.suspend()
    renderer.suspend()
    renderer.resume()
    renderer.resume()
    let report = renderer.encode(onePointFrame())
    #expect(report.encodeNs > 0)
}
