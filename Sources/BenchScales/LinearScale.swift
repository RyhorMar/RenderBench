import Foundation

/// Straight proportional projection from a data range onto `[0, 1]`.
public struct LinearScale: AxisScale {
    public let domain: ClosedRange<Double>

    public init(domain: ClosedRange<Double>) {
        self.domain = domain
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
        guard span > 0, target > 0 else { return [] }

        // Measured with the step the caller's target implies. Both ends are offered, because the
        // longer label is as often the negative lower bound as the upper one.
        let probeStep = NiceSteps.step(forSpan: span, targetCount: target)
        let probeDecimals = NiceSteps.decimals(forStep: probeStep)
        let affordable = TickLayout.affordableCount(
            target: target,
            axisLength: axisLength,
            candidates: [
                Self.label(for: domain.lowerBound, decimals: probeDecimals),
                Self.label(for: domain.upperBound, decimals: probeDecimals),
            ],
            orientation: orientation,
            measuring: measuring
        )

        let step = NiceSteps.step(forSpan: span, targetCount: affordable)
        let decimals = NiceSteps.decimals(forStep: step)
        return TickLayout.walk(domain: domain, step: step, cap: target) {
            Self.label(for: $0, decimals: decimals)
        }
    }

    private static func label(for value: Double, decimals: Int) -> String {
        // Negative zero prints as "-0", which reads as a distinct value to everyone but a float.
        let cleaned = value == 0 ? 0 : value
        return String(format: "%.\(decimals)f", cleaned)
    }
}
