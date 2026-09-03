import Testing
@testable import BenchCore

@Test
func sampleCarriesBothCoordinates() {
    let sample = Sample(carrier: 1_756_900_000.25, value: 3_014.5)
    #expect(sample.carrier == 1_756_900_000.25)
    #expect(sample.value == 3_014.5)
}

/// The carrier must survive present-day unix time without losing sub-second resolution. This is
/// the assertion that fails first if `Carrier` is ever narrowed to `Float`.
@Test
func carrierKeepsSubSecondResolutionAtPresentDayEpoch() {
    let base: Carrier = 1_756_900_000
    let nudged = base + 0.001
    #expect(nudged != base)
    #expect(nudged - base == 0.001)
}
