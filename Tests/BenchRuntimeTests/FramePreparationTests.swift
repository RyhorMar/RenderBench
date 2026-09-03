import BenchCore
import BenchDownsampling
import BenchScales
import Foundation
import Testing
@testable import BenchRuntime

private struct FixedWidth: TextMeasuring {
    func width(of text: String) -> Double { Double(text.count) * 7.5 }
    var lineHeight: Double { 11 }
}

private func provider(_ values: [(carrier: Double, value: Double)]) -> ArrayProvider {
    ArrayProvider(
        [values.map { Sample(carrier: $0.carrier, value: $0.value) }],
        metadata: [SeriesMetadata(name: "s", unit: .fraction)]
    )
}

private func prepare(
    _ source: ArrayProvider,
    window: ClosedRange<Carrier> = 0...10,
    yDomain: ClosedRange<Double> = -1...1,
    policy: DownsamplePolicy = .none
) -> PreparedFrame {
    var scratch: [Sample] = []
    return FramePreparation.prepare(
        provider: source,
        spec: LineChartSpec(series: [0], policy: policy),
        window: window,
        yDomain: yDomain,
        size: (width: 1_024, height: 768),
        dark: false,
        measuring: FixedWidth(),
        scratch: &scratch
    )
}

/// The orientation of the projection, pinned. Every backend consumes these coordinates, so a flip
/// here flips every chart in the package at once — and no cross-backend comparison would notice,
/// because both sides would flip together. A mutation that inverted this passed the entire suite
/// before this test existed.
@Test
func theProjectionPutsTheDomainMinimumAtZeroAndTheMaximumAtOne() {
    let frame = prepare(
        provider([(0, -1), (5, 0), (10, 1)]),
        window: 0...10,
        yDomain: -1...1
    )
    let points = frame.series[0].points
    #expect(points.count == 3)

    // Carrier: window start is 0, window end is 1.
    #expect(abs(points[0].x - 0) < 1e-12)
    #expect(abs(points[1].x - 0.5) < 1e-12)
    #expect(abs(points[2].x - 1) < 1e-12)

    // Value: domain bottom is 0, domain top is 1. Backends subtract from the plot's bottom edge,
    // so an inverted projection here draws every chart upside down.
    #expect(abs(points[0].y - 0) < 1e-12)
    #expect(abs(points[1].y - 0.5) < 1e-12)
    #expect(abs(points[2].y - 1) < 1e-12)
}

@Test
func ticksAreProjectedByTheSameScaleAsTheSamples() {
    let frame = prepare(provider([(0, -1), (10, 1)]), yDomain: -1...1)
    for tick in frame.xTicks + frame.yTicks {
        #expect(tick.position >= 0)
        #expect(tick.position <= 1)
    }
    // A tick at the domain's midpoint sits at the plot's midpoint, not at the midpoint of the
    // ticks that happened to be chosen.
    if let middle = frame.yTicks.first(where: { $0.label == "0.0" }) {
        #expect(abs(middle.position - 0.5) < 1e-9)
    }
}

/// Gaps survive preparation as breaks, with no coordinates of their own: a backend that used the
/// x and y of a break would draw a line to the plot's corner.
@Test
func aGapBecomesABreakWithoutCoordinates() {
    let frame = prepare(provider([(0, -1), (2, .nan), (4, 1)]))
    let points = frame.series[0].points
    #expect(points.filter(\.isBreak).count == 1)
    let breakPoint = points.first { $0.isBreak }
    #expect(breakPoint?.x == 0)
    #expect(breakPoint?.y == 0)
}

@Test
func thePlotRectLeavesTheDocumentedInsets() {
    let frame = prepare(provider([(0, 0), (10, 1)]))
    #expect(frame.plotRect.minX == FramePreparation.leftInset)
    #expect(frame.plotRect.minY == FramePreparation.topInset)
    #expect(frame.plotRect.maxX == 1_024 - FramePreparation.rightInset)
    #expect(frame.plotRect.maxY == 768 - FramePreparation.bottomInset)
    #expect(frame.plotRect.isDrawable)
}

@Test
func aPlotTooSmallToDrawIsReportedRatherThanNegative() {
    var scratch: [Sample] = []
    let frame = FramePreparation.prepare(
        provider: provider([(0, 0), (10, 1)]),
        spec: LineChartSpec(series: [0]),
        window: 0...10,
        yDomain: -1...1,
        size: (width: 10, height: 10),
        dark: false,
        measuring: FixedWidth(),
        scratch: &scratch
    )
    #expect(frame.plotRect.isDrawable == false)
    #expect(frame.plotRect.width >= 0)
    #expect(frame.series.isEmpty)
}

@Test
func aRefusedSeriesIsReportedAndNotProjected() {
    let gravity = SeriesUnit(
        symbol: "°API", quantity: .dimensionless, scale: 1, offset: 0, isAveragable: false
    )
    let samples = (0..<500).map { Sample(carrier: Double($0) / 50, value: Double($0 % 30)) }
    let source = ArrayProvider([samples], metadata: [SeriesMetadata(name: "g", unit: gravity)])
    var scratch: [Sample] = []
    let frame = FramePreparation.prepare(
        provider: source,
        spec: LineChartSpec(series: [0], policy: .lttb),
        window: 0...10,
        yDomain: 0...30,
        size: (width: 1_024, height: 768),
        dark: false,
        measuring: FixedWidth(),
        scratch: &scratch
    )
    #expect(frame.failures.count == 1)
    #expect(frame.series.isEmpty)
    #expect(frame.pointsSubmitted == 0)
}
