import BenchTestSupport
import Testing
@testable import BenchScales

private let measurer = FixedMetrics(pointsPerCharacter: 7.0)

@Test
func ticksFallOnClockDivisions() {
    let scale = TimeScale(domain: 0...60)
    let step = TimeScale.ladderStep(forSpan: 60, targetCount: 6)
    let values = scale.ticks(target: 6, axisLength: 600, orientation: .horizontal, measuring: measurer).map(\.value)

    #expect(TimeScale.ladder.contains(step))
    #expect(values.first == 0)
    #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: step) == 0 })
}

/// 2.5 seconds is a fine decimal step and a nonsense clock division. Every step must come from
/// the ladder — including the sub-second rungs, which the previous version of this test declared
/// impossible and then avoided by starting its window list at ten seconds.
@Test
func everyStepComesFromTheLadder() {
    for span in [0.5, 1.0, 3.0, 10.0, 45.0, 200.0, 5_000.0, 90_000.0] {
        let step = TimeScale.ladderStep(forSpan: span, targetCount: 6)
        #expect(step > 0)
        let onLadder = TimeScale.ladder.contains(step)
        let wholeDays = step.truncatingRemainder(dividingBy: 86_400) == 0
        #expect(onLadder || wholeDays, "span \(span) produced step \(step)")
    }
}

/// A one-second window is the reference chart's shortest. With a one-second floor on the ladder
/// it got two labels, which is an axis with endpoints rather than an axis.
@Test
func aOneSecondWindowIsLabelledInTenths() {
    let ticks = TimeScale(domain: 0...1).ticks(
        target: 6,
        axisLength: 600,
        orientation: .horizontal,
        measuring: measurer
    )
    #expect(ticks.count >= 5)
    #expect(ticks.contains { $0.label.contains(".") })
}

/// Formatting converts seconds to an integer. A domain past that range is an empty axis, not a
/// trap: a caller charting nanosecond-epoch values has made a unit mistake, and a crash is not
/// how they should find out.
@Test
func aDomainTooLargeToLabelYieldsNoTicksInsteadOfTrapping() {
    for upper in [1e19, 4e18, Double.greatestFiniteMagnitude] {
        let ticks = TimeScale(domain: 0...upper).ticks(
            target: 6,
            axisLength: 400,
            orientation: .horizontal,
            measuring: measurer
        )
        #expect(ticks.isEmpty, "domain 0...\(upper) should not be labelled")
    }
}

@Test
func labelResolutionMatchesTheSpacing() {
    #expect(TimeScale.label(forSecond: 3_661, offset: 0, step: 1) == "01:01:01")
    #expect(TimeScale.label(forSecond: 3_661, offset: 0, step: 300) == "01:01")
    #expect(TimeScale.label(forSecond: 90_000, offset: 0, step: 86_400) == "d1")
}

@Test
func zoneOffsetIsCarriedNotInherited() {
    let utc = TimeScale.label(forSecond: 0, offset: 0, step: 60)
    let plusThree = TimeScale.label(forSecond: 0, offset: 10_800, step: 60)
    #expect(utc == "00:00")
    #expect(plusThree == "03:00")
}

/// One second, one minute and one hour must all produce a legible number of labels. The exact
/// count is allowed to change with the window; what is not allowed is an axis with two labels or
/// with forty.
@Test
func labelCountStaysInABandAcrossThreeOrdersOfMagnitude() {
    for span in [1.0, 60.0, 3_600.0] {
        let scale = TimeScale(domain: 0...span)
        let count = scale.ticks(target: 6, axisLength: 600, orientation: .horizontal, measuring: measurer).count
        #expect(count >= 3)
        #expect(count <= 14)
    }
}

@Test
func windowLongerThanADayStillTerminates() {
    let scale = TimeScale(domain: 0...(86_400 * 30))
    let ticks = scale.ticks(target: 6, axisLength: 600, orientation: .horizontal, measuring: measurer)
    #expect(ticks.isEmpty == false)
    #expect(ticks.count < 100)
}
