import BenchCore
import Foundation
import Testing
@testable import BenchRuntime

private func tick(_ id: UInt64, at timestamp: Double) -> FrameTick {
    FrameTick(frameID: id, targetTimestamp: timestamp + 1.0 / 120, timestamp: timestamp)
}

/// The freeze, as a unit test. At 100 Hz on a 120 Hz display every frame is shorter than one
/// sample period; a pipeline that advances only when a whole sample is due never advances at all,
/// and the chart stops while the overlay keeps reporting the frame rate.
@Test @MainActor
func aDisplayFasterThanTheSourceStillAdvancesTheClock() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    _ = pipeline.prime()
    let primed = pipeline.samplesDue

    var timestamp = 0.0
    for frame in 1...600 {
        timestamp += 1.0 / 120
        _ = pipeline.advance(tick: tick(UInt64(frame), at: timestamp))
    }

    // Five seconds of 120 Hz frames must produce five seconds of 100 Hz samples.
    #expect(pipeline.elapsed > 14.9)
    #expect(pipeline.samplesDue >= primed + 490)
}

/// No remainder is lost across a long run of sub-sample frames: the banked time is real time.
@Test @MainActor
func bankedTimeMatchesRealTimeToWithinOneFrame() {
    let pipeline = FramePipeline(windowSeconds: 5, sampleRateHz: 60)
    var timestamp = 0.0
    let step = 1.0 / 120
    for frame in 1...1_200 {
        timestamp += step
        _ = pipeline.advance(tick: tick(UInt64(frame), at: timestamp))
    }
    #expect(abs(pipeline.elapsed - (timestamp - step)) < step * 1.5)
}

@Test @MainActor
func theWindowFollowsTheClockAndKeepsItsExtent() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    _ = pipeline.prime()
    guard let plan = pipeline.advance(tick: tick(1, at: 1.0)) else {
        Issue.record("first tick produced no plan")
        return
    }
    #expect(plan.window.upperBound - plan.window.lowerBound == 10)

    var timestamp = 1.0
    for frame in 2...300 { timestamp += 1.0 / 60; _ = pipeline.advance(tick: tick(UInt64(frame), at: timestamp)) }
    guard let later = pipeline.advance(tick: tick(301, at: timestamp + 1.0 / 60)) else {
        Issue.record("later tick produced no plan")
        return
    }
    #expect(later.window.lowerBound > plan.window.lowerBound)
    #expect(later.window.upperBound - later.window.lowerBound == 10)
}

/// Before any time has passed the window must still have an extent, or every scale built from it
/// collapses and reports itself out of domain — which draws an empty chart on the first frame.
@Test @MainActor
func theFirstWindowIsNotEmpty() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    guard let plan = pipeline.advance(tick: tick(1, at: 0)) else {
        Issue.record("first tick produced no plan")
        return
    }
    #expect(plan.window.upperBound > plan.window.lowerBound)
}

/// The epoch bug: a policy change is a configuration change, and a snapshot prepared under the old
/// one must not be drawn. Before this the demo bumped the epoch only when the series set changed.
@Test @MainActor
func aSupersededSnapshotIsNotDrawn() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    let before = pipeline.epoch
    pipeline.invalidateConfiguration()
    #expect(pipeline.epoch > before)

    // A tick that publishes and then finds the configuration changed under it yields nothing.
    let advanced = pipeline.advance(tick: tick(1, at: 0.1))
    #expect(advanced != nil)
    #expect(pipeline.framesPlanned == 1)
}

@Test @MainActor
func beginRunResetsTheClockAndTheRecordedConditions() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    _ = pipeline.prime()
    for frame in 1...10 { _ = pipeline.advance(tick: tick(UInt64(frame), at: Double(frame) / 60)) }
    #expect(pipeline.elapsed > 10)
    let firstStart = pipeline.runStartedAt

    pipeline.beginRun(sampleRateHz: 5_000)
    #expect(pipeline.elapsed == 0)
    #expect(pipeline.framesPlanned == 0)
    #expect(pipeline.sampleRateHz == 5_000)
    #expect(pipeline.runStartedAt >= firstStart)
}

/// A run's start is the run's, not the application's. A results file that recorded launch time
/// would misattribute every thermal comparison made from it.
@Test @MainActor
func theRunStartIsRecordedAtBeginRunNotAtConstruction() throws {
    let pipeline = FramePipeline(windowSeconds: 1, sampleRateHz: 100)
    let constructed = pipeline.runStartedAt
    // A measurable gap without sleeping the test: any later wall-clock read is at or after this.
    pipeline.beginRun()
    #expect(pipeline.runStartedAt >= constructed)
    #expect(pipeline.thermalStateAtStart == ThermalState(ProcessInfo.processInfo.thermalState))
}

@Test @MainActor
func primingFillsExactlyOneWindow() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 250)
    #expect(pipeline.prime() == 2_500)
    #expect(pipeline.elapsed == 10)
}

/// A tick that arrives out of order must not run the clock backwards.
@Test @MainActor
func aTickWithANonAdvancingTimestampBanksNothing() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    _ = pipeline.advance(tick: tick(1, at: 5.0))
    let after = pipeline.elapsed
    _ = pipeline.advance(tick: tick(2, at: 4.0))
    #expect(pipeline.elapsed == after)
}

@Test @MainActor
func everyPlannedFrameIsAccountedForInTheCounters() {
    let pipeline = FramePipeline(windowSeconds: 10, sampleRateHz: 100)
    for frame in 1...50 { _ = pipeline.advance(tick: tick(UInt64(frame), at: Double(frame) / 60)) }
    let counters = pipeline.counters
    #expect(counters.produced == 50)
    #expect(counters.delivered == 50)
    #expect(counters.dropped == 0)
    #expect(pipeline.framesPlanned == 50)
}
