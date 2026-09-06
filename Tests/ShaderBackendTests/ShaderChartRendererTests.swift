import BenchCore
import BenchRuntime
import Foundation
import Testing
@testable import ShaderBackend

@Test
func anUndrawablePlotProducesNoSeries() {
    let frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 0, height: 0))
    let encoded = ShaderChartRenderer.encode(frame)
    #expect(encoded.series.isEmpty)
    #expect(encoded.pointsDrawn == 0)
}

/// `pointsDrawn` counts real samples, not runs: a break costs the run it starts but not the point
/// count this backend reports, the same definition every other backend's `pointsDrawn` uses.
@Test
func pointsDrawnCountsEveryNonBreakPointAcrossEverySeries() {
    var frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 100, height: 100))
    frame.series = [
        PreparedSeries(index: 0, colour: Palette.colour(forSeries: 0, dark: false), points: [
            PlottedPoint(x: 0.0, y: 0.1, isBreak: false),
            PlottedPoint(x: 0.1, y: 0.2, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.3, y: 0.4, isBreak: false),
        ]),
    ]
    frame.pointsSubmitted = frame.series[0].points.count

    let encoded = ShaderChartRenderer.encode(frame)
    #expect(encoded.pointsDrawn == 3)
    #expect(encoded.series[0].runs.count == 1, "the lone point after the break has no segment to pack")
}

@Test
func everySeriesCarriesItsOwnColourAndIndex() {
    var frame = PreparedFrame(plotRect: PlotRect(x: 0, y: 0, width: 100, height: 100))
    let colour = Palette.colour(forSeries: 3, dark: false)
    frame.series = [
        PreparedSeries(index: 3, colour: colour, points: [
            PlottedPoint(x: 0, y: 0, isBreak: false),
            PlottedPoint(x: 1, y: 1, isBreak: false),
        ]),
    ]
    let encoded = ShaderChartRenderer.encode(frame)
    #expect(encoded.series[0].colour == colour)
    #expect(encoded.series[0].index == 3)
}

@Test
func encodedFrameCarriesChromeAndLineWidthThrough() {
    var frame = PreparedFrame(plotRect: PlotRect(x: 5, y: 6, width: 100, height: 100))
    frame.lineWidth = 4
    frame.chrome = ChromeLayout.build(plot: frame.plotRect, xTicks: [], yTicks: [], chrome: .light, scale: 1)
    let encoded = ShaderChartRenderer.encode(frame)
    #expect(encoded.lineWidth == 4)
    #expect(encoded.chrome == frame.chrome)
}
