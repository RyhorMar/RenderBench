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
public final class FrameSlot: Sendable {
    private let storage = Mutex<FrameSnapshot?>(nil)
    private let tally = Mutex<SlotCounters>(SlotCounters())

    public init() {}

    /// Publishes a snapshot, replacing any the renderer has not taken.
    public func publish(_ snapshot: FrameSnapshot) {
        let replaced = storage.withLock { slot -> Bool in
            let hadUntaken = slot != nil
            slot = snapshot
            return hadUntaken
        }
        tally.withLock { counters in
            counters.produced &+= 1
            if replaced { counters.dropped &+= 1 }
        }
    }

    /// Takes the pending snapshot, if it belongs to the current configuration.
    ///
    /// - Parameter epoch: Generation the caller is prepared to draw. Snapshots from an older one
    ///   are discarded and counted, never returned.
    public func take(epoch: UInt64) -> FrameSnapshot? {
        let taken = storage.withLock { slot -> FrameSnapshot? in
            defer { slot = nil }
            return slot
        }
        guard let taken else { return nil }
        guard taken.epoch == epoch else {
            tally.withLock { $0.staleEpoch &+= 1 }
            return nil
        }
        tally.withLock { $0.delivered &+= 1 }
        return taken
    }

    /// Current counts.
    public var counters: SlotCounters {
        tally.withLock { $0 }
    }
}
