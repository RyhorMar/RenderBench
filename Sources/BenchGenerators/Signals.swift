import BenchCore
import Foundation

/// A synthetic series with a reason to exist.
///
/// Every signal here is kept for one defect it exposes. A signal that reveals nothing is data
/// volume, and data volume is not a test.
public protocol Signal: Sendable {
    /// Name, unit, valid range and provenance of the series it produces.
    var metadata: SeriesMetadata { get }
    /// Noise-free value at `seconds` after the series epoch.
    func value(at seconds: Double) -> Double
    /// Standard deviation of the noise added on top, in the series unit. Zero for exact signals.
    var noiseSigma: Double { get }
}

/// S1 — a damped oscillation on a slow drift. The well-behaved case everything should render
/// correctly, and the baseline the others are read against.
///
/// `v(t) = A·exp(−t/τ)·sin(2πf·t + φ) + B·t + C`
public struct OscillatingReaction: Signal {
    public var amplitude: Double
    /// Decay constant τ, seconds.
    public var decay: Double
    /// Oscillation frequency, hertz.
    public var frequency: Double
    /// Phase φ, radians.
    public var phase: Double
    /// Linear drift B, unit per second.
    public var drift: Double
    /// Constant offset C, in the series unit.
    public var offset: Double
    public var noiseSigma: Double

    public var metadata: SeriesMetadata {
        SeriesMetadata(
            name: "Reaction concentration",
            unit: .molesPerLitre,
            validRange: -2...2,
            provenance: .calculated
        )
    }

    public init(
        amplitude: Double = 1.0,
        decay: Double = 120,
        frequency: Double = 0.25,
        phase: Double = 0,
        drift: Double = 0.002,
        offset: Double = 0,
        noiseSigma: Double = 0.01
    ) {
        self.amplitude = amplitude
        self.decay = decay
        self.frequency = frequency
        self.phase = phase
        self.drift = drift
        self.offset = offset
        self.noiseSigma = noiseSigma
    }

    public func value(at seconds: Double) -> Double {
        amplitude * exp(-seconds / decay) * sin(2 * .pi * frequency * seconds + phase)
            + drift * seconds
            + offset
    }
}

/// S2 — a fast carrier under a slow modulation. The signal the comparison exists for.
///
/// `v(t) = A·sin(2π·f₁·t) + 0.15·A·sin(2π·f₂·t)`, with `f₁` far above what a pixel column can
/// resolve. Over a ten-second window on a 400-point axis one column spans ten carrier periods, so
/// a policy that picks representative samples flattens the envelope while one that reports extrema
/// keeps it. That difference is visible on screen, which is the point: it is an argument about
/// downsampling that does not require the reader to trust an argument.
public struct ModulatedCarrier: Signal {
    public var amplitude: Double
    /// Carrier frequency f₁, hertz.
    public var carrierFrequency: Double
    /// Modulation frequency f₂, hertz.
    public var modulationFrequency: Double
    /// Modulation depth as a fraction of `amplitude`.
    public var modulationDepth: Double
    public var noiseSigma: Double

    public var metadata: SeriesMetadata {
        SeriesMetadata(
            name: "Vibration",
            unit: .fraction,
            validRange: -2...2,
            provenance: .measured
        )
    }

    public init(
        amplitude: Double = 1.0,
        carrierFrequency: Double = 400,
        modulationFrequency: Double = 3,
        modulationDepth: Double = 0.15,
        noiseSigma: Double = 0
    ) {
        self.amplitude = amplitude
        self.carrierFrequency = carrierFrequency
        self.modulationFrequency = modulationFrequency
        self.modulationDepth = modulationDepth
        self.noiseSigma = noiseSigma
    }

    public func value(at seconds: Double) -> Double {
        amplitude * sin(2 * .pi * carrierFrequency * seconds)
            + modulationDepth * amplitude * sin(2 * .pi * modulationFrequency * seconds)
    }
}

extension Signal {
    /// Samples the signal on a regular grid.
    ///
    /// - Parameters:
    ///   - count: Samples to produce.
    ///   - sampleRateHz: Source rate. Deliberately independent of any display rate: keeping the
    ///     two apart is what the whole frame pipeline is built to handle.
    ///   - seed: Seed for the noise. The same seed produces a bit-identical series on every run.
    /// - Complexity: O(*count*).
    public func samples(count: Int, sampleRateHz: Double, seed: UInt64) -> [Sample] {
        precondition(count >= 0, "sample count cannot be negative")
        precondition(sampleRateHz > 0, "sample rate must be positive")

        var noise = GaussianNoise(seed: seed)
        var result: [Sample] = []
        result.reserveCapacity(count)
        let step = 1 / sampleRateHz

        for index in 0..<count {
            let seconds = Double(index) * step
            let clean = value(at: seconds)
            let value = noiseSigma > 0 ? clean + noiseSigma * noise.next() : clean
            result.append(Sample(carrier: seconds, value: value))
        }
        return result
    }
}

/// Seeds fixed per signal so that a run can be reproduced from the signal name alone.
public enum SignalSeed {
    public static let oscillatingReaction: UInt64 = 0x0000_0000_5243_0001
    public static let modulatedCarrier: UInt64 = 0x0000_0000_5243_0002
}
