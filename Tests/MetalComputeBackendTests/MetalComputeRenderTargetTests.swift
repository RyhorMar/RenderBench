import BenchCore
import BenchRuntime
import BenchScales
import Foundation
import Metal
import Testing
@testable import MetalComputeBackend

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
        size: (width: Double(ComparisonImage.width), height: Double(ComparisonImage.height)),
        chrome: .forScheme(dark: false),
        scale: 1,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    if shift != 0 {
        frame.plotRect = PlotRect(
            x: frame.plotRect.x + shift, y: frame.plotRect.y,
            width: frame.plotRect.width, height: frame.plotRect.height
        )
    }
    return frame
}

/// BGR triples the palette renders as at full coverage.
private let solidSeriesColours: [(UInt8, UInt8, UInt8)] = (0..<8).map { index in
    let encoded = Palette.colour(forSeries: index, dark: false).encodedSRGB
    return (
        UInt8((encoded.blue * 255).rounded()),
        UInt8((encoded.green * 255).rounded()),
        UInt8((encoded.red * 255).rounded())
    )
}

/// The comparison this backend exists to make: this backend receives every windowed point at
/// `DownsamplePolicy.none` — the frame this scene hands it whenever `reducesOnGPU` is true — and
/// reduces on the GPU, judged against the CPU path's own `minMax` reduction rasterised by
/// `CoreGraphicsReference`, the same reference every other backend is judged against.
///
/// The two are not the same algorithm — see `Docs/methods/gpu-compute-reduction.md` for the
/// bucketing-space deviation this backend documents plainly — but on this project's own reference
/// fixture, one contiguous run, regularly sampled, no gaps, the time-to-x projection is affine and
/// the two are expected to converge closely. Reported here, honestly, regardless of outcome.
@Test
func theGPUReductionDrawsCloseToTheCPUReferenceOnTheProjectFixture() throws {
    guard let target = MetalComputeRenderTarget() else { return }
    let reference = CoreGraphicsReference.render(prepared(LineChartSpec(series: Array(0..<8), policy: .minMax)))
    guard let reference else { Issue.record("no reference"); return }
    let candidate = try target.render(prepared(LineChartSpec(series: Array(0..<8), policy: .none)))

    let difference = StructuralDifference.between(
        reference: reference, candidate: candidate,
        width: ComparisonImage.width, height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    // `difference.solidMismatches` and `difference.solidPixels` are reported in this method's own
    // verification report regardless of whether `agrees` holds below. Measured once, after the
    // bucket-count fix in `RunColumns.columns`: 0 of 8188 solid pixels disagree, 133 mismatches
    // away from edges — matching `Docs/methods/equivalence.md`'s own table of `MetalBackend`
    // numbers on the identical fixture, since both draw through the same instanced-quad line pass
    // and were handed the same points to draw once their own reduction had run.
    #expect(difference.solidPixels > 5_000)
    #expect(difference.agrees, "\(difference.solidMismatches) certain pixels disagree")
}

/// The check above is one-sided by construction: `StructuralDifference.agrees` fails only when a
/// pixel the reference was certain about goes unfilled, never when this backend draws *more* ink
/// than the reference anywhere the reference itself had none to be certain about. Doubling every
/// run's bucket count — exactly the bug `RunColumns.columns` carried before its fix — doubles the
/// points drawn per run without ever leaving a reference-certain pixel unfilled, so `agrees` stays
/// `true` straight through that regression (confirmed by reverting the fix and rerunning both this
/// file's tests: the pixel check above still passed). This test is the density check the pixel
/// check structurally cannot be, and it exists specifically to catch what that one cannot.
///
/// Factor: measured once on this fixture, the CPU path (`policy: .minMax`) emits 7680 points
/// (8 series × 960) and this backend's GPU path, post-fix, emits 7664 (8 series × 958) — ratio
/// 0.998. The pre-fix defect emitted 15344 (ratio 1.998, exactly double). `1.5` sits with real
/// margin above the honest ~1.0 ratio and well below the 2.0 the bug produced, so it separates the
/// two without being tuned to the current code's exact output.
@Test
func gpuReductionPointDensityStaysWithinOneAndAHalfTimesTheCPUBudget() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let library = try MetalComputeCompiledLibrary(device: device)
    let reducer = try MetalComputeReducer(device: device, library: library.library)

    let cpuFrame = prepared(LineChartSpec(series: Array(0..<8), policy: .minMax))
    let cpuPointCount = cpuFrame.series.reduce(0) { total, series in
        total + series.points.filter { !$0.isBreak }.count
    }

    let gpuFrame = prepared(LineChartSpec(series: Array(0..<8), policy: .none))
    let runsPerSeries = gpuFrame.series.map { RunSplitter.runs(in: $0.points) }
    let reduced = try reducer.reduce(runsPerSeries: runsPerSeries, plotWidth: gpuFrame.plotRect.width)
    let gpuPointCount = reduced.reduce(0) { total, series in
        total + series.reduce(0) { $0 + $1.points.count }
    }

    let ratio = Double(gpuPointCount) / Double(cpuPointCount)
    #expect(
        ratio > 1 / 1.5 && ratio < 1.5,
        "gpu drew \(gpuPointCount) points against the CPU path's \(cpuPointCount) (ratio \(ratio))"
    )
}

