import BenchCore
import BenchRuntime
import BenchScales
import Foundation
import Testing
@testable import SwiftChartsBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

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
        size: (width: Double(SwiftChartsRenderTarget.width), height: Double(SwiftChartsRenderTarget.height)),
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
    guard let candidate = SwiftChartsRenderTarget.render(frame) else { Issue.record("no candidate"); return }
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
    guard let candidate = SwiftChartsRenderTarget.render(shifted) else { Issue.record("no candidate"); return }
    let d = StructuralDifference.between(
        reference: reference,
        candidate: candidate,
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!d.agrees)
}

/// The card's own acceptance criterion: what this backend hands to `Chart` accounts for every
/// point `FramePreparation` submitted, on a fixture with no breaks to subtract.
@MainActor
@Test
func pointsDrawnMatchesPointsSubmitted() {
    let renderer = SwiftChartsRenderer()
    let frame = eightCurvesPrepared()
    let report = renderer.encode(frame)
    #expect(report.pointsDrawn == frame.pointsSubmitted)
}

/// Two renders of the same frame must not depend on anything this package controls — but not
/// quite bit-identical, unlike every backend that rasterises through code this package owns.
///
/// Measured by running forty renders of one unchanged frame back to back, under concurrent
/// background load, to separate a real rendering difference from noise: one pair disagreed, at up
/// to 3 864 of 3 145 728 bytes, every one of them by exactly 1 of 255. That is `Chart`'s own
/// render server settling internal state — text or layout caching this package cannot see or
/// control — not this backend redrawing anything differently. A tolerance of 1 is this
/// observation, not the project's general rounding tolerance of 8 used against the Core Graphics
/// reference elsewhere in this file, which asks a different question.
///
/// The max-delta check alone cannot tell that story from a deterministic rounding regression: a
/// bug that shifted one channel by exactly 1 on every pixel would also have `worst == 1` and pass
/// forever. So this also counts *how many* bytes differ, not only the worst one. Re-running this
/// render pair locally (20 and 60 back-to-back renders, with and without concurrent background
/// load) always reproduced the same shape: 0 differing bytes on almost every pair, and exactly
/// 3 864 on the render server's first-to-second warm-up transition — never anything in between and
/// never more. `8 000` gives that observation better than 2x headroom while still rejecting a
/// systematic bug: a rounding error touching even one whole colour channel across the frame would
/// disagree on up to 786 432 bytes (1024 × 768, a quarter of the buffer), two orders of magnitude
/// past this bound. Jitter is small and sparse; a systematic bug is large and uniform — this is the
/// line between them.
@MainActor
@Test
func twoRendersOfTheSameFrameAgreeToWithinOneLevel() throws {
    let frame = eightCurvesPrepared()
    guard let first = SwiftChartsRenderTarget.render(frame) else { Issue.record("no render"); return }
    guard let second = SwiftChartsRenderTarget.render(frame) else { Issue.record("no render"); return }
    #expect(first.count == ComparisonImage.byteCount(scale: 1))
    #expect(first.count == second.count)
    var worst = 0
    var differing = 0
    for (a, b) in zip(first, second) {
        let delta = abs(Int(a) - Int(b))
        if delta != 0 { differing += 1 }
        worst = max(worst, delta)
    }
    #expect(worst <= 1, "renders of one frame disagreed by up to \(worst) of 255")
    #expect(differing <= 8_000, "\(differing) of \(first.count) bytes disagreed — too many to be render-server jitter")
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
            size: (width: Double(SwiftChartsRenderTarget.width), height: Double(SwiftChartsRenderTarget.height)),
            chrome: .forScheme(dark: false),
            scale: 1,
            dark: false,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
    }

    guard let withGap = SwiftChartsRenderTarget.render(frame(gapped)) else { Issue.record("no render"); return }
    guard let withoutGap = SwiftChartsRenderTarget.render(frame(full)) else { Issue.record("no render"); return }
    #expect(withGap != withoutGap, "a broken run rendered identically to an unbroken one")
}
