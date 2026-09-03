import Foundation

/// Normally distributed noise from a seeded uniform generator.
///
/// Box–Muller rather than a library call, for the same reason `SplitMix64` is written out here:
/// the transform must be reproducible across platforms and launches, and it produces two values
/// per pair of uniforms, so the second is kept rather than thrown away.
/// - SeeAlso: Docs/methods/randomness-and-signals.md
public struct GaussianNoise: Sendable {
    private var uniform: SplitMix64
    private var spare: Double?

    public init(seed: UInt64) {
        self.uniform = SplitMix64(seed: seed)
        self.spare = nil
    }

    /// Next draw from N(0, 1).
    public mutating func next() -> Double {
        if let spare {
            self.spare = nil
            return spare
        }
        // Excluding zero: log(0) is not a number anyone wants in a signal.
        var first = 0.0
        while first <= .leastNormalMagnitude {
            first = Double(uniform.next() >> 11) * 0x1p-53
        }
        let second = Double(uniform.next() >> 11) * 0x1p-53

        let radius = (-2 * log(first)).squareRoot()
        let angle = 2 * Double.pi * second
        spare = radius * sin(angle)
        return radius * cos(angle)
    }
}
