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
