import Testing
@testable import BenchRuntime

/// A steady stream reads back as its own rate.
@Test
func aSteadyStreamReportsItsRate() {
    var meter = FrameRateMeter()
    var time = 0.0
    for _ in 0..<121 {
        meter.record(timestamp: time)
        time += 1.0 / 120
    }
    let rate = meter.rate
    #expect(rate != nil)
    #expect((118.0...122.0).contains(rate ?? 0), "read \(String(describing: rate))")
}

/// The defect this meter exists to remove, written as numbers.
///
/// Seventy-three frames in the second, and the last gap happens to be a full-rate one. An
/// instantaneous reading — one over the gap between the last two marks — answers 120. Measured on
/// a device on 10 September 2026, that is exactly what the overlay reported for a backend
/// sustaining 73 frames a second.
@Test
func aFullRateGapAtTheEndDoesNotMakeTheWindowFast() {
    var marks: [Double] = []
    var time = 0.0
    for _ in 0..<73 {
        marks.append(time)
        time += 1.0 / 73
    }
    marks.append(marks[marks.count - 1] + 1.0 / 120)

    var meter = FrameRateMeter()
    for mark in marks { meter.record(timestamp: mark) }

    let instantaneous = 1.0 / (marks[marks.count - 1] - marks[marks.count - 2])
    #expect((119.0...121.0).contains(instantaneous), "the trap this test sets is not set")

    let rate = meter.rate
    #expect((70.0...77.0).contains(rate ?? 0), "read \(String(describing: rate))")
}

/// Marks older than the window are not counted, so a run that slowed down reads as slow rather
/// than as the average of what it used to be.
@Test
func marksOlderThanTheWindowAreForgotten() {
    var meter = FrameRateMeter(window: 1.0)
    var time = 0.0
    for _ in 0..<120 {
        meter.record(timestamp: time)
        time += 1.0 / 120
    }
    // Three seconds later, two marks a quarter of a second apart: four frames a second.
    meter.record(timestamp: time + 3.0)
    meter.record(timestamp: time + 3.25)
    let rate = meter.rate
    #expect((3.0...5.0).contains(rate ?? 0), "read \(String(describing: rate))")
}

/// A gap longer than the window leaves one mark, and one mark is not a rate.
///
/// `nil`, not the last known value: in this project an absent reading means "cannot report", and
/// holding a stale number here is the very thing being fixed.
@Test
func aPauseLongerThanTheWindowReportsNothing() {
    var meter = FrameRateMeter(window: 1.0)
    meter.record(timestamp: 0)
    meter.record(timestamp: 1.0 / 120)
    #expect(meter.rate != nil)
    meter.record(timestamp: 5.0)
    #expect(meter.rate == nil)
}

/// A meter that has seen one mark, or none, reports nothing rather than zero.
@Test
func fewerThanTwoMarksReportNothing() {
    var empty = FrameRateMeter()
    #expect(empty.rate == nil)
    empty.record(timestamp: 0)
    #expect(empty.rate == nil)
}
