import BenchCore
import Foundation

/// The chart's furniture: the colours and weights of everything that is not a series.
///
/// One definition, because there were three. The offscreen reference stroked its grid at 0.8 linear
/// grey, the SwiftUI view used `Color.secondary.opacity(0.18)`, and the layer tree used a third
/// value — so a reference image was a reference for a chart nobody was looking at, and the
/// cross-backend comparison only agreed because both sides read the same wrong constants.
public struct ChartChrome: Sendable, Equatable {
    public var background: PaletteColor
    public var grid: PaletteColor
    public var axis: PaletteColor
    public var label: PaletteColor
    public var gridWidth: Double
    public var axisWidth: Double

    public init(
        background: PaletteColor,
        grid: PaletteColor,
        axis: PaletteColor,
        label: PaletteColor,
        gridWidth: Double = 0.5,
        axisWidth: Double = 1
    ) {
        self.background = background
        self.grid = grid
        self.axis = axis
        self.label = label
        self.gridWidth = gridWidth
        self.axisWidth = axisWidth
    }

    public static let light = ChartChrome(
        background: PaletteColor(srgb: 252, 252, 252),
        grid: PaletteColor(srgb: 222, 222, 224),
        axis: PaletteColor(srgb: 142, 142, 147),
        label: PaletteColor(srgb: 108, 108, 112)
    )

    public static let dark = ChartChrome(
        background: PaletteColor(srgb: 28, 28, 30),
        grid: PaletteColor(srgb: 58, 58, 62),
        axis: PaletteColor(srgb: 120, 120, 128),
        label: PaletteColor(srgb: 152, 152, 160)
    )

    public static func forScheme(dark: Bool) -> ChartChrome { dark ? .dark : .light }
}

/// Snapping a coordinate so a stroke lands on whole device pixels.
///
/// A one-point line centred on an integer coordinate spans half a pixel either side, so it
/// rasterises as two columns at half coverage instead of one crisp line. Offsetting by half a pixel
/// in device space is the standard remedy and it has to know the scale, which is why nothing in
/// this package could do it while no scale existed anywhere.
public enum PixelSnap {
    /// Centres a stroke of `width` on the nearest device pixel boundary.
    public static func centre(_ value: Double, width: Double, scale: Double) -> Double {
        guard scale > 0 else { return value }
        let devicePixels = value * scale
        // An odd-width stroke sits on a pixel centre, an even-width one on a boundary.
        let odd = Int((width * scale).rounded()) % 2 != 0
        let snapped = odd ? (devicePixels - 0.5).rounded() + 0.5 : devicePixels.rounded()
        return snapped / scale
    }
}
