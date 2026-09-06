import BenchCore
import BenchRuntime
import SwiftUI

/// Draws a prepared frame as one retained `PolylineShape` per series, stroked by SwiftUI's own
/// `ShapeView`, with this project's chrome underneath in a `Canvas`.
///
/// Unlike `CanvasChartView`, which redraws every point inside a closure this process runs on every
/// tick, this view hands SwiftUI a `Shape` value it owns: `body` runs again on `frame` changing,
/// but rasterising the shapes themselves is SwiftUI's own render server's decision, made on its
/// own thread, after `body` has already returned — the same shape of problem `SwiftChartsChartView`
/// and `CoreAnimationBackend`'s layer tree both have.
public struct ShapePathChartView: View {
    private let frame: ShapePathFrame

    public init(frame: ShapePathFrame) {
        self.frame = frame
    }

    public var body: some View {
        ZStack {
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                drawChrome(in: &context, size: size)
            }
            // One `PolylineShape` per series, keyed by its own index rather than by position in
            // this array: a series must keep the identity SwiftUI already tracks for it across
            // frames, or a retained shape becomes a rebuilt one on every tick.
            ForEach(frame.series, id: \.index) { series in
                PolylineShape(points: series.points, breaks: series.breaks)
                    .stroke(
                        colour(series.colour),
                        style: StrokeStyle(lineWidth: frame.lineWidth, lineCap: .round, lineJoin: .bevel)
                    )
            }
        }
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

    /// Strokes lines that share a colour and width in one call, each as its own subpath — the same
    /// grouping every other backend's chrome uses, and for the same reason: two touching axis
    /// lines stroked separately blend their antialiased edges into the canvas separately and land
    /// on a different byte at their shared corner.
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
