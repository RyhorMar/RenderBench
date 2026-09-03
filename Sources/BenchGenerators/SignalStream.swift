import BenchCore

/// Produces a signal's samples on a fixed grid, one index at a time, without losing its place.
///
/// The demo used to do this inline and got it wrong in a way worth keeping a type to prevent: it
/// built a fresh noise generator per frame, seeded from the current sample index, so the value a
/// given sample received depended on where frame boundaries happened to fall. Wall-clock deltas
/// decide those boundaries, which made the "one seed, one stream" guarantee — the reason
/// `SplitMix64` is written out by hand in this module — false at the only place it shipped.
///
/// One stream per series, living as long as the series does. It never restarts, so sample *n* is
/// the same number no matter how many calls it took to reach it.
public struct SignalStream: Sendable {
    private let signal: any Signal
    private let sampleRateHz: Double
    private var noise: GaussianNoise
    private var nextIndex: Int

    /// Samples already produced. Equal to the index of the next sample.
    public var producedCount: Int { nextIndex }

    /// Metadata of the series this stream produces.
    public var metadata: SeriesMetadata { signal.metadata }

    /// - Parameters:
    ///   - signal: What to generate.
    ///   - sampleRateHz: Source rate. Independent of any display rate by design.
    ///   - seed: Seed for this stream's noise. Two streams must not share one.
    public init(signal: any Signal, sampleRateHz: Double, seed: UInt64) {
        precondition(sampleRateHz > 0, "sample rate must be positive")
        self.signal = signal
        self.sampleRateHz = sampleRateHz
        self.noise = GaussianNoise(seed: seed)
        self.nextIndex = 0
    }

    /// Produces samples up to but not including index `count`, and hands each to `receive`.
    ///
    /// Calling with a `count` at or below what has already been produced does nothing, so a caller
    /// may advance by fractions of a sample period without losing the remainder.
    public mutating func advance(to count: Int, receive: (Sample) -> Void) {
        guard count > nextIndex else { return }
        for index in nextIndex..<count {
            let seconds = Double(index) / sampleRateHz
            let clean = signal.value(at: seconds)
            let value = signal.noiseSigma > 0 ? clean + signal.noiseSigma * noise.next() : clean
            receive(Sample(carrier: seconds, value: value))
        }
        nextIndex = count
    }
}
