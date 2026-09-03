import Foundation

/// Tick spacings a reader can do arithmetic in.
///
/// Axis labels are read, subtracted and interpolated by eye. A step of 3.7 defeats all three, so
/// the spacing is snapped to `1`, `2`, `2.5` or `5` times a power of ten. The 2.5 is what makes
/// quarters land on round numbers, which matters for fractions and percentages.
///
/// - SeeAlso: Docs/methods/axis-ticks.md
public enum NiceSteps {
    /// The smallest allowed step that yields at most `targetCount` intervals across `span`.
    ///
    /// - Parameters:
    ///   - span: Extent of the domain. Non-positive spans yield `1`, so an empty domain produces
    ///     a degenerate axis rather than a division by zero.
    ///   - targetCount: How many intervals the caller would like. Must be positive.
    /// - Returns: A step from the allowed set, always greater than zero.
    public static func step(forSpan span: Double, targetCount: Int) -> Double {
        guard span > 0, targetCount > 0, span.isFinite else { return 1 }
        let raw = span / Double(targetCount)
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let normalised = raw / magnitude
        for candidate in [1.0, 2.0, 2.5, 5.0] where normalised <= candidate {
            return candidate * magnitude
        }
        return 10 * magnitude
    }

    /// Smallest multiple of `step` that is not below `value`.
    public static func alignedUp(_ value: Double, to step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded(.up) * step
    }

    /// Number of decimal places needed to write `step` without losing it to rounding.
    ///
    /// A step of 2.5 needs one decimal, a step of 250 needs none. Deriving this from the step
    /// rather than from the values is what keeps the label width stable as a window scrolls.
    public static func decimals(forStep step: Double) -> Int {
        guard step > 0, step.isFinite else { return 0 }
        let exponent = Int((log10(step)).rounded(.down))
        // 2.5 and 0.25 carry one more digit than their magnitude suggests.
        let mantissa = step / pow(10, Double(exponent))
        let extra = abs(mantissa - 2.5) < 1e-9 ? 1 : 0
        return max(0, -exponent + extra)
    }
}
