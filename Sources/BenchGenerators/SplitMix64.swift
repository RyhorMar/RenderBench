/// Deterministic 64-bit generator, reimplemented here rather than taken from the system.
///
/// `SystemRandomNumberGenerator` is unusable for this project: a benchmark whose input differs
/// between runs cannot support a claim about a difference between runs. One seed produces one
/// bit-identical stream, on every platform and every launch.
///
/// - Note: Steele, Lea and Flood, *Fast Splittable Pseudorandom Number Generators*, OOPSLA 2014,
///   §4 — the `nextLong` mixing function. The constants are the paper's.
/// - SeeAlso: Docs/methods/randomness-and-signals.md
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Creates a generator. Any seed is valid, including zero.
    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
