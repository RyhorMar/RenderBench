import QuartzCore
import Testing
@testable import BenchRuntime

/// The whole mapping, as a table. Four rows because two facts decide it: what the display can do,
/// and whether the bundle unlocked the range at all.
@Test
func theRequestedRangeFollowsTheDisplayAndTheOptIn() {
    let proMotion = FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                     optedInToHighFrameRate: true)
    #expect(proMotion.range.minimum == 60)
    #expect(proMotion.range.maximum == 120)
    #expect(proMotion.range.preferred == 120)
    #expect(proMotion.optInMissing == false)

    let capped = FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                  optedInToHighFrameRate: false)
    #expect(capped.range.maximum == 60, "asked for what the build cannot deliver")
    #expect(capped.optInMissing)

    let plain = FrameRateRequest(displayMaximumFramesPerSecond: 60,
                                 optedInToHighFrameRate: true)
    #expect(plain.range.maximum == 60)
    #expect(plain.optInMissing == false)
}

/// On a display that cannot exceed 60 the opt-in unlocks nothing, so its absence is not a
/// shortfall. Reporting one would put a red row on a screen where nothing is wrong.
@Test
func theOptInIsNotMissedOnADisplayThatCannotUseIt() {
    let plain = FrameRateRequest(displayMaximumFramesPerSecond: 60,
                                 optedInToHighFrameRate: false)
    #expect(plain.optInMissing == false)
    #expect(plain.range.maximum == 60)
}

/// The value the accepted measurement was taken under, pinned by a test so it cannot change in
/// passing. A different range is a different run condition, and the file already in
/// `Benchmarks/results/` was recorded under this one.
@Test
func theProMotionRangeIsTheOneTheStoredResultWasMeasuredUnder() {
    let request = FrameRateRequest(displayMaximumFramesPerSecond: 120,
                                   optedInToHighFrameRate: true)
    #expect(request.range == CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120))
}

/// A caller that could not read the screen passes something below 60. No iOS display is slower,
/// so the honest reading of such a number is "unknown", and 60 is what every display can do.
@Test
func aDisplayRateBelowSixtyIsTreatedAsSixty() {
    let unknown = FrameRateRequest(displayMaximumFramesPerSecond: 0,
                                   optedInToHighFrameRate: true)
    #expect(unknown.range.maximum == 60)
    #expect(unknown.range.minimum == 60)
}
