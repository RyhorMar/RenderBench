import BenchCore
import Foundation
import Testing
@testable import BenchGenerators

/// The property every benchmark in this repository rests on. A run that cannot be reproduced
/// cannot support a claim about a difference between runs.
@Test
func oneSeedProducesABitIdenticalSeries() {
    let signal = OscillatingReaction()
    let first = signal.samples(count: 5_000, sampleRateHz: 100, seed: SignalSeed.oscillatingReaction)
    let second = signal.samples(count: 5_000, sampleRateHz: 100, seed: SignalSeed.oscillatingReaction)

    #expect(first.count == second.count)
    #expect(zip(first, second).allSatisfy { $0.value.bitPattern == $1.value.bitPattern })
}

@Test
func differentSeedsProduceDifferentNoise() {
    let signal = OscillatingReaction()
    let first = signal.samples(count: 1_000, sampleRateHz: 100, seed: 1)
    let second = signal.samples(count: 1_000, sampleRateHz: 100, seed: 2)
    #expect(zip(first, second).contains { $0.value != $1.value })
}

@Test
func carriersAreStrictlyIncreasingAndMatchTheSourceRate() {
    let samples = OscillatingReaction().samples(count: 1_000, sampleRateHz: 250, seed: 7)
    #expect(samples[1].carrier - samples[0].carrier == 1.0 / 250.0)
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $1.carrier > $0.carrier })
}

/// Without noise the generator must be exactly the formula in its documentation, evaluated here
/// independently. A generator checked against itself proves only that it is consistent.
@Test
func noiselessOutputMatchesTheClosedForm() {
    let signal = OscillatingReaction(noiseSigma: 0)
    for index in 0..<400 {
        let t = Double(index) * 0.01
        let expected = 1.0 * exp(-t / 120) * sin(2 * .pi * 0.25 * t) + 0.002 * t
        #expect(abs(signal.value(at: t) - expected) < 1e-12)
    }
}

/// The first peak of a lightly damped quarter-hertz oscillation sits a quarter period in. Damping
/// and drift move it slightly; a shift of more than a few percent means a sign or a factor of two
/// went missing.
@Test
func firstPeakSitsAQuarterPeriodIn() {
    let signal = OscillatingReaction(noiseSigma: 0)
    var bestTime = 0.0
    var bestValue = -Double.infinity
    for index in 0...4_000 {
        let t = Double(index) * 0.001
        let value = signal.value(at: t)
        if value > bestValue {
            bestValue = value
            bestTime = t
        }
    }
    #expect(abs(bestTime - 1.0) < 0.05)
}

/// The envelope MinMax must preserve and LTTB must not. Asserted on the raw signal so that a
/// failure here separates a broken generator from a broken downsampler.
@Test
func carrierEnvelopeSpansTheFullAmplitudeWithinOneWindow() {
    let samples = ModulatedCarrier().samples(count: 50_000, sampleRateHz: 5_000, seed: SignalSeed.modulatedCarrier)
    let values = samples.map(\.value)
    let span = (values.max() ?? 0) - (values.min() ?? 0)

    #expect(span > 1.98)
    #expect(span < 2.4)
}

/// Ten carrier periods per pixel column at the documented window and axis width. If this stops
/// holding, the demonstration the signal exists for stops demonstrating anything.
@Test
func oneColumnCoversManyCarrierPeriods() {
    let signal = ModulatedCarrier()
    let windowSeconds = 10.0
    let axisPoints = 400.0
    let periodsPerColumn = signal.carrierFrequency * windowSeconds / axisPoints
    #expect(periodsPerColumn == 10)
}

@Test
func gaussianNoiseIsCentredAndScaled() {
    var noise = GaussianNoise(seed: 99)
    var sum = 0.0
    var sumOfSquares = 0.0
    let count = 100_000
    for _ in 0..<count {
        let draw = noise.next()
        sum += draw
        sumOfSquares += draw * draw
    }
    let mean = sum / Double(count)
    let variance = sumOfSquares / Double(count) - mean * mean

    #expect(abs(mean) < 0.02)
    #expect(abs(variance - 1) < 0.03)
}

@Test
func zeroSigmaAddsNothing() {
    let signal = ModulatedCarrier(noiseSigma: 0)
    let samples = signal.samples(count: 100, sampleRateHz: 1_000, seed: 5)
    for sample in samples {
        #expect(sample.value == signal.value(at: sample.carrier))
    }
}
