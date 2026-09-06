import BenchCore
import BenchRuntime
import BenchScales
import Foundation
import Metal
import Testing
@testable import SceneKitBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

// Copied verbatim from `Tests/MetalBackendTests/MetalRenderTargetTests.swift`. Test targets do
// not import each other in this project, by design — see that file for the rationale.
private func eightCurves() -> ArrayProvider {
    let rate = 1_000.0
    var series: [[Sample]] = []
    var metadata: [SeriesMetadata] = []
    for index in 0..<8 {
        let amplitude = 1.0 - Double(index) * 0.06
        let frequency = 0.25 + Double(index) * 0.02
        let phase = Double(index) * .pi / 5
        series.append((0..<10_000).map { step in
            let time = Double(step) / rate
            return Sample(carrier: time, value: amplitude * sin(2 * .pi * frequency * time + phase))
        })
        metadata.append(SeriesMetadata(name: "s\(index)", unit: .fraction))
    }
    return ArrayProvider(series, metadata: metadata)
}

private func prepared(_ spec: LineChartSpec, shiftedBy shift: Double = 0) -> PreparedFrame {
    var scratch: [Sample] = []
    var frame = FramePreparation.prepare(
        provider: eightCurves(),
        spec: spec,
        window: window,
        yDomain: yDomain,
        size: (width: Double(SceneKitRenderTarget.width), height: Double(SceneKitRenderTarget.height)),
        chrome: .forScheme(dark: false),
        scale: 1,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    if shift != 0 {
        frame.plotRect = PlotRect(
            x: frame.plotRect.x + shift,
            y: frame.plotRect.y,
            width: frame.plotRect.width,
            height: frame.plotRect.height
        )
    }
    return frame
}

private func eightCurvesPrepared() -> PreparedFrame { prepared(LineChartSpec(series: Array(0..<8))) }

/// BGR triples the palette renders as at full coverage.
private let solidSeriesColours: [(UInt8, UInt8, UInt8)] = (0..<8).map { index in
    let encoded = Palette.colour(forSeries: index, dark: false).encodedSRGB
    return (
        UInt8((encoded.blue * 255).rounded()),
        UInt8((encoded.green * 255).rounded()),
        UInt8((encoded.red * 255).rounded())
    )
}

/// The bounding box of pixels this project's own reference renders in one of the eight solid
/// series colours — a coarse-grained shape, not a per-pixel one, that a 1 px line and a 1.5 pt
/// stroke of the same data should still agree on: neither backend moves a series, only how wide
/// it paints it.
private func solidSeriesBoundingBox(_ pixels: [UInt8], width: Int, height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
    for y in 0..<height {
        for x in 0..<width {
            let byte = (y * width + x) * 4
            guard solidSeriesColours.contains(where: {
                pixels[byte] == $0.0 && pixels[byte + 1] == $0.1 && pixels[byte + 2] == $0.2
            }) else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return minX <= maxX ? (minX, minY, maxX, maxY) : nil
}

/// Absence of a GPU is a fact about the host, and every test below skips on it. This one makes
/// that visible: without it a machine with no Metal device would report a page of passes.
@Test
func thisHostHasAMetalDevice() {
    #expect(MTLCreateSystemDefaultDevice() != nil, "no Metal device: every render test below skipped")
}

/// The card's own acceptance criterion, and this backend's hypothesis stated in advance: a
/// `.line` primitive rasterises at exactly one device pixel regardless of the geometry's stated
/// width, so it cannot fill what this project's 1.5 pt reference stroke fills. `solidMismatches`
/// is expected to be large — the opposite of every backend before it — and that is the result,
/// not a defect to chase.
@Test
func drawsARecognisablyDifferentLineFromTheReference() throws {
    guard let target = SceneKitRenderTarget() else { return }
    let frame = eightCurvesPrepared()
    guard let reference = CoreGraphicsReference.render(frame) else { Issue.record("no reference"); return }
    let candidate = try target.render(frame)
    let d = StructuralDifference.between(
        reference: reference,
        candidate: candidate,
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(d.solidPixels > 5_000, "nothing was solid enough to compare")
    #expect(d.solidMismatches > 1_000, "a 1 px line cannot fill what a 1.5 pt stroke fills")
    // Observation, not a criterion — see Docs/methods/scenekit.md: the shape drawn is still
    // recognisably the same chart, just at the wrong width, so most pixels away from a stroke's
    // own edges still agree even though the certain-coverage criterion above does not.
    #expect(d.differingPixels < reference.count / 4 / 10, "but the shape is the same shape")
}

@Test
func aShiftedRenderIsRejected() throws {
    guard let target = SceneKitRenderTarget() else { return }
    var frame = eightCurvesPrepared()
    frame.plotRect = PlotRect(
        x: frame.plotRect.x + 1, y: frame.plotRect.y,
        width: frame.plotRect.width, height: frame.plotRect.height
    )
    guard let reference = CoreGraphicsReference.render(eightCurvesPrepared()) else {
        Issue.record("no reference")
        return
    }
    let candidate = try target.render(frame)
    let d = StructuralDifference.between(
        reference: reference,
        candidate: candidate,
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!d.agrees)
}

/// The one claim this backend's equivalence failure does not undermine: the camera and the
/// geometry it views place the chart in the right *place*, even though the line drawn there is
/// the wrong width. Checked on the bounding box of solid-coloured pixels rather than pixel for
/// pixel, since a narrower line legitimately shrinks that box by less than its own width — a
/// wrong camera or a flipped axis would instead move it by tens or hundreds of pixels.
@Test
func theSeriesBoundingBoxLandsWhereTheReferencePutsIt() throws {
    guard let target = SceneKitRenderTarget() else { return }
    let frame = eightCurvesPrepared()
    guard let reference = CoreGraphicsReference.render(frame) else { Issue.record("no reference"); return }
    let candidate = try target.render(frame)

    guard let referenceBox = solidSeriesBoundingBox(reference, width: ComparisonImage.width, height: ComparisonImage.height)
    else { Issue.record("reference drew no solid series pixels"); return }
    guard let candidateBox = solidSeriesBoundingBox(candidate, width: ComparisonImage.width, height: ComparisonImage.height)
    else { Issue.record("candidate drew no solid series pixels"); return }

    let tolerance = 10
    #expect(abs(candidateBox.minX - referenceBox.minX) <= tolerance)
    #expect(abs(candidateBox.maxX - referenceBox.maxX) <= tolerance)
    #expect(abs(candidateBox.minY - referenceBox.minY) <= tolerance)
    #expect(abs(candidateBox.maxY - referenceBox.maxY) <= tolerance)
}
