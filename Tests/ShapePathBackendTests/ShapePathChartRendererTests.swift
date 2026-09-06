import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import Foundation
import Testing
@testable import ShapePathBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4
private let size = (width: 1_024.0, height: 768.0)

@Test
func anUndrawablePlotProducesNoSeries() {
    let frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 0, height: 0))
    let encoded = ShapePathChartRenderer.encode(frame)
    #expect(encoded.series.isEmpty)
    #expect(encoded.pointsDrawn == 0)
}

/// Without this, a mutation that stopped recording breaks would still pass every other test in
/// this target: nothing else here has a gap in it to detect.
@Test
func aBreakIsRecordedAsAnIndexRatherThanBecomingAPoint() {
    var values = (0..<2_000).map { Sample(carrier: Double($0) / 200, value: sin(Double($0) / 40)) }
    for index in 800..<900 { values[index] = Sample(carrier: values[index].carrier, value: .nan) }
    let provider = ArrayProvider([values], metadata: [SeriesMetadata(name: "g", unit: .fraction)])

    var scratch: [Sample] = []
    let frame = FramePreparation.prepare(
        provider: provider,
        spec: LineChartSpec(series: [0], policy: .minMax),
        window: window,
        yDomain: yDomain,
        size: size,
        chrome: .forScheme(dark: false),
        scale: 1,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    let breaks = frame.series[0].points.filter(\.isBreak).count
    #expect(breaks > 0)

    let encoded = ShapePathChartRenderer.encode(frame)
    let series = encoded.series[0]

    // A break is not geometry: it must not become one of the series' points.
    #expect(series.points.count == frame.pointsSubmitted - breaks)
    #expect(encoded.pointsDrawn == frame.pointsSubmitted - breaks)

    // And it must be recorded so the point after it starts a fresh subpath rather than being
    // connected to whatever came before the gap.
    #expect(!series.breaks.isEmpty)
    for breakIndex in series.breaks {
        #expect(breakIndex > 0 && breakIndex < series.points.count)
    }
}

/// Bounds alone do not pin down which index is recorded: an off-by-one that records one point too
/// early or too late still satisfies `0 < breakIndex < points.count` above, and still produces
/// *some* pixel difference from an ungapped render, since a gap drawn one point short or one point
/// long is still visibly different from no gap at all. This fixture is built directly rather than
/// run through `FramePreparation`'s downsampling, so the count of non-break points ahead of each
/// gap is known exactly, and the recorded index can be checked against that exact count rather
/// than merely a range.
@Test
func theBreakIndexIsExactlyTheCountOfNonBreakPointsBeforeIt() {
    var frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 100, height: 100))
    let colour = Palette.colour(forSeries: 0, dark: false)
    frame.series = [
        PreparedSeries(index: 0, colour: colour, points: [
            PlottedPoint(x: 0.0, y: 0.1, isBreak: false),
            PlottedPoint(x: 0.1, y: 0.2, isBreak: false),
            PlottedPoint(x: 0.2, y: 0.3, isBreak: false),
            PlottedPoint(x: 0.3, y: 0.4, isBreak: false),
            PlottedPoint(x: 0.4, y: 0.5, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.6, y: 0.6, isBreak: false),
            PlottedPoint(x: 0.7, y: 0.7, isBreak: false),
            PlottedPoint(x: 0.8, y: 0.8, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 1.0, y: 0.9, isBreak: false),
            PlottedPoint(x: 1.1, y: 1.0, isBreak: false),
        ]),
    ]
    frame.pointsSubmitted = frame.series[0].points.count

    let encoded = ShapePathChartRenderer.encode(frame)
    let series = encoded.series[0]

    // A break is not geometry: it must not become one of the series' points.
    #expect(series.points.count == 10)
    #expect(encoded.pointsDrawn == 10)

    // 5 real points precede the first gap; 3 more (indices 5, 6, 7) precede the second — the
    // exact position, not merely a value inside 0..<points.count.
    #expect(series.breaks == Set([5, 8]))
}

@Test
func everySeriesCarriesItsOwnColourAndIndex() {
    var scratch: [Sample] = []
    let samples = (0..<200).map { Sample(carrier: Double($0) / 20, value: sin(Double($0) / 10)) }
    let provider = ArrayProvider([samples], metadata: [SeriesMetadata(name: "s", unit: .fraction)])
    let frame = FramePreparation.prepare(
        provider: provider,
        spec: LineChartSpec(series: [0], policy: .minMax),
        window: window,
        yDomain: yDomain,
        size: size,
        chrome: .forScheme(dark: false),
        scale: 1,
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    let encoded = ShapePathChartRenderer.encode(frame)
    let expected = Palette.colour(forSeries: 0, dark: false)
    #expect(encoded.series[0].colour == expected)
    #expect(encoded.series[0].index == 0)
}
