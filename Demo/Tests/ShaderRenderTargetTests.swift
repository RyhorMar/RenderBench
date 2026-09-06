import BenchCore
import BenchRuntime
import Foundation
import ShaderBackend
import Testing

// This file's whole reason to live in `Demo/Tests` rather than in
// `Tests/ShaderBackendTests`: `ShaderRenderTarget.render(_:)` calls into `ShaderChartView`, which
// composites `Rectangle().colorEffect(ShaderLibrary.default.chart_line(...))`. `ShaderLibrary`
// resolves that function from the *running process's* main bundle, and only this test bundle's
// host app — `RenderBenchDemo`, built by Xcode from `Demo/Sources/Shaders/ChartLine.metal` — has
// ever compiled it in. Under `swift test`, no bundle on the machine has, so the same call would
// silently composite nothing rather than fail loudly, and a test written there would be measuring
// whether `ImageRenderer` can produce an image at all, not whether the shader draws a chart.

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

// Copied verbatim from `Tests/MetalBackendTests/MetalRenderTargetTests.swift`. Test targets do
// not import each other in this project, by design — see that file for the rationale. This is
// the one demo-side exception to "test targets copy the fixture rather than importing another
// test target": `Demo/Tests` cannot import a package test target at all, so it copies the same
// fixture a package-level render-target test would.
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
        size: (width: Double(ShaderRenderTarget.width), height: Double(ShaderRenderTarget.height)),
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

/// The one place in this whole project the fragment shader actually runs. Everything upstream of
/// this call — packing, run-splitting, the descriptor — was already checked without a compiled
/// shader in `Tests/ShaderBackendTests`; only this line's outcome depends on
/// `Demo/Sources/Shaders/ChartLine.metal` having built into this bundle's host app.
@MainActor
@Test
func drawsTheSameChartAsTheReference() throws {
    let frame = eightCurvesPrepared()
    guard let reference = CoreGraphicsReference.render(frame) else { Issue.record("no reference"); return }
    guard let candidate = ShaderRenderTarget.render(frame) else { Issue.record("no candidate"); return }
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
    guard let candidate = ShaderRenderTarget.render(shifted) else { Issue.record("no candidate"); return }
    let d = StructuralDifference.between(
        reference: reference,
        candidate: candidate,
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!d.agrees)
}

/// A gap must be visible as a gap: the render with the break must disagree with a render of the
/// same series without one, checked here rather than only at the buffer level in
/// `Tests/ShaderBackendTests`, since only this bundle can turn the packed runs into actual pixels.
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
            size: (width: Double(ShaderRenderTarget.width), height: Double(ShaderRenderTarget.height)),
            chrome: .forScheme(dark: false),
            scale: 1,
            dark: false,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
    }

    guard let withGap = ShaderRenderTarget.render(frame(gapped)) else { Issue.record("no render"); return }
    guard let withoutGap = ShaderRenderTarget.render(frame(full)) else { Issue.record("no render"); return }
    #expect(withGap != withoutGap, "a broken run rendered identically to an unbroken one")
}
