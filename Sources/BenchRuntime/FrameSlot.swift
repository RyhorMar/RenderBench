import Synchronization

/// What the producer hands the renderer for one frame.
public struct FrameSnapshot: Sendable, Equatable {
    /// Frame number this snapshot was prepared for.
    public let frameID: UInt64
    /// Generation of the configuration it was prepared under.
    ///
    /// Changing the window, the series set or the downsampling policy bumps the epoch. A snapshot
    /// from an older epoch is discarded rather than drawn: it is correct data answering a question
    /// nobody is asking any more, and drawing it produces one frame of the previous configuration
    /// mixed into the new one.
    public let epoch: UInt64
    /// Carrier window the snapshot covers.
    public let window: ClosedRange<Double>
    /// Points the renderer is expected to draw from it.
    public let pointCount: Int

    public init(frameID: UInt64, epoch: UInt64, window: ClosedRange<Double>, pointCount: Int) {
        self.frameID = frameID
        self.epoch = epoch
        self.window = window
        self.pointCount = pointCount
    }
}

/// How many frames the producer made, the renderer took, and nobody ever saw.
public struct SlotCounters: Sendable, Equatable {
    /// Snapshots published by the producer.
    public var produced: UInt64 = 0
    /// Snapshots taken by a renderer.
    public var delivered: UInt64 = 0
    /// Snapshots overwritten before anyone took them.
    public var dropped: UInt64 = 0
    /// Snapshots discarded for belonging to a superseded configuration.
    public var staleEpoch: UInt64 = 0

    public init() {}
}

/// A one-deep mailbox holding the newest snapshot, with a count of what it discarded.
///
/// Deliberately lossy: a renderer that falls behind wants the current state of the world, not a
/// queue of stale ones. What makes it honest rather than merely convenient is `dropped` — the same
/// structure without that counter is the thing people call back-pressure when it is nothing of the
/// sort. Back-pressure slows the producer down. This does not; it tells you how often it didn't.
///
/// A lossless record, when one is needed, is a second channel, not a deeper queue here.
/// - SeeAlso: Docs/methods/frame-pipeline.md
public final class FrameSlot: Sendable {
    /// The snapshot and the counters describing it, under one lock.
    ///
    /// One `Mutex`, not two. With the slot and the tally locked separately a reader could observe
    /// a delivery that had not been produced yet — the producer having released the slot lock
    /// before incrementing its counter — and a results file computed from that pair reports a
    /// drop ratio built from two different instants.
    private struct State {
        var pending: FrameSnapshot?
        var counters = SlotCounters()
    }

    private let state = Mutex<State>(State())

    public init() {}

    /// Publishes a snapshot, replacing any the renderer has not taken.
    public func publish(_ snapshot: FrameSnapshot) {
        state.withLock { state in
            if state.pending != nil { state.counters.dropped &+= 1 }
            state.pending = snapshot
            state.counters.produced &+= 1
        }
    }

    /// Takes the pending snapshot, if it belongs to the current configuration.
    ///
    /// - Parameter epoch: Generation the caller is prepared to draw. Snapshots from an older one
    ///   are discarded and counted, never returned.
    public func take(epoch: UInt64) -> FrameSnapshot? {
        state.withLock { state in
            guard let taken = state.pending else { return nil }
            state.pending = nil
            guard taken.epoch == epoch else {
                state.counters.staleEpoch &+= 1
                return nil
            }
            state.counters.delivered &+= 1
            return taken
        }
    }

    /// Current counts, consistent with each other and with the slot they describe.
    public var counters: SlotCounters {
        state.withLock { $0.counters }
    }
}
