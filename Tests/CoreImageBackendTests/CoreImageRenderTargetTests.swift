import BenchCore
import BenchRuntime
import BenchScales
import Foundation
import Metal
import Testing
@testable import CoreImageBackend

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
        size: (width: Double(CoreImageRenderTarget.width), height: Double(CoreImageRenderTarget.height)),
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

/// Absence of a GPU is a fact about the host, and every test below skips on it. This one makes
/// that visible: without it a machine with no Metal device would report a page of passes.
@Test
func thisHostHasAMetalDevice() {
    #expect(MTLCreateSystemDefaultDevice() != nil, "no Metal device: every render test below skipped")
}

/// The card's own acceptance criterion: at the neutral `CIColorControls` parameters every
/// equivalence test in this backend renders at, the raster delivered through Core Image must be
/// the same chart `CoreGraphicsReference` draws.
@Test
func drawsTheSameChartAsTheReference() throws {
    guard let target = CoreImageRenderTarget() else { return }
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
    #expect(d.solidPixels > 5_000)
    #expect(d.agrees, "\(d.solidMismatches) certain pixels disagree")
}

@Test
func aShiftedRenderIsRejected() throws {
    guard let target = CoreImageRenderTarget() else { return }
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

/// `saturation` is a real parameter of the pipeline, not a value nothing reads: the categorical
/// series colours the demo's `filterEnabled` mode would push to `1.6` are not grey, so the render
/// must come out byte-different from the neutral one.
@Test
func aVisiblySaturatedRenderDiffersFromTheNeutralOne() throws {
    guard let target = CoreImageRenderTarget() else { return }
    let frame = eightCurvesPrepared()
    let neutral = try target.render(frame)
    let saturated = try target.render(frame, saturation: 1.6)
    #expect(neutral != saturated)
}
