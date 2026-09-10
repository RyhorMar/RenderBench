import Testing
@testable import RenderBenchDemo

/// The word is written out here, not read back from ``HUDFormat``, so that the overlay cannot drift
/// back to a dash without this failing. A dash was what it printed before: it looks tidy and it
/// answers none of the three questions a reader has — cannot report, nothing measured yet, or
/// somebody's placeholder.
@Test
func anAbsentReadingIsTheWordNil() {
    #expect(HUDFormat.absent == "nil")
    #expect(HUDFormat.count(nil) == "nil")
    #expect(HUDFormat.milliseconds(nil) == "nil")
}

/// The other half of the rule, and the one that would rot quietly: zero is a measurement. A backend
/// that counted no dropped frames says so, and turning that into absence would hide the good case.
@Test
func zeroIsAMeasurementAndStaysOne() {
    #expect(HUDFormat.count(0) == "0")
    #expect(HUDFormat.milliseconds(0) == "0.00 ms")
}

/// Nanoseconds in, milliseconds on screen. The overlay reads the same sink as the results file, so a
/// wrong scale here would put a figure next to the chart that no file agrees with.
@Test
func readingsAreScaledFromNanosecondsToMilliseconds() {
    #expect(HUDFormat.milliseconds(1_234_567) == "1.23 ms")
    #expect(HUDFormat.milliseconds(16_700_000) == "16.70 ms")
}
