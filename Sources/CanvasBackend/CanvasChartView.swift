import BenchCore
import BenchRuntime
import SwiftUI

/// Strokes a prepared frame. Holds no state and computes nothing.
///
/// Everything it draws was decided before the frame started — including where each tick sits, so
/// the view has no projection of its own to get wrong. That is what makes the CPU cost of a Canvas
/// backend measurable as two separate numbers instead of one lump.
public struct CanvasChartView: View {
    private let frame: CanvasFrame
    private let recorder: RasterTimeRecorder?
    private let chrome: ChartChrome

    /// - Parameters:
    ///   - recorder: Collects how long the draw pass took. Without one, this backend reports no
    ///     rasterisation time at all and its published frame cost is preparation plus path
    ///     building — which is not a rendering method's cost.
    ///   - chrome: Colours and weights for everything that is not a series. Shared with the
    ///     offscreen reference, so the stored image is a reference for what ships; there were
    ///     three independent definitions of these colours before.
    public init(
        frame: CanvasFrame,
        recorder: RasterTimeRecorder? = nil,
        chrome: ChartChrome = .light
    ) {
        self.frame = frame
        self.recorder = recorder
        self.chrome = chrome
    }

    public var body: some View {
        // Opaque, and the background is filled here rather than by a modifier behind it. A
        // non-opaque canvas is cleared to transparent and composited over whatever is underneath
        // every frame — up to a million pixels at 3x — for an alpha channel this design never
        // reads. Opacity obliges the drawing to cover every pixel, which the fill does.
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let clock = ContinuousClock()
            let elapsed = clock.measure { draw(in: &context, size: size) }
            recorder?.record(nanoseconds: elapsed.nanoseconds)
        }
    }

    /// The drawing itself, timed by the caller.
    ///
    /// Split out so the measurement covers the rasterisation and nothing else — and so that what
    /// is being timed is visible at the call site rather than buried in a closure.
    private func draw(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colour(chrome.background)))
        drawContents(&context)
    }

    private func drawContents(_ context: inout GraphicsContext) {
        let plot = frame.plotRect
        guard plot.width > 1, plot.height > 1 else { return }

            var grid = Path()
            for tick in frame.yTicks {
                let y = plot.maxY - CGFloat(tick.position) * plot.height
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            context.stroke(grid, with: .color(colour(chrome.grid)), lineWidth: chrome.gridWidth)

            var axes = Path()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(axes, with: .color(colour(chrome.axis)), lineWidth: chrome.axisWidth)

            // One style for every series: only the colour varies, and rebuilding the value inside
            // the loop allocated per series per frame. Bevel rather than round joins — at roughly
            // one point between vertices a round join builds arc geometry nobody can see, about
            // eight thousand of them a frame, and a Metal backend emitting plain quads would be
            // compared against that cost as if it were a difference in method.
            let style = StrokeStyle(lineWidth: frame.lineWidth, lineCap: .round, lineJoin: .bevel)
            for stroke in frame.strokes {
                context.stroke(stroke.path, with: .color(colour(stroke.colour)), style: style)
            }

            // Resolved once each, then drawn. Text layout every frame is inherent to an
            // immediate-mode backend — there is nowhere to keep a laid-out run between frames —
            // so it is part of this method's cost rather than a defect in it. Worth knowing when
            // reading the numbers: the offscreen reference draws no text, so a comparison against
            // a stored image omits work the measured frame did.
            for tick in frame.yTicks {
                let y = plot.maxY - CGFloat(tick.position) * plot.height
                let resolved = context.resolve(label(tick.label))
                context.draw(resolved, at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing)
            }
            for tick in frame.xTicks {
                let x = plot.minX + CGFloat(tick.position) * plot.width
                let resolved = context.resolve(label(tick.label))
                context.draw(resolved, at: CGPoint(x: x, y: plot.maxY + 10), anchor: .center)
            }
    }

    /// Hoisted: rebuilding the descriptor per tick per frame allocated for a value that never
    /// varies.
    private static let labelFont = Font.system(size: 9, design: .monospaced)

    private func label(_ text: String) -> Text {
        Text(text).font(Self.labelFont).foregroundStyle(colour(chrome.label))
    }

    private func colour(_ palette: PaletteColor) -> Color {
        Color(.sRGBLinear, red: palette.red, green: palette.green, blue: palette.blue)
    }
}
