import Foundation

/// Projection for a carrier measured in seconds, with ticks on divisions people read clocks in.
///
/// Time is not decimal, so the nice-step ladder does not apply: 2.5 minutes is not a boundary any
/// reader recognises. The steps come from a closed list of clock divisions instead, which is also
/// what keeps a label from landing at 07:43:12 when the reader wants to know roughly when.
public struct TimeScale: AxisScale {
    /// Seconds since the series epoch.
    public let domain: ClosedRange<Double>
    /// Offset applied before formatting, in seconds east of UTC.
    ///
    /// Carried explicitly rather than read from the environment: a benchmark rendered in one zone
    /// and compared in another must produce the same pixels, and a scale that consults a global
    /// clock setting cannot promise that.
    public let secondsFromGMT: Int

    /// Clock divisions labels may fall on, in seconds.
    static let ladder: [Double] = [
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1_800,
        3_600, 7_200, 10_800, 21_600, 43_200,
        86_400,
    ]

    public init(domain: ClosedRange<Double>, secondsFromGMT: Int = 0) {
        self.domain = domain
        self.secondsFromGMT = secondsFromGMT
    }

    private var span: Double { domain.upperBound - domain.lowerBound }

    public func map(_ value: Double) -> MapResult {
        guard span > 0 else { return MapResult(normalised: 0.5, isOutOfDomain: true) }
        let raw = (value - domain.lowerBound) / span
        let outside = value < domain.lowerBound || value > domain.upperBound
        return MapResult(normalised: min(max(raw, 0), 1), isOutOfDomain: outside)
    }

    public func invert(_ normalised: Double) -> Double {
        domain.lowerBound + normalised * span
    }

    public func ticks(target: Int, axisLength: Double, measuring: some TextMeasuring) -> [Tick] {
        guard span > 0, target > 0 else { return [] }

        let sample = Self.label(forSecond: domain.upperBound, offset: secondsFromGMT, step: 1)
        let widest = measuring.width(of: sample)
        let affordable = widest > 0 ? Int(axisLength / (widest * 1.5)) : target
        let effective = max(2, min(target, max(affordable, 2)))

        let step = Self.ladderStep(forSpan: span, targetCount: effective)
        var ticks: [Tick] = []
        var value = NiceSteps.alignedUp(domain.lowerBound, to: step)
        while value <= domain.upperBound + step * 1e-9, ticks.count < 10_000 {
            ticks.append(
                Tick(
                    value: value,
                    label: Self.label(forSecond: value, offset: secondsFromGMT, step: step),
                    isMajor: true
                )
            )
            value += step
        }
        return ticks
    }

    /// Coarsest ladder entry that still yields at least `targetCount` intervals, or the coarsest
    /// entry there is when the window spans more than a day.
    static func ladderStep(forSpan span: Double, targetCount: Int) -> Double {
        let ideal = span / Double(targetCount)
        for candidate in ladder where candidate >= ideal { return candidate }
        // Beyond a day, fall back to whole days so that labels stay on midnight boundaries.
        return ladder[ladder.count - 1] * (ideal / ladder[ladder.count - 1]).rounded(.up)
    }

    /// Formats one instant at a resolution matched to the step.
    ///
    /// Seconds appear only when the step is finer than a minute, and the day appears only when the
    /// step reaches a day; showing more precision than the spacing supports is how an axis ends up
    /// with six labels that differ in their last digit alone.
    static func label(forSecond value: Double, offset: Int, step: Double) -> String {
        let total = Int((value + Double(offset)).rounded(.down))
        let secondOfDay = ((total % 86_400) + 86_400) % 86_400
        let hours = secondOfDay / 3_600
        let minutes = (secondOfDay % 3_600) / 60
        let seconds = secondOfDay % 60

        if step < 60 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        if step < 86_400 {
            return String(format: "%02d:%02d", hours, minutes)
        }
        let day = Int((Double(total) / 86_400).rounded(.down))
        return "d\(day)"
    }
}
