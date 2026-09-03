import BenchCore
import Testing
@testable import BenchGenerators

private func collect(_ stream: inout SignalStream, to count: Int) -> [Sample] {
    var out: [Sample] = []
    stream.advance(to: count) { out.append($0) }
    return out
}

/// The regression guard for the freeze. The demo advanced its clock only when a whole sample was
/// due, so at 100 Hz on a 120 Hz display every frame produced nothing and lost its delta — the
/// chart stopped while the overlay went on reporting 120 fps. A stream that keeps its place makes
/// the caller's arithmetic "bank the time, ask for the count", which cannot lose a remainder.
@Test
func advancingBySubSampleStepsEventuallyProducesEverySample() {
    var stream = SignalStream(signal: OscillatingReaction(noiseSigma: 0), sampleRateHz: 100, seed: 1)
    var produced = 0
    var elapsed = 0.0

    // 120 Hz frames against a 100 Hz source: every frame asks for less than one new sample.
    for _ in 0..<600 {
        elapsed += 1.0 / 120.0
        stream.advance(to: Int(elapsed * 100)) { _ in produced += 1 }
    }
    #expect(produced == Int(elapsed * 100))
    #expect(produced > 490)
    #expect(stream.producedCount == produced)
}

@Test
func askingForACountAlreadyReachedProducesNothing() {
    var stream = SignalStream(signal: ModulatedCarrier(), sampleRateHz: 1_000, seed: 2)
    #expect(collect(&stream, to: 50).count == 50)
    #expect(collect(&stream, to: 50).isEmpty)
    #expect(collect(&stream, to: 20).isEmpty)
    #expect(collect(&stream, to: 51).count == 1)
}

/// A stream's output must not depend on how many calls it took to get there. The demo's old
/// per-frame generator failed exactly this: frame boundaries decided which noise a sample got.
@Test
func outputIsIndependentOfHowTheAdvanceIsSplit() {
    var whole = SignalStream(signal: OscillatingReaction(), sampleRateHz: 100, seed: 7)
    var pieces = SignalStream(signal: OscillatingReaction(), sampleRateHz: 100, seed: 7)

    let inOneGo = collect(&whole, to: 500)
    var stepwise: [Sample] = []
    for boundary in [3, 17, 18, 200, 201, 499, 500] {
        stepwise += collect(&pieces, to: boundary)
    }

    #expect(inOneGo.count == stepwise.count)
    #expect(zip(inOneGo, stepwise).allSatisfy { $0.value.bitPattern == $1.value.bitPattern })
}

@Test
func carriersFollowTheSourceRate() {
    var stream = SignalStream(signal: ModulatedCarrier(), sampleRateHz: 5_000, seed: 3)
    let samples = collect(&stream, to: 10)
    #expect(samples[0].carrier == 0)
    #expect(abs(samples[1].carrier - 1.0 / 5_000) < 1e-15)
}

@Test
func separateStreamsWithSeparateSeedsDoNotCorrelate() {
    var first = SignalStream(signal: OscillatingReaction(), sampleRateHz: 100, seed: 10)
    var second = SignalStream(signal: OscillatingReaction(), sampleRateHz: 100, seed: 11)
    let a = collect(&first, to: 200).map(\.value)
    let b = collect(&second, to: 200).map(\.value)
    #expect(zip(a, b).contains { $0 != $1 })
}
