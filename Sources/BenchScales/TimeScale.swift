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
    ///
    /// Starts below a second because the reference chart's shortest window is one second: with a
    /// one-second floor that window gets two labels, which is an axis with endpoints rather than
    /// an axis. Tenths are still divisions a reader recognises; hundredths are not, so the ladder
    /// stops there.
    static let ladder: [Double] = [
        0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1_800,
        3_600, 7_200, 10_800, 21_600, 43_200,
        86_400,
    ]

    /// Largest instant this scale can label.
    ///
    /// Formatting converts seconds to an integer, so a domain beyond this cannot be rendered. It
    /// is reported as an empty axis rather than a trap: a caller charting nanosecond-epoch values
    /// has made a unit mistake, and crashing their process is not how they should find out.
    static let labelableLimit: Double = 4e18

    public init(domain: ClosedRange<Double>, secondsFromGMT: Int = 0) {
        self.domain = domain
        self.secondsFromGMT = secondsFromGMT
    }

    public func map(_ value: Double) -> MapResult {
        proportional(value, in: domain)
    }

    public func invert(_ normalised: Double) -> Double {
        proportionalInverse(normalised, in: domain)
    }

    public func ticks(
        target: Int,
        axisLength: Double,
        orientation: AxisOrientation,
        measuring: some TextMeasuring
    ) -> [Tick] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, target > 0, isLabelable else { return [] }

        let probeStep = Self.ladderStep(forSpan: span, targetCount: target)
        let affordable = TickLayout.affordableCount(
            target: target,
            axisLength: axisLength,
            candidates: [
                Self.label(forSecond: domain.lowerBound, offset: secondsFromGMT, step: probeStep),
                Self.label(forSecond: domain.upperBound, offset: secondsFromGMT, step: probeStep),
            ],
            orientation: orientation,
            measuring: measuring
        )

        let step = Self.ladderStep(forSpan: span, targetCount: affordable)
        return TickLayout.walk(domain: domain, step: step, cap: target) {
            Self.label(forSecond: $0, offset: secondsFromGMT, step: step)
        }
    }

    /// Whether both ends of the domain can be converted to an integer number of seconds.
    var isLabelable: Bool {
        domain.lowerBound.isFinite
            && domain.upperBound.isFinite
            && abs(domain.lowerBound) < Self.labelableLimit
            && abs(domain.upperBound) < Self.labelableLimit
    }

    /// Coarsest ladder entry that still yields at least `targetCount` intervals, or whole days
    /// when the window spans more than one.
    static func ladderStep(forSpan span: Double, targetCount: Int) -> Double {
        guard span > 0, targetCount > 0 else { return 1 }
        let ideal = span / Double(targetCount)
        for candidate in ladder where candidate >= ideal { return candidate }
        let day = ladder[ladder.count - 1]
        return day * max(1, (ideal / day).rounded(.up))
    }

    /// Formats one instant at a resolution matched to the step.
    ///
    /// Seconds appear only when the step is finer than a minute, tenths only when it is finer than
    /// a second, and the day only when the step reaches a day. Showing more precision than the
    /// spacing supports is how an axis ends up with six labels differing in their last digit alone.
    ///
    /// - Precondition: `abs(value + offset) < labelableLimit`. Callers reach this through
    ///   ``ticks(target:axisLength:orientation:measuring:)``, which refuses such a domain.
    static func label(forSecond value: Double, offset: Int, step: Double) -> String {
        let shifted = value + Double(offset)
        guard shifted.isFinite, abs(shifted) < labelableLimit else { return "" }

        let total = Int(shifted.rounded(.down))
        let secondOfDay = ((total % 86_400) + 86_400) % 86_400
        let hours = secondOfDay / 3_600
        let minutes = (secondOfDay % 3_600) / 60
        let seconds = secondOfDay % 60

        if step < 1 {
            let fraction = shifted - Double(total)
            return String(format: "%02d:%02d.%01d", minutes, seconds, Int(fraction * 10))
        }
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
