import BenchCore
import Foundation

/// What one tick asks the caller to do.
public struct FramePlan: Sendable, Equatable {
    /// Carrier range that should be on screen.
    public let window: ClosedRange<Carrier>
    /// Total samples the source should have produced by now, counting from the run's start.
    ///
    /// A count rather than a delta: the caller advances its generators *to* this number, so a
    /// frame shorter than one sample period cannot lose its remainder — it simply asks for the
    /// same count again, and the next frame asks for one more.
    public let samplesDue: Int
    /// The snapshot to draw, already checked against the current configuration.
    public let snapshot: FrameSnapshot
}

/// The part of a frame that is not drawing: banking time, deciding the window, publishing a
/// snapshot and taking it back, and remembering when the run began.
///
/// It lives here rather than in an application for one reason worth stating: the first version of
/// this logic was written inside a SwiftUI view model, where it could not be tested, and three
/// separate defects lived in it — a lost frame remainder that froze the chart on a 120 Hz display,
/// an epoch that never advanced on a configuration change, and a generator reseeded per frame. All
/// three are now unit tests, and the second backend will inherit the fixed version instead of
/// copying the broken one.
@MainActor
public final class FramePipeline {
    /// Seconds of history on screen.
    public let windowSeconds: Double
    /// Rate the source produces samples at, independent of any display rate.
    public private(set) var sampleRateHz: Double

    /// Seconds of run time banked so far.
    public private(set) var elapsed: Double = 0
    /// Generation of the configuration. A snapshot from an older one is discarded, not drawn.
    public private(set) var epoch: UInt64 = 1
    /// Frames handed back to the caller to draw.
    public private(set) var framesPlanned: UInt64 = 0

    /// When the current run began, and the thermal state at that moment.
    ///
    /// Captured at ``beginRun()`` rather than at construction: a scene object outlives a run, and
    /// a results file that recorded application launch time as the run's start would misattribute
    /// every thermal comparison made from it.
    public private(set) var runStartedAt: Date
    public private(set) var thermalStateAtStart: ThermalState

    private let slot = FrameSlot()
    private var lastTickTimestamp: Double?

    public init(windowSeconds: Double, sampleRateHz: Double) {
        precondition(windowSeconds > 0, "a window needs a positive extent")
        precondition(sampleRateHz > 0, "a source needs a positive rate")
        self.windowSeconds = windowSeconds
        self.sampleRateHz = sampleRateHz
        self.runStartedAt = Date()
        self.thermalStateAtStart = ThermalState(ProcessInfo.processInfo.thermalState)
    }

    /// Marks the start of a run: resets the clock, the counters and the recorded conditions.
    public func beginRun(sampleRateHz: Double? = nil) {
        if let sampleRateHz {
            precondition(sampleRateHz > 0, "a source needs a positive rate")
            self.sampleRateHz = sampleRateHz
        }
        elapsed = 0
        framesPlanned = 0
        lastTickTimestamp = nil
        runStartedAt = Date()
        thermalStateAtStart = ThermalState(ProcessInfo.processInfo.thermalState)
        invalidateConfiguration()
    }

    /// Declares that anything a prepared snapshot describes has changed — the window, the series
    /// set, the downsampling policy.
    ///
    /// Cheap, and forgetting it is expensive: a snapshot prepared under the previous configuration
    /// is correct data answering a question nobody is asking, and drawing it puts one frame of the
    /// old picture inside the new one.
    public func invalidateConfiguration() {
        epoch &+= 1
    }

    /// Fills the window once, before the first frame, so a chart opens with data rather than an
    /// empty axis.
    ///
    /// - Returns: the sample count the caller should advance its sources to.
    public func prime() -> Int {
        elapsed = windowSeconds
        return samplesDue
    }

    /// Banks this tick's elapsed time and returns what to draw.
    ///
    /// Time is banked **unconditionally**, before any decision about whole samples. Advancing only
    /// when at least one sample is due discards every frame shorter than a sample period — at
    /// 100 Hz on a 120 Hz display that is every frame, so the clock never moves and the chart
    /// freezes while the overlay reports a healthy frame rate.
    ///
    /// - Returns: `nil` when the snapshot was superseded before it could be taken.
    public func advance(tick: FrameTick) -> FramePlan? {
        if let previous = lastTickTimestamp {
            let delta = tick.timestamp - previous
            if delta > 0 { elapsed += delta }
        }
        lastTickTimestamp = tick.timestamp

        let upper = max(elapsed, minimumWindowExtent)
        let window = max(0, upper - windowSeconds)...upper
        let due = samplesDue

        slot.publish(
            FrameSnapshot(frameID: tick.frameID, epoch: epoch, window: window, pointCount: due)
        )
        guard let snapshot = slot.take(epoch: epoch) else { return nil }
        framesPlanned &+= 1
        return FramePlan(window: window, samplesDue: due, snapshot: snapshot)
    }

    /// Snapshots produced, delivered and dropped.
    public var counters: SlotCounters { slot.counters }

    /// Samples the source should have produced by now.
    public var samplesDue: Int { Int(elapsed * sampleRateHz) }

    /// A window needs a non-empty extent even before any time has passed, or every scale built
    /// from it collapses and reports itself out of domain.
    private var minimumWindowExtent: Double { 1.0 / sampleRateHz }
}
