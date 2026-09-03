import Foundation

/// Straight proportional projection from a data range onto `[0, 1]`.
public struct LinearScale: AxisScale {
    public let domain: ClosedRange<Double>

    public init(domain: ClosedRange<Double>) {
        self.domain = domain
    }

    private var span: Double { domain.upperBound - domain.lowerBound }

    public func map(_ value: Double) -> MapResult {
        guard span > 0 else {
            // A degenerate domain has no proportion to report. Everything lands mid-axis and is
            // flagged, so a caller cannot mistake the collapse for data sitting at the centre.
            return MapResult(normalised: 0.5, isOutOfDomain: true)
        }
        let raw = (value - domain.lowerBound) / span
        let outside = value < domain.lowerBound || value > domain.upperBound
        return MapResult(normalised: min(max(raw, 0), 1), isOutOfDomain: outside)
    }

    public func invert(_ normalised: Double) -> Double {
        domain.lowerBound + normalised * span
    }

    public func ticks(target: Int, axisLength: Double, measuring: some TextMeasuring) -> [Tick] {
        guard span > 0, target > 0 else { return [] }
        let step = NiceSteps.step(forSpan: span, targetCount: target)
        let decimals = NiceSteps.decimals(forStep: step)

        // How many labels the axis can physically hold, measured rather than assumed. Without
        // this the caller's target silently becomes a promise the axis cannot keep and labels
        // overlap at exactly the zoom levels where the reader is looking hardest.
        let widest = measuring.width(of: Self.label(for: domain.upperBound, decimals: decimals))
        let affordable = widest > 0 ? Int(axisLength / (widest * 1.5)) : target
        let effective = max(2, min(target, max(affordable, 2)))
        let chosenStep = NiceSteps.step(forSpan: span, targetCount: effective)
        let chosenDecimals = NiceSteps.decimals(forStep: chosenStep)

        var ticks: [Tick] = []
        var value = NiceSteps.alignedUp(domain.lowerBound, to: chosenStep)
        // Bounded so that a pathological domain cannot spin here; the bound is far above any
        // label count an axis could display.
        while value <= domain.upperBound + chosenStep * 1e-9, ticks.count < 10_000 {
            ticks.append(
                Tick(value: value, label: Self.label(for: value, decimals: chosenDecimals), isMajor: true)
            )
            value += chosenStep
        }
        return ticks
    }

    private static func label(for value: Double, decimals: Int) -> String {
        // Negative zero prints as "-0", which reads as a distinct value to everyone but a float.
        let cleaned = value == 0 ? 0 : value
        return String(format: "%.\(decimals)f", cleaned)
    }
}
