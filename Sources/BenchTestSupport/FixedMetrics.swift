import BenchScales

/// Text metrics that do not depend on a font, a platform or a rendering pass.
///
/// Tick selection is arithmetic on measured labels, so a test that wants to pin a tick count needs
/// a measurer whose numbers it chose. Shared from here rather than redeclared per test target,
/// because four copies of a stub drift and then two suites disagree about what "fits".
public struct FixedMetrics: TextMeasuring {
    public let pointsPerCharacter: Double
    public let lineHeight: Double

    public init(pointsPerCharacter: Double = 7.5, lineHeight: Double = 11) {
        self.pointsPerCharacter = pointsPerCharacter
        self.lineHeight = lineHeight
    }

    public func width(of text: String) -> Double {
        Double(text.count) * pointsPerCharacter
    }
}
