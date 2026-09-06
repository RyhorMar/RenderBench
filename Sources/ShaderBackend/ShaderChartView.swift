import BenchCore
import BenchRuntime
import SwiftUI

/// Draws a prepared frame as one `Rectangle().colorEffect(chart_line(...))` per contiguous run,
/// over this project's chrome in a `Canvas` underneath.
///
/// `ShaderLibrary.default.chart_line` resolves the compiled shader from the main bundle of
/// whichever process is running — the demo app's, when this view is hosted there. Nothing under
/// `swift test` has compiled `Demo/Sources/Shaders/ChartLine.metal` into any bundle at all, so a
/// `colorEffect` built here and rendered there composites a `Rectangle` whose colour effect never
/// resolved to anything — no crash, no error, just a shape this backend's own package-level tests
/// must not judge by its pixels. That is exactly why the shader's equivalence test lives in
/// `RenderBenchDemoTests` instead of here: only the app target's bundle has the compiled function.
public struct ShaderChartView: View {
    private let frame: ShaderFrame

    public init(frame: ShaderFrame) {
        self.frame = frame
    }

    public var body: some View {
        ZStack {
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                drawChrome(in: &context, size: size)
            }
            // One `colorEffect` per run rather than per series: see `ShaderLineBuffers` for why a
            // break becomes a separate invocation instead of a marker inside one series' buffer.
            // Keyed by series index first, then run position within that series — a series keeps
            // the identity SwiftUI already tracks for it across frames even though the number of
            // runs inside it can itself change frame to frame as breaks move.
            ForEach(frame.series, id: \.index) { series in
                ForEach(Array(series.runs.enumerated()), id: \.offset) { _, run in
                    Rectangle()
                        .colorEffect(
                            ShaderLibrary.default.chart_line(
                                .data(run),
                                .float(Float(frame.lineWidth / 2)),
                                .color(colour(series.colour))
                            )
                        )
                }
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