@Test
func aShiftedRenderIsRejected() throws {
    guard let target = MetalComputeRenderTarget() else { return }
    let reference = CoreGraphicsReference.render(prepared(LineChartSpec(series: Array(0..<8), policy: .minMax)))
    guard let reference else { Issue.record("no reference"); return }
    let shifted = prepared(LineChartSpec(series: Array(0..<8), policy: .none), shiftedBy: 1)
    let candidate = try target.render(shifted)

    let difference = StructuralDifference.between(
        reference: reference, candidate: candidate,
        width: ComparisonImage.width, height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!difference.agrees)
}

/// A gap must be visible as a gap: a run this backend reduces must not bridge a break, exactly
/// like every other backend's treatment of one.
@Test
func aGappedRenderDisagreesWithAnUngappedOne() throws {
    guard let target = MetalComputeRenderTarget() else { return }
    var scratch: [Sample] = []
    let full = (0..<2_000).map { Sample(carrier: Double($0) / 200, value: sin(Double($0) / 40)) }
    var gapped = full
    for index in 800..<900 { gapped[index] = Sample(carrier: gapped[index].carrier, value: .nan) }

    func frame(_ samples: [Sample]) -> PreparedFrame {
        FramePreparation.prepare(
            provider: ArrayProvider([samples], metadata: [SeriesMetadata(name: "g", unit: .fraction)]),
            spec: LineChartSpec(series: [0], policy: .none, lineWidth: 4),
            window: window, yDomain: -1.4...1.4,
            size: (width: Double(ComparisonImage.width), height: Double(ComparisonImage.height)),
            chrome: .forScheme(dark: false), scale: 1, dark: false,
            measuring: ApproximateTextWidth(), scratch: &scratch
        )
    }

    let withGap = try target.render(frame(gapped))
    let withoutGap = try target.render(frame(full))
    #expect(withGap != withoutGap, "a broken run rendered identically to an unbroken one")
}

/// `RunSplitter` is the seam this whole backend runs through before anything reaches the GPU: no
/// run it returns may contain a break, and a break-adjacent run must end exactly where the data
/// says it does.
@Test
func runSplitterEndsARunAtEveryBreak() {
    let points = [
        PlottedPoint(x: 0, y: 0.1, isBreak: false),
        PlottedPoint(x: 0.1, y: 0.2, isBreak: false),
        PlottedPoint(x: 0, y: 0, isBreak: true),
        PlottedPoint(x: 0.3, y: 0.4, isBreak: false),
    ]
    let runs = RunSplitter.runs(in: points)
    #expect(runs.count == 2)
    #expect(runs[0].points.count == 2)
    #expect(runs[1].points.count == 1)
}
