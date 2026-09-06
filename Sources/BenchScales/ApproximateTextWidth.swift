/// Width estimate for tick labels.
///
/// Deliberately arithmetic rather than a real text layout: laying out a `Text` per candidate label
/// costs more than the tick selection it informs, and the digits of a monospaced-digit font are
/// uniform enough that a per-character constant is within a point of the truth.
///
/// Public and injectable, because the numbers it produces are the input to collision avoidance: a
/// caller who needs CoreText metrics, or a test that needs to pin a tick count, has to be able to
/// supply their own.
public struct ApproximateTextWidth: TextMeasuring {
    public var pointsPerCharacter: Double
    public var lineHeight: Double

    public init(pointsPerCharacter: Double = 7.5, lineHeight: Double = 11) {
        self.pointsPerCharacter = pointsPerCharacter
        self.lineHeight = lineHeight
    }

    public func width(of text: String) -> Double {
        Double(text.count) * pointsPerCharacter
    }
}
