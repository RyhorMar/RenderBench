/// One tick on an axis: where it sits, what it reads, and whether it carries a label.
public struct Tick: Sendable, Equatable {
    /// Position in data space.
    public let value: Double
    /// Rendered text. Empty for minor ticks, which are drawn but not labelled.
    public let label: String
    /// Major ticks are labelled and drawn heavier; minor ticks subdivide them.
    public let isMajor: Bool

    public init(value: Double, label: String, isMajor: Bool) {
        self.value = value
        self.label = label
        self.isMajor = isMajor
    }
}

/// Result of projecting a value into normalised space.
///
/// The out-of-domain flag exists because silence is the failure mode that matters here: a
/// logarithmic scale meeting a zero or a negative value must report it, not drop the point and
/// leave the reader with a curve that is quietly missing its most interesting samples.
public struct MapResult: Sendable, Equatable {
    /// Position in `[0, 1]` for values inside the domain; clamped outside it.
    public let normalised: Double
    /// True when the value has no image under this scale, and `normalised` is a clamp.
    public let isOutOfDomain: Bool

    public init(normalised: Double, isOutOfDomain: Bool) {
        self.normalised = normalised
        self.isOutOfDomain = isOutOfDomain
    }
}

/// Which way an axis runs, and therefore which dimension of a label limits how many fit.
///
/// The distinction is not cosmetic: labels on a horizontal axis collide along their width, labels
/// on a vertical axis collide along their line height. A single measurement cannot answer both.
public enum AxisOrientation: Sendable {
    case horizontal
    case vertical
}

/// Measures rendered text so that tick density can be chosen without over-plotting.
///
/// Behind a protocol on purpose: the implementation needs CoreText or UIKit, and this module is
/// not allowed to import either. The drawing layer supplies one; tests supply a fixed-size stub.
public protocol TextMeasuring: Sendable {
    /// Width of `text` in points, in whatever font the caller has configured.
    func width(of text: String) -> Double
    /// Height of one line in points, in the same font.
    var lineHeight: Double { get }
}

extension TextMeasuring {
    /// Smallest centre-to-centre spacing at which two labels do not touch, in points.
    ///
    /// The 1.5 factor is a gutter, not a measurement: labels that merely abut are unreadable even
    /// though they do not overlap.
    public func minimumSpacing(for text: String, along orientation: AxisOrientation) -> Double {
        let extent = orientation == .horizontal ? width(of: text) : lineHeight
        return extent * 1.5
    }
}

/// Projection between data space and the normalised `[0, 1]` space every backend draws in.
///
/// Implementations are value types and must be free of drawing state: the same scale instance is
/// used by the downsampler, by the axis renderer and by hit-testing within one frame.
public protocol AxisScale: Sendable {
    /// Values the scale accepts. Values outside it are reported, never silently dropped.
    var domain: ClosedRange<Double> { get }
    /// Projects a data value into `[0, 1]`.
    func map(_ value: Double) -> MapResult
    /// Inverse of ``map(_:)`` for values inside the domain.
    func invert(_ normalised: Double) -> Double
    /// Ticks for the current domain, aiming for `target` labels without letting them collide.
    ///
    /// - Parameters:
    ///   - target: Largest number of ticks that may be returned. A hard cap, not a wish: a caller
    ///     sizing a label pool from it must not be handed more.
    ///   - axisLength: Length of the axis in points. Required: collision avoidance is arithmetic
    ///     on a measured label against available length, and without the length the measurer is
    ///     decoration.
    ///   - orientation: Which dimension of a label limits spacing on this axis.
    ///   - measuring: Supplies rendered text metrics in the caller's font.
    /// - Returns: At most `target` ticks, ordered by increasing value.
    func ticks(
        target: Int,
        axisLength: Double,
        orientation: AxisOrientation,
        measuring: some TextMeasuring
    ) -> [Tick]
}
