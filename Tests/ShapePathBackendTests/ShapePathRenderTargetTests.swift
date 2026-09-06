import BenchCore
import BenchRuntime
import BenchScales
import Foundation
import Testing
@testable import ShapePathBackend

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
        size: (width: Double(ShapePathRenderTarget.width), height: Double(ShapePathRenderTarget.height)),
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

@MainActor
@Test
func drawsTheSameChartAsTheReference() throws {
    let frame = eightCurvesPrepared()
    guard let reference = CoreGraphicsReference.render(frame) else { Issue.record("no reference"); return }
    guard let candidate = ShapePathRenderTarget.render(frame) else { Issue.record("no candidate"); return }
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

@MainActor
@Test
func aShiftedRenderIsRejected() throws {
    let shifted = prepared(LineChartSpec(series: Array(0..<8)), shiftedBy: 1)
    guard let reference = CoreGraphicsReference.render(eightCurvesPrepared()) else {
        Issue.record("no reference")
        return
    }
    guard let candidate = ShapePathRenderTarget.render(shifted) else { Issue.record("no candidate"); return }
    let d = StructuralDifference.between(
        reference: reference,
        candidate: candidate,
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!d.agrees)
}

/// The card's own acceptance criterion: what this backend hands to its `PolylineShape`s accounts
/// for every point `FramePreparation` submitted, on a fixture with no breaks to subtract.
@MainActor
@Test
func pointsDrawnMatchesPointsSubmitted() {
    let renderer = ShapePathRenderer()
    let frame = eightCurvesPrepared()
    let report = renderer.encode(frame)
    #expect(report.pointsDrawn == frame.pointsSubmitted)
}

/// A gap must be visible as a gap: the render with the break must disagree with a render of the
/// same series without one, away from the corner they otherwise share.
@MainActor
@Test
func aGappedRenderDisagreesWithAnUngappedOne() throws {
    var scratch: [Sample] = []
    let full = (0..<2_000).map { Sample(carrier: Double($0) / 200, value: sin(Double($0) / 40)) }
    var gapped = full
    for index in 800..<900 { gapped[index] = Sample(carrier: gapped[index].carrier, value: .nan) }

    func frame(_ samples: [Sample]) -> PreparedFrame {
        FramePreparation.prepare(
            provider: ArrayProvider([samples], metadata: [SeriesMetadata(name: "g", unit: .fraction)]),
            spec: LineChartSpec(series: [0], policy: .minMax, lineWidth: 4),
            window: window,
            yDomain: -1.4...1.4,
            size: (width: Double(ShapePathRenderTarget.width), height: Double(ShapePathRenderTarget.height)),
            chrome: .forScheme(dark: false),
            scale: 1,
            dark: false,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
    }

    guard let withGap = ShapePathRenderTarget.render(frame(gapped)) else { Issue.record("no render"); return }
    guard let withoutGap = ShapePathRenderTarget.render(frame(full)) else { Issue.record("no render"); return }
    #expect(withGap != withoutGap, "a broken run rendered identically to an unbroken one")
}
