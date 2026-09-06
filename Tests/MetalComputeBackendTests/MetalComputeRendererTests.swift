import BenchCore
import BenchHost
import BenchRuntime
import Metal
import SwiftUI
import Testing
@testable import MetalComputeBackend

/// Every point in the window, unreduced — the shape of frame this backend actually receives once
/// the scene sets `policy: .none` for it, per `RendererDescriptor.reducesOnGPU`'s own doc comment.
private func windowFrame(pointCount: Int = 3_000) -> PreparedFrame {
    var frame = PreparedFrame(plotRect: PlotRect(x: 52, y: 10, width: 960, height: 736))
    frame.series = [
        PreparedSeries(
            index: 0,
            colour: Palette.colour(forSeries: 0, dark: false),
            points: (0..<pointCount).map {
                let x = Double($0) / Double(pointCount - 1)
                return PlottedPoint(x: x, y: 0.5 + 0.4 * sin(x * 40), isBreak: false)
            }
        ),
    ]
    frame.chrome = ChromeLayout.build(plot: frame.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    return frame
}

@MainActor @Test
func encodedRevisionAdvancesOnEveryEncode() {
    let renderer = MetalComputeRenderer()
    let before = renderer.encodedRevision
    _ = renderer.encode(windowFrame())
    #expect(renderer.encodedRevision == before + 1)
    _ = renderer.encode(windowFrame())
    #expect(renderer.encodedRevision == before + 2)
}

/// The card's own acceptance criterion: the GPU actually reduced the window rather than merely
/// drawing it. Twenty thousand raw points, against a 960-point-wide plot that reduces each run to
/// roughly two points per pixel column, must come back as far fewer after reduction.
@MainActor @Test
func pointsDrawnIsMeaningfullySmallerThanTheRawWindow() {
    let renderer = MetalComputeRenderer()
    // The only documented reason `pointsDrawn` may come back `nil` here is "no device on this
    // host" — skip for that, but a device that exists and still failed to reduce must fail this
    // test loudly rather than pass on an untested condition.
    guard renderer.device != nil else { return }
    let frame = windowFrame(pointCount: 20_000)
    let report = renderer.encode(frame)
    guard let pointsDrawn = report.pointsDrawn else {
        Issue.record("a device exists but pointsDrawn came back nil — reduction must have failed")
        return
    }
    #expect(pointsDrawn > 0)
    #expect(pointsDrawn < 20_000 / 4, "\(pointsDrawn) of 20000 raw points is not a meaningful reduction")
}

/// A host with no Metal device cannot know whether anything was drawn, and must say so — the same
/// reporting `MetalRenderer` gives for the same reason.
@MainActor @Test
func encodeReportsNilCountsWhenThereIsNoDevice() {
    let renderer = MetalComputeRenderer(device: nil)
    #expect(renderer.device == nil)
    let report = renderer.encode(windowFrame())
    #expect(report.pointsDrawn == nil)
    #expect(report.drawCalls == nil)
}

/// Once torn down this backend genuinely submits nothing — it counts its own submissions, unlike
/// a render-server backend — so `0` here is a known fact, not the fabricated zero a prior card's
/// defect reported in place of an honest `nil`. `teardownActuallyReleasesTheEncodedGeometry` below
/// checks the companion half of that same defect: releasing state, not only refusing to advance.
@MainActor @Test
func teardownReportsKnownZerosNotFabricatedOnes() {
    let renderer = MetalComputeRenderer()
    _ = renderer.encode(windowFrame())
    let revisionBeforeTeardown = renderer.encodedRevision
    renderer.teardown()

    let report = renderer.encode(windowFrame())
    #expect(report.pointsDrawn == 0)
    #expect(report.drawCalls == 0)
    #expect(report.encodeNs == 0)
    #expect(renderer.encodedRevision == revisionBeforeTeardown, "a torn-down renderer must not keep advancing its revision")
}

@MainActor @Test
func teardownActuallyReleasesTheEncodedGeometry() {
    let renderer = MetalComputeRenderer()
    _ = renderer.encode(windowFrame())
    #expect(!renderer.geometry.isEmpty)
    renderer.teardown()
    #expect(renderer.geometry.isEmpty, "teardown() left the previous frame's geometry in place")
}

@MainActor @Test
func drawCallsCountsOneBatchPerSeriesPlusChrome() {
    let renderer = MetalComputeRenderer()
    guard renderer.device != nil else { return }
    // No ticks: only the two axis lines, sharing one style, merge into a single chrome batch —
    // the same reasoning `MetalRenderer`'s own equivalent test states.
    let report = renderer.encode(windowFrame())
    #expect(report.drawCalls == 2)
}

@MainActor @Test
func takeDeferredTimesStartsWithNothingToReport() {
    let renderer = MetalComputeRenderer()
    _ = renderer.encode(windowFrame())
    let deferred = renderer.takeDeferredTimes()
    #expect(deferred.raster == nil)
    #expect(deferred.gpu == nil)
}

@MainActor @Test
func descriptorDeclaresGPUReduction() {
    #expect(MetalComputeRenderer.descriptor.reducesOnGPU)
    #expect(MetalComputeRenderer.descriptor.identifier == "metal-compute")
    #expect(MetalComputeRenderer.descriptor.reportsRasterTime)
    #expect(MetalComputeRenderer.descriptor.reportsGPUTime)
}
