import BenchCore
import BenchRuntime
import Charts
import SwiftUI

/// Draws a prepared frame through SwiftUI's `Chart`, with this project's own chrome underneath.
///
/// `Chart`'s own axes and grid are hidden (`chartXAxis(.hidden)`, `chartYAxis(.hidden)`) rather
/// than styled to match: styling them would still leave two independently laid-out grids racing
/// to agree pixel-for-pixel, and the comparison this project makes is about the series, not about
/// whose axis styling looks nicer. Turning them back on is a property a demo could add; it is not
/// part of what this backend measures.
public struct SwiftChartsChartView: View {
    private let frame: SwiftChartsFrame

    public init(frame: SwiftChartsFrame) {
        self.frame = frame
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                    drawChrome(in: &context, size: size)
                }
                chart(in: geometry.size)
            }
        }
    }

    /// The plot, padded to `frame.plotRect` exactly — the same inset every other backend draws
    /// inside, so this backend's own layout engine positions marks in that rectangle and nowhere
    /// else.
    private func chart(in size: CGSize) -> some View {
        let plot = frame.plotRect
        return Chart(frame.marks) { mark in
            LineMark(
                x: .value("x", mark.x),
                y: .value("y", mark.y),
                series: .value("run", mark.seriesKey)
            )
            .foregroundStyle(colour(mark.colour))
            .lineStyle(StrokeStyle(lineWidth: frame.lineWidth, lineCap: .round, lineJoin: .bevel))
            .interpolationMethod(.linear)
        }
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .padding(EdgeInsets(
            top: plot.minY,
            leading: plot.minX,
            bottom: max(0, size.height - plot.maxY),
            trailing: max(0, size.width - plot.maxX)
        ))
    }

    private func drawChrome(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colour(frame.chrome.background)))
        strokeChrome(frame.chrome.lines, in: &context)
        for entry in frame.chrome.labels {
            let resolved = context.resolve(label(entry.text))
            let anchor: UnitPoint = entry.anchor == .trailing ? .trailing : .center
            context.draw(resolved, at: CGPoint(x: entry.x, y: entry.y), anchor: anchor)
        }
    }

    /// Strokes lines that share a colour and width in one call, each as its own subpath — the
    /// same grouping `CoreGraphicsReference` and `CanvasChartView` use, and for the same reason:
    /// two touching axis lines stroked separately blend their antialiased edges into the canvas
    /// separately and land on a different byte at their shared corner.
    private func strokeChrome(_ lines: [ChromeLine], in context: inout GraphicsContext) {
        var index = 0
        while index < lines.count {
            let style = lines[index]
            var path = Path()
            while index < lines.count, lines[index].colour == style.colour, lines[index].width == style.width {
                let line = lines[index]
                path.move(to: CGPoint(x: line.x0, y: line.y0))
                path.addLine(to: CGPoint(x: line.x1, y: line.y1))
                index += 1
            }
            context.stroke(path, with: .color(colour(style.colour)), lineWidth: style.width)
        }
    }

    private static let labelFont = Font.system(size: 9, design: .monospaced)

    private func label(_ text: String) -> Text {
        Text(text).font(Self.labelFont).foregroundStyle(colour(frame.chrome.labelColour))
    }

    private func colour(_ palette: PaletteColor) -> Color {
        Color(.sRGBLinear, red: palette.red, green: palette.green, blue: palette.blue)
    }
}
