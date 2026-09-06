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
    private let encodedRevision: UInt64

    /// - Parameters:
    ///   - recorder: Collects how long the draw pass took. Without one, this backend reports no
    ///     rasterisation time at all and its published frame cost is preparation plus path
    ///     building — which is not a rendering method's cost.
    ///   - encodedRevision: Which `encode()` call produced `frame`. Tags the recording so a
    ///     caller reading it later — this view draws one tick after `encode()`, by construction —
    ///     knows which frame it belongs to rather than assuming it is the newest one.
    public init(
        frame: CanvasFrame,
        recorder: RasterTimeRecorder? = nil,
        encodedRevision: UInt64 = 0
    ) {
        self.frame = frame
        self.recorder = recorder
        self.encodedRevision = encodedRevision
    }

    public var body: some View {
        // Opaque, and the background is filled here rather than by a modifier behind it. A
        // non-opaque canvas is cleared to transparent and composited over whatever is underneath
        // every frame — up to a million pixels at 3x — for an alpha channel this design never
        // reads. Opacity obliges the drawing to cover every pixel, which the fill does.
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let clock = ContinuousClock()
            let elapsed = clock.measure { draw(in: &context, size: size) }
            recorder?.record(nanoseconds: elapsed.nanoseconds, encodedRevision: encodedRevision)
        }
    }

    /// The drawing itself, timed by the caller.
    ///
    /// Split out so the measurement covers the rasterisation and nothing else — and so that what
    /// is being timed is visible at the call site rather than buried in a closure.
    private func draw(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colour(frame.chrome.background)))
        drawContents(&context)
    }

    private func drawContents(_ context: inout GraphicsContext) {
        let plot = frame.plotRect
        guard plot.width > 1, plot.height > 1 else { return }

        strokeChrome(frame.chrome.lines, in: &context)

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
        // immediate-mode backend — there is nowhere to keep a laid-out run between frames — so it
        // is part of this method's cost rather than a defect in it.
        for entry in frame.chrome.labels {
            let resolved = context.resolve(label(entry.text))
            let anchor: UnitPoint = entry.anchor == .trailing ? .trailing : .center
            context.draw(resolved, at: CGPoint(x: entry.x, y: entry.y), anchor: anchor)
        }
    }

    /// Strokes lines that share a colour and width in one `stroke(_:with:lineWidth:)` call, each
    /// as its own subpath.
    ///
    /// Grouping matters here for the same reason it does in ``OffscreenRenderTarget`` — measured
    /// there: two touching axis lines stroked in separate calls blend their antialiased edges
    /// into the canvas separately and land on a different byte at their shared corner than the
    /// same two edges stroked together. Both draw through Core Graphics with the same default cap
    /// and join, so the same grouping is kept here rather than re-measuring an effect that is a
    /// property of the rasteriser, not of this call site.
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

    /// Hoisted: rebuilding the descriptor per tick per frame allocated for a value that never
    /// varies.
    private static let labelFont = Font.system(size: 9, design: .monospaced)

    private func label(_ text: String) -> Text {
        Text(text).font(Self.labelFont).foregroundStyle(colour(frame.chrome.labelColour))
    }

    private func colour(_ palette: PaletteColor) -> Color {
        Color(.sRGBLinear, red: palette.red, green: palette.green, blue: palette.blue)
    }
}
