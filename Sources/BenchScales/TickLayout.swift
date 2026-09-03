/// Shared tick-layout arithmetic.
///
/// Both scales need the same three steps — decide how many labels fit, pick a step, walk it — and
/// a third scale will need them too. Keeping one copy means a fix to the collision rule lands
/// everywhere rather than in whichever scale the reporter happened to be looking at.
enum TickLayout {
    /// Largest number of labels that fit on `axisLength` without touching.
    ///
    /// - Parameters:
    ///   - target: The caller's cap. The result never exceeds it.
    ///   - candidates: Labels that may appear. **Both domain ends must be included**: measuring
    ///     only the upper bound under-measures a domain like `-100000...1`, and under-measuring is
    ///     always the failing direction, because this count can only reduce the caller's target.
    static func affordableCount(
        target: Int,
        axisLength: Double,
        candidates: [String],
        orientation: AxisOrientation,
        measuring: some TextMeasuring
    ) -> Int {
        guard target > 0, axisLength > 0 else { return 0 }
        let spacing = candidates
            .map { measuring.minimumSpacing(for: $0, along: orientation) }
            .max() ?? 0
        guard spacing > 0 else { return target }
        return max(2, min(target, max(Int(axisLength / spacing), 2)))
    }

    /// Ticks on multiples of `step` inside `domain`, never more than `cap` of them.
    ///
    /// The walk is bounded twice: by the domain and by `cap`. The second bound is what makes the
    /// protocol's "at most `target`" true — a domain whose ends both land on a step otherwise
    /// yields one more tick than the caller asked for, and a caller sizing a label pool from
    /// `target` under-allocates on exactly those axes.
    static func walk(
        domain: ClosedRange<Double>,
        step: Double,
        cap: Int,
        label: (Double) -> String
    ) -> [Tick] {
        guard step > 0, cap > 0, domain.upperBound > domain.lowerBound else { return [] }
        var ticks: [Tick] = []
        ticks.reserveCapacity(cap)
        var value = NiceSteps.alignedUp(domain.lowerBound, to: step)
        // The epsilon admits a final tick that floating-point drift places a hair past the bound.
        while value <= domain.upperBound + step * 1e-9, ticks.count < cap {
            ticks.append(Tick(value: value, label: label(value), isMajor: true))
            value += step
        }
        return ticks
    }
}

extension AxisScale {
    /// Clamped proportional projection, shared by every scale that is linear in its own space.
    ///
    /// A collapsed domain has no proportion to report, so it lands mid-axis and is flagged: a
    /// caller must not be able to mistake the collapse for data sitting at the bottom.
    func proportional(_ value: Double, in domain: ClosedRange<Double>) -> MapResult {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return MapResult(normalised: 0.5, isOutOfDomain: true) }
        let raw = (value - domain.lowerBound) / span
        let outside = value < domain.lowerBound || value > domain.upperBound
        return MapResult(normalised: min(max(raw, 0), 1), isOutOfDomain: outside)
    }

    /// Inverse of ``proportional(_:in:)``.
    func proportionalInverse(_ normalised: Double, in domain: ClosedRange<Double>) -> Double {
        domain.lowerBound + normalised * (domain.upperBound - domain.lowerBound)
    }
}
