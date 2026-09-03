import BenchCore
import BenchScales
import SwiftUI

/// Strokes a prepared frame. Holds no state and computes nothing.
///
/// Everything it draws was decided before the frame started, which is what makes the CPU cost of a
/// Canvas backend measurable as two separate numbers instead of one lump.
public struct CanvasChartView: View {
    private let frame: CanvasFrame
    private let lineWidth: Double
    private let axisColour: Color
    private let gridColour: Color
    private let labelColour: Color

    public init(
        frame: CanvasFrame,
        lineWidth: Double,
        axisColour: Color = .secondary,
        gridColour: Color = Color.secondary.opacity(0.18),
        labelColour: Color = .secondary
    ) {
        self.frame = frame
        self.lineWidth = lineWidth
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
                let y = plot.maxY - CGFloat(normalised(tick.value, in: frame.yTicks)) * plot.height
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            context.stroke(grid, with: .color(gridColour), lineWidth: 0.5)

            var axes = Path()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(axes, with: .color(axisColour), lineWidth: 1)

            for stroke in frame.strokes {
                context.stroke(
                    stroke.path,
                    with: .color(colour(stroke.colour)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            for tick in frame.yTicks {
                let y = plot.maxY - CGFloat(normalised(tick.value, in: frame.yTicks)) * plot.height
                context.draw(
                    Text(tick.label).font(.system(size: 9, design: .monospaced)).foregroundStyle(labelColour),
                    at: CGPoint(x: plot.minX - 6, y: y),
                    anchor: .trailing
                )
            }
            for tick in frame.xTicks {
                let x = plot.minX + CGFloat(normalisedX(tick.value)) * plot.width
                context.draw(
                    Text(tick.label).font(.system(size: 9, design: .monospaced)).foregroundStyle(labelColour),
                    at: CGPoint(x: x, y: plot.maxY + 10),
                    anchor: .center
                )
            }
        }
    }

    private func colour(_ palette: PaletteColor) -> Color {
        Color(.sRGBLinear, red: palette.red, green: palette.green, blue: palette.blue)
    }

    private func normalised(_ value: Double, in ticks: [Tick]) -> Double {
        guard let low = ticks.first?.value, let high = ticks.last?.value, high > low else { return 0.5 }
        return (value - low) / (high - low)
    }

    private func normalisedX(_ value: Double) -> Double {
        guard let low = frame.xTicks.first?.value,
              let high = frame.xTicks.last?.value,
              high > low
        else { return 0.5 }
        return (value - low) / (high - low)
    }
}
