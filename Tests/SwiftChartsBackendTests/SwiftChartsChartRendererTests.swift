import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import Foundation
import Testing
@testable import SwiftChartsBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4
private let size = (width: 1_024.0, height: 768.0)

@Test
func anUndrawablePlotProducesNoMarks() {
    let frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 0, height: 0))
    let encoded = SwiftChartsChartRenderer.encode(frame)
    #expect(encoded.marks.isEmpty)
    #expect(encoded.pointsDrawn == 0)
}

/// Without this, a mutation that stopped splitting a series at its breaks would still pass every
/// other test in this target: nothing else here has a gap in it to draw through.
@Test
func aBreakEndsARunRatherThanBeingConnectedAcrossIt() {
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

    let encoded = SwiftChartsChartRenderer.encode(frame)

    // A break is not geometry: it must end a run rather than becoming one of its marks.
    #expect(encoded.pointsDrawn == frame.pointsSubmitted - breaks)

    // And it must start a new run: every mark before the gap and every mark after it share a
    // series index but must not share a run key, or `Chart` draws a line through the hole. The
    // gap sits at carrier 4.0...4.495 inside a 0...10 window, i.e. normalised x 0.40...0.4495.
    let keysBeforeTheGap = Set(encoded.marks.filter { $0.x < 0.35 }.map(\.seriesKey))
    let keysAfterTheGap = Set(encoded.marks.filter { $0.x > 0.5 }.map(\.seriesKey))
    #expect(!keysBeforeTheGap.isEmpty)
    #expect(!keysAfterTheGap.isEmpty)
    #expect(keysBeforeTheGap.isDisjoint(with: keysAfterTheGap), "the gap did not start a new run")
}

@Test
func everyMarkCarriesItsSeriesColour() {
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
    let encoded = SwiftChartsChartRenderer.encode(frame)
    let expected = Palette.colour(forSeries: 0, dark: false)
    #expect(encoded.marks.allSatisfy { $0.colour == expected })
}
