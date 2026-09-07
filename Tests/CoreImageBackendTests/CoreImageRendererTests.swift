import BenchCore
import BenchHost
import BenchRuntime
import Metal
import Testing
@testable import CoreImageBackend

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
func descriptorReportsRasterAndGPUTime() {
    let descriptor = CoreImageRenderer.descriptor
    #expect(descriptor.identifier == "core-image")
    #expect(descriptor.displayName == "Core Image")
    #expect(descriptor.reportsRasterTime)
    #expect(descriptor.reportsGPUTime)
}

@MainActor
@Test
func encodeAdvancesEncodedRevisionByOneEachCall() {
    let renderer = CoreImageRenderer()
    #expect(renderer.encodedRevision == 0)
    _ = renderer.encode(onePointFrame())
    #expect(renderer.encodedRevision == 1)
    _ = renderer.encode(onePointFrame())
    #expect(renderer.encodedRevision == 2)
}

/// This backend hands `CoreGraphicsReference`'s whole raster to Core Image; it never itself
/// iterates per-point geometry, so it has no count of samples drawn to report — a fact about the
/// method, not a missing measurement. `nil` regardless of whether a device exists.
@MainActor
@Test
func pointsDrawnIsAlwaysNil() {
    let renderer = CoreImageRenderer()
    let report = renderer.encode(onePointFrame())
    #expect(report.pointsDrawn == nil)
}

/// On a host with a Metal device this backend issues exactly one Core Image render per frame, to
/// one fixed destination — a count it knows, unlike a render server deciding its own submissions
/// on a thread this process cannot observe.
@MainActor
@Test
func drawCallsIsOneWhenADeviceExists() {
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    let renderer = CoreImageRenderer()
    let report = renderer.encode(onePointFrame())
    #expect(report.drawCalls == 1)
}

/// A host with no Metal device cannot deliver anything, so it cannot know a count either — `nil`,
/// not the `0` a working delivery would report for a frame with nothing to draw.
@MainActor
@Test
func drawCallsIsNilWithNoDevice() {
    let renderer = CoreImageRenderer(device: nil)
    let report = renderer.encode(onePointFrame())
    #expect(report.drawCalls == nil)
}

@MainActor
@Test
func teardownIsIdempotentAndLeavesTheRendererInert() {
    let renderer = CoreImageRenderer()
    _ = renderer.encode(onePointFrame())
    renderer.teardown()
    renderer.teardown()
    let revisionAfterTeardown = renderer.encodedRevision

    let report = renderer.encode(onePointFrame())
    #expect(report.encodeNs == 0)
    #expect(report.pointsDrawn == nil)
    // Torn down or active, this backend never knows a draw-call count with no device — but here
    // it never even tries to draw, so `nil` is the only honest answer, same as an active frame on
    // a device-less host, and never a `0` this process cannot back.
    #expect(report.drawCalls == nil)
    #expect(renderer.encodedRevision == revisionAfterTeardown, "a torn-down renderer must not advance further")
}

@MainActor
@Test
func suspendAndResumeAreHarmlessWhenCalledRepeatedly() {
    let renderer = CoreImageRenderer()
    renderer.suspend()
    renderer.suspend()
    renderer.resume()
    renderer.resume()
    let report = renderer.encode(onePointFrame())
    #expect(report.encodeNs > 0)
}

/// `saturation` defaults to the neutral value the equivalence tests render at, so a renderer built
/// with no explicit choice reproduces `CoreGraphicsReference`'s own bytes rather than a tinted
/// picture nobody asked for.
@MainActor
@Test
func saturationDefaultsToNeutral() {
    let renderer = CoreImageRenderer()
    #expect(renderer.saturation == CoreImageRenderer.neutralSaturation)
}

/// The real defect behind B23: every existing fixture in this file uses a `plotRect` that already
/// matches `ComparisonImage`'s pinned size, so nothing here ever exercised what the live demo
/// actually sends — a `PreparedFrame` sized to the real, on-screen chart area, which on a phone is
/// nowhere near 1024×768 points.
@MainActor
@Test
func theRenderedImageMatchesTheFramesOwnSizeNotThePinnedComparisonSize() {
    // A plausible on-screen chart area, deliberately far from ComparisonImage's 1024×768.
    let plot = PlotRect(x: 52, y: 10, width: 320, height: 200)
    var frame = PreparedFrame(plotRect: plot)
    frame.series = [
        PreparedSeries(
            index: 0, colour: Palette.colour(forSeries: 0, dark: false),
            points: [PlottedPoint(x: 0, y: 0.5, isBreak: false), PlottedPoint(x: 1, y: 0.5, isBreak: false)]
        ),
    ]
    frame.chrome = ChromeLayout.build(plot: plot, xTicks: [], yTicks: [], chrome: .light, scale: 1)

    let renderer = CoreImageRenderer()
    _ = renderer.encode(frame)

    let expectedWidth = CGFloat(plot.maxX + FramePreparation.rightInset)
    let expectedHeight = CGFloat(plot.maxY + FramePreparation.bottomInset)
    let extent = renderer.image?.extent
    #expect(extent?.width == expectedWidth, "image is \(String(describing: extent)), the frame's own canvas is \(expectedWidth)x\(expectedHeight)")
    #expect(extent?.height == expectedHeight)
}
