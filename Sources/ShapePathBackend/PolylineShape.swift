import SwiftUI

/// One series' polyline, as a retained SwiftUI `Shape` rather than a `Path` stroked inside a draw
/// closure.
///
/// `points` already sit in the plot's own coordinate space — the same absolute, top-left-origin
/// points `CanvasChartRenderer` builds — so `path(in:)` ignores the rectangle SwiftUI offers it:
/// re-deriving a rectangle-relative layout here would be a second, independently sourced geometry
/// that could disagree with the one `ShapePathChartRenderer` already computed from `PreparedFrame`.
public struct PolylineShape: Shape {
    /// Absolute plot-space coordinates, breaks already removed: a break carries no position of its
    /// own, so keeping its placeholder would put a mark where the series has no measurement.
    public var points: [CGPoint]
    /// Indices into `points` where a break in the source series fell. The point at such an index
    /// starts a new subpath instead of continuing the one before it.
    public var breaks: Set<Int>

    /// Creates a shape from geometry `ShapePathChartRenderer` already built.
    public init(points: [CGPoint], breaks: Set<Int>) {
        self.points = points
        self.breaks = breaks
    }

    /// Builds the path SwiftUI strokes. Called on SwiftUI's own schedule, not once per tick.
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            if index == 0 || breaks.contains(index) {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
