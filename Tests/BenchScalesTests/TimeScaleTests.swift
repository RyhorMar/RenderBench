import Testing
@testable import BenchScales

private struct FixedWidth: TextMeasuring {
    func width(of text: String) -> Double { Double(text.count) * 7.0 }
}

@Test
func ticksFallOnClockDivisions() {
    let scale = TimeScale(domain: 0...60)
    let step = TimeScale.ladderStep(forSpan: 60, targetCount: 6)
    let values = scale.ticks(target: 6, axisLength: 600, measuring: FixedWidth()).map(\.value)

    #expect(TimeScale.ladder.contains(step))
    #expect(values.first == 0)
    #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: step) == 0 })
}

/// 2.5 is a fine decimal step and a nonsense clock division. The ladder exists to keep it out.
@Test
func decimalStepsNeverReachATimeAxis() {
    for span in [10.0, 45.0, 200.0, 5_000.0, 90_000.0] {
        let step = TimeScale.ladderStep(forSpan: span, targetCount: 6)
        #expect(step > 0)
        #expect(step.truncatingRemainder(dividingBy: 1) == 0)
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
        let count = scale.ticks(target: 6, axisLength: 600, measuring: FixedWidth()).count
        #expect(count >= 3)
        #expect(count <= 14)
    }
}

@Test
func windowLongerThanADayStillTerminates() {
    let scale = TimeScale(domain: 0...(86_400 * 30))
    let ticks = scale.ticks(target: 6, axisLength: 600, measuring: FixedWidth())
    #expect(ticks.isEmpty == false)
    #expect(ticks.count < 100)
}
