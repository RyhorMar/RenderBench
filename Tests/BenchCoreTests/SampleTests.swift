import Testing
@testable import BenchCore

@Test
func sampleCarriesBothCoordinates() {
    let sample = Sample(carrier: 1_756_900_000.25, value: 3_014.5)
    #expect(sample.carrier == 1_756_900_000.25)
    #expect(sample.value == 3_014.5)
}

/// The reason the carrier is `Double`. At present-day unix time the spacing between representable
/// values is a few hundred nanoseconds here and about two minutes in `Float`; a running window
/// built on the latter quantises into visible steps. Exact equality is not the claim — no binary
/// float represents a millisecond exactly at this magnitude — the claim is that the error stays
/// far below anything a frame can resolve.
@Test
func carrierResolvesMillisecondsAtPresentDayEpoch() {
    let base: Carrier = 1_756_900_000
    let nudged = base + 0.001

    #expect(nudged != base)
    #expect(abs((nudged - base) - 0.001) < 1e-6)
    #expect(base.ulp < 1e-6)
    #expect(Float(base).ulp > 100)
}
