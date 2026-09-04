import BenchCore

/// One stroke of the chart's furniture, in points, already snapped to device pixels.
public struct ChromeLine: Sendable, Equatable {
    public let x0: Double, y0: Double, x1: Double, y1: Double
    public let colour: PaletteColor
    public let width: Double
}

public struct ChromeLabel: Sendable, Equatable {
    public enum Anchor: Sendable { case trailing, center }
    public let text: String
    public let x: Double
    public let y: Double
    public let anchor: Anchor
}

/// Everything a backend strokes that is not a series, decided once for all of them.
///
/// Until this existed each backend computed the grid for itself, three different ways, and a
/// change to the chrome was a change in seven files. A backend now receives lines and strokes
/// them; whether the grid sits on a pixel centre is no longer its decision to get wrong.
public struct ChromeLayout: Sendable, Equatable {
    public var background: PaletteColor
    public var labelColour: PaletteColor
    /// Grid first, then the two axes — draw order, so series drawn afterwards sit on top.
    public var lines: [ChromeLine]
    public var labels: [ChromeLabel]

    public static let empty = ChromeLayout(background: ChartChrome.light.background,
                                           labelColour: ChartChrome.light.label, lines: [], labels: [])

    public static func build(
        plot: PlotRect, xTicks: [PlottedTick], yTicks: [PlottedTick],
        chrome: ChartChrome, scale: Double
    ) -> ChromeLayout {
        var layout = ChromeLayout(background: chrome.background, labelColour: chrome.label, lines: [], labels: [])
        guard plot.isDrawable else { return layout }
        for tick in yTicks {
            let y = PixelSnap.centre(plot.maxY - tick.position * plot.height, width: chrome.gridWidth, scale: scale)
            layout.lines.append(ChromeLine(x0: plot.minX, y0: y, x1: plot.maxX, y1: y, colour: chrome.grid, width: chrome.gridWidth))
            layout.labels.append(ChromeLabel(text: tick.label, x: plot.minX - 6, y: y, anchor: .trailing))
        }
        let left = PixelSnap.centre(plot.minX, width: chrome.axisWidth, scale: scale)
        let bottom = PixelSnap.centre(plot.maxY, width: chrome.axisWidth, scale: scale)
        layout.lines.append(ChromeLine(x0: left, y0: plot.minY, x1: left, y1: bottom, colour: chrome.axis, width: chrome.axisWidth))
        layout.lines.append(ChromeLine(x0: left, y0: bottom, x1: plot.maxX, y1: bottom, colour: chrome.axis, width: chrome.axisWidth))
        for tick in xTicks {
            layout.labels.append(ChromeLabel(text: tick.label, x: plot.minX + tick.position * plot.width, y: plot.maxY + 10, anchor: .center))
        }
        return layout
    }
}
