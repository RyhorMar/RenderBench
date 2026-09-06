import BenchCore
import BenchRuntime
import Foundation
import Testing
import simd
@testable import MetalBackend

private let plot = PlotRect(x: 100, y: 50, width: 800, height: 400)

private func series(_ points: [(Double, Double, Bool)]) -> PreparedSeries {
    PreparedSeries(
        index: 0,
        colour: Palette.colour(forSeries: 0, dark: false),
        points: points.map { PlottedPoint(x: $0.0, y: $0.1, isBreak: $0.2) }
    )
}

@Test
func aPolylineOfNPointsBecomesNMinusOneSegments() {
    let geometry = MetalGeometryBuilder.build(
        series: series((0..<10).map { (Double($0) / 9, 0.5, false) }),
        plot: plot,
        scale: 1
    )
    #expect(geometry.points.count == 10)
    #expect(geometry.segmentStarts.count == 9)
    #expect(geometry.segmentStarts == Array(0..<9).map(UInt32.init))
}

/// The invariant a break exists to enforce: no drawn segment may span one.
///
/// A backend that ignores breaks draws a straight line across a gap in the data, which is a claim
/// about measurements that were never taken. The other backends enforce it by starting a new
/// subpath; here there are no subpaths, only the index list, so this is where it lives.
@Test
func noSegmentSpansABreak() {
    let geometry = MetalGeometryBuilder.build(
        series: series([
            (0.0, 0.1, false), (0.1, 0.2, false),
            (0.0, 0.0, true),
            (0.3, 0.4, false), (0.4, 0.5, false), (0.5, 0.6, false),
        ]),
        plot: plot,
        scale: 1
    )
    // Five real points; the break contributes none.
    #expect(geometry.points.count == 5)
    // One segment in the first run, two in the second. The pair (1, 2) would be the gap.
    #expect(geometry.segmentStarts == [0, 2, 3])
}

@Test
func aRunOfOnePointDrawsNothing() {
    let geometry = MetalGeometryBuilder.build(
        series: series([(0.0, 0.1, false), (0.0, 0.0, true), (0.5, 0.5, false)]),
        plot: plot,
        scale: 1
    )
    #expect(geometry.points.count == 2)
    #expect(geometry.segmentStarts.isEmpty)
}

@Test
func normalisedPointsLandInPixelSpaceWithTheOriginAtTheTopLeft() {
    let geometry = MetalGeometryBuilder.build(
        series: series([(0, 0, false), (1, 1, false)]),
        plot: plot,
        scale: 2
    )
    // y is measured up from the domain's bottom and down from the top of the bitmap.
    #expect(geometry.points[0] == SIMD2<Float>(200, 900))
    #expect(geometry.points[1] == SIMD2<Float>(1800, 100))
}

@Test
func batchesIndexIntoOneSharedBuffer() {
    var frame = PreparedFrame(plotRect: plot)
    frame.series = [
        series([(0, 0, false), (0.5, 0.5, false)]),
        PreparedSeries(
            index: 1,
            colour: Palette.colour(forSeries: 1, dark: false),
            points: [PlottedPoint(x: 0, y: 1, isBreak: false), PlottedPoint(x: 1, y: 0, isBreak: false)]
        ),
    ]
    frame.yTicks = [PlottedTick(position: 0.5, label: "0")]
    frame.chrome = ChromeLayout.build(plot: plot, xTicks: [], yTicks: frame.yTicks, chrome: .light, scale: 1)

    let geometry = MetalChartGeometry.build(frame, scale: 1)
    // Grid, axes, and one batch per series.
    #expect(geometry.batches.count == 4)
    // Every segment index must address the shared point buffer, not its own slice.
    for batch in geometry.batches {
        for index in batch.segmentRange {
            #expect(Int(geometry.segmentStarts[index]) + 1 < geometry.points.count)
        }
    }
    #expect(geometry.vertexCount == geometry.segmentStarts.count * 6)
}

/// A silent mismatch here reads whatever follows the struct as a colour, and produces a plausible
/// chart in the wrong hue — the failure mode this project has already shipped once.
@Test
func uniformsMatchTheLayoutTheShaderDeclares() {
    #expect(MemoryLayout<ChartUniforms>.stride == 32)
    #expect(MemoryLayout<ChartUniforms>.alignment == 16)
}

/// Two breaks in a row, and a break before any data. Both leave a run of no points at all, and the
/// segment loop would build an invalid range from one — the guard against it was load-bearing and
/// nothing exercised it until this test existed.
@Test
func adjacentAndLeadingBreaksProduceNoSegments() {
    let geometry = MetalGeometryBuilder.build(
        series: series([
            (0.0, 0.0, true),
            (0.0, 0.0, true),
            (0.2, 0.3, false),
            (0.0, 0.0, true),
            (0.0, 0.0, true),
            (0.6, 0.7, false),
            (0.7, 0.8, false),
        ]),
        plot: plot,
        scale: 1
    )
    #expect(geometry.points.count == 3)
    #expect(geometry.segmentStarts == [1])
}

/// Every point a break: nothing to draw, and nothing to trap on either.
@Test
func aSeriesOfNothingButBreaksDrawsNothing() {
    let geometry = MetalGeometryBuilder.build(
        series: series([(0, 0, true), (0, 0, true), (0, 0, true)]),
        plot: plot,
        scale: 1
    )
    #expect(geometry.points.isEmpty)
    #expect(geometry.segmentStarts.isEmpty)
}
