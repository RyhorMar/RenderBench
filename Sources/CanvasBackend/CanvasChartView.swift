import BenchCore
import SwiftUI

/// Strokes a prepared frame. Holds no state and computes nothing.
///
/// Everything it draws was decided before the frame started — including where each tick sits, so
/// the view has no projection of its own to get wrong. That is what makes the CPU cost of a Canvas
/// backend measurable as two separate numbers instead of one lump.
public struct CanvasChartView: View {
    private let frame: CanvasFrame
    private let axisColour: Color
    private let gridColour: Color
    private let labelColour: Color

    public init(
        frame: CanvasFrame,
        axisColour: Color = .secondary,
        gridColour: Color = Color.secondary.opacity(0.18),
        labelColour: Color = .secondary
    ) {
        self.frame = frame
        self.axisColour = axisColour
        self.gridColour = gridColour
        self.labelColour = labelColour
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let plot = frame.plotRect
            guard plot.width > 1, plot.height > 1 else { return }

            var grid = Path()
            for tick in frame.yTicks {
                let y = plot.maxY - CGFloat(tick.position) * plot.height
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            context.stroke(grid, with: .color(gridColour), lineWidth: 0.5)

            var axes = Path()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(axes, with: .color(axisColour), lineWidth: 1)

            // One style for every series: only the colour varies, and rebuilding the value inside
            // the loop allocated per series per frame. Bevel rather than round joins — at roughly
            // one point between vertices a round join builds arc geometry nobody can see, about
            // eight thousand of them a frame, and a Metal backend emitting plain quads would be
            // compared against that cost as if it were a difference in method.
            let style = StrokeStyle(lineWidth: frame.lineWidth, lineCap: .round, lineJoin: .bevel)
            for stroke in frame.strokes {
                context.stroke(stroke.path, with: .color(colour(stroke.colour)), style: style)
            }

            for tick in frame.yTicks {
                let y = plot.maxY - CGFloat(tick.position) * plot.height
                context.draw(
                    label(tick.label),
                    at: CGPoint(x: plot.minX - 6, y: y),
                    anchor: .trailing
                )
            }
            for tick in frame.xTicks {
                let x = plot.minX + CGFloat(tick.position) * plot.width
                context.draw(
                    label(tick.label),
                    at: CGPoint(x: x, y: plot.maxY + 10),
                    anchor: .center
                )
            }
        }
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(labelColour)
    }

    private func colour(_ palette: PaletteColor) -> Color {
        Color(.sRGBLinear, red: palette.red, green: palette.green, blue: palette.blue)
    }
}
