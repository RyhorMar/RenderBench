import BenchCore
import BenchDownsampling
import BenchRuntime
import BenchScales
import BenchTestSupport
import Foundation
import Testing
@testable import CanvasBackend

private let size = CGSize(width: 400, height: 300)
private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

private func provider(
    unit: SeriesUnit = .fraction,
    seriesCount: Int = 1
) -> ArrayProvider {
    let samples = (0..<1_000).map { index in
        Sample(carrier: Double(index) / 100, value: sin(Double(index) * 0.05))
    }
    return ArrayProvider(
        Array(repeating: samples, count: seriesCount),
        metadata: Array(repeating: SeriesMetadata(name: "s", unit: unit), count: seriesCount)
    )
}

private func build(
    _ source: ArrayProvider,
    policy: DownsamplePolicy = .minMax,
    lineWidth: Double = 1.5,
    seriesCount: Int = 1
) -> CanvasFrame {
    var scratch: [Sample] = []
    return CanvasChartRenderer.buildFrame(
        provider: source,
        spec: LineChartSpec(
            series: Array(0..<seriesCount),
            policy: policy,
            lineWidth: lineWidth
        ),
        window: window,
        yDomain: yDomain,
        size: size,
        dark: false,
        measuring: FixedMetrics(),
        scratch: &scratch
    )
}

/// The defect this whole module shipped with: labels were positioned by the view against the span
/// of the ticks, while the samples were positioned by the scale against the domain. On this very
/// data that put the "1.0" label 14% of the plot height away from where 1.0 is drawn.
@Test
func tickPositionsAgreeWithTheScaleThatPlacedTheData() {
    let frame = build(provider())
    let yScale = LinearScale(domain: yDomain)
    let ticks = yScale.ticks(
        target: LineChartSpec(series: [0]).tickTarget,
        axisLength: Double(frame.plotRect.height),
        orientation: .vertical,
        measuring: FixedMetrics()
    )

    #expect(frame.yTicks.count == ticks.count)
    for (plotted, tick) in zip(frame.yTicks, ticks) {
        #expect(abs(plotted.position - yScale.map(tick.value).normalised) < 1e-12)
        #expect(plotted.label == tick.label)
    }
    // And the projection is not the identity over the tick span, which is what the bug computed.
    if let first = frame.yTicks.first {
        #expect(first.position > 0.0001)
    }
}

@Test
func everyTickPositionIsInsideTheUnitInterval() {
    let frame = build(provider())
    for tick in frame.xTicks + frame.yTicks {
        #expect(tick.position >= 0)
        #expect(tick.position <= 1)
    }
}

/// The spec field the view used to ignore in favour of a hardcoded 1.5.
@Test
func strokeWidthComesFromTheSpec() {
    #expect(build(provider(), lineWidth: 0.75).lineWidth == 0.75)
    #expect(build(provider(), lineWidth: 4).lineWidth == 4)
}

/// A refused series must be visible in the frame. Absorbing the error drew a chart with the
/// series simply missing while `pointsDrawn == pointsSubmitted` still read clean.
@Test
func aRefusedSeriesIsReportedRatherThanSilentlyBlank() {
    let gravity = SeriesUnit(
        symbol: "°API",
        quantity: .dimensionless,
        scale: 1,
        offset: 0,
        isAveragable: false
    )
    let frame = build(provider(unit: gravity), policy: .lttb)

    #expect(frame.failures.count == 1)
    #expect(frame.failures.first?.seriesIndex == 0)
    #expect(frame.failures.first?.error == .nonAveragable(unit: gravity))
    #expect(frame.strokes.isEmpty)

    // MinMax computes nothing, so the same series draws normally under it.
    let allowed = build(provider(unit: gravity), policy: .minMax)
    #expect(allowed.failures.isEmpty)
    #expect(allowed.strokes.count == 1)
}

@Test
func plotRectLeavesRoomForLabelsOnTwoSides() {
    let frame = build(provider())
    #expect(frame.plotRect.minX == CanvasChartRenderer.leftInset)
    #expect(frame.plotRect.minY == CanvasChartRenderer.topInset)
    #expect(frame.plotRect.maxX == size.width - CanvasChartRenderer.rightInset)
    #expect(frame.plotRect.maxY == size.height - CanvasChartRenderer.bottomInset)
}

@Test
func aChartTooSmallToDrawReturnsAnEmptyFrameRatherThanNegativeGeometry() {
    var scratch: [Sample] = []
    let frame = CanvasChartRenderer.buildFrame(
        provider: provider(),
        spec: LineChartSpec(series: [0]),
        window: window,
        yDomain: yDomain,
        size: CGSize(width: 10, height: 10),
        dark: false,
        measuring: FixedMetrics(),
        scratch: &scratch
    )
    #expect(frame.strokes.isEmpty)
    #expect(frame.plotRect.width >= 0)
    #expect(frame.plotRect.height >= 0)
}

@Test
func drawnPointsNeverExceedSubmittedOnes() {
    let frame = build(provider(seriesCount: 4), seriesCount: 4)
    #expect(frame.strokes.count == 4)
    #expect(frame.pointsDrawn <= frame.pointsSubmitted)
    #expect(frame.pointsDrawn > 0)
}

@Test
func bothTimingsAreRecorded() {
    let frame = build(provider(seriesCount: 3), seriesCount: 3)
    #expect(frame.prepareNs > 0)
    #expect(frame.encodeNs > 0)
}
