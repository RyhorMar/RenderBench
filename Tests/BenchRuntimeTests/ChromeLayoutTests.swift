import BenchCore
import BenchRuntime
import Testing

private let plot = PlotRect(x: 52, y: 10, width: 960, height: 736)

@Test
func gridLinesArePixelSnappedAndSpanThePlot() {
    let layout = ChromeLayout.build(
        plot: plot,
        xTicks: [],
        yTicks: [PlottedTick(position: 0.5, label: "0")],
        chrome: .light,
        scale: 2
    )
    // One grid line, two axis lines.
    #expect(layout.lines.count == 3)
    let grid = layout.lines[0]
    #expect(grid.x0 == plot.minX && grid.x1 == plot.maxX)
    // Centre of the plot is y = 378; a 0.5 pt line at 2x is one device pixel, so it must sit on
    // a pixel centre: 378.25 in points.
    #expect(grid.y0 == 378.25 && grid.y1 == 378.25)
    #expect(grid.width == ChartChrome.light.gridWidth)
    #expect(grid.colour == ChartChrome.light.grid)
}

@Test
func axesAreTheLastTwoLinesAndLabelsCarryAnchors() {
    let layout = ChromeLayout.build(
        plot: plot,
        xTicks: [PlottedTick(position: 0, label: "0 s")],
        yTicks: [PlottedTick(position: 1, label: "1.4")],
        chrome: .light,
        scale: 1
    )
    let axes = layout.lines.suffix(2)
    #expect(axes.allSatisfy { $0.colour == ChartChrome.light.axis })
    #expect(layout.labels.count == 2)
    #expect(layout.labels.first { $0.text == "1.4" }?.anchor == .trailing)
    #expect(layout.labels.first { $0.text == "0 s" }?.anchor == .center)
}
