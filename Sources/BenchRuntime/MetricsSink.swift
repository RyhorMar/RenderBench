import Synchronization

/// Percentiles over a window of frames.
public struct FrameStatistics: Sendable, Equatable, Codable {
    /// Frames the summary was computed over.
    public let sampleCount: Int
    /// Nanoseconds.
    public let p50Ns: UInt64
    public let p95Ns: UInt64
    public let p99Ns: UInt64
    public let maxNs: UInt64

    public init(sampleCount: Int, p50Ns: UInt64, p95Ns: UInt64, p99Ns: UInt64, maxNs: UInt64) {
        self.sampleCount = sampleCount
        self.p50Ns = p50Ns
        self.p95Ns = p95Ns
        self.p99Ns = p99Ns
        self.maxNs = maxNs
    }
}

/// Collects per-frame records and is the only place percentiles are computed.
///
/// Both the on-screen overlay and the benchmark runner read from here and neither calculates
/// anything of its own. Two implementations of "p95" disagreeing by a rounding rule is not a
/// hypothetical: it is how a HUD ends up contradicting the results file it was supposed to
/// illustrate.
///
/// Percentiles use nearest-rank — the smallest value at or below which at least *p* percent of
/// observations fall, with no interpolation. Stated because the alternatives differ by a whole
/// frame on a hundred-sample window, and a table that does not say which it used cannot be
/// compared with anything.
///
/// - SeeAlso: Docs/methods/frame-statistics.md — why nearest-rank, and what a percentile over
///   this window does not tell you.
public final class MetricsSink: Sendable {
    private struct Storage {
        var frames: [FrameMetrics]
        var head: Int
        var count: Int
    }

    /// Frames retained. Older records are overwritten.
    public let capacity: Int
    private let storage: Mutex<Storage>

    /// - Parameter capacity: Frames kept. The default holds twenty seconds at 120 Hz, which is
    ///   long enough to cover a benchmark case and short enough that a thermal shift partway
    ///   through shows up as a change rather than being averaged away.
    public init(capacity: Int = 2_400) {
        precondition(capacity > 0, "MetricsSink needs a positive capacity")
        self.capacity = capacity
        self.storage = Mutex(Storage(frames: [], head: 0, count: 0))
    }

    /// Records one frame.
    ///
    /// - Complexity: O(1) amortised. Safe to call from the frame tick.
    public func record(_ metrics: FrameMetrics) {
        storage.withLock { state in
            if state.frames.count < capacity {
                state.frames.append(metrics)
            } else {
                state.frames[state.head] = metrics
            }
            state.head = (state.head + 1) % capacity
            state.count = Swift.min(state.count + 1, capacity)
        }
    }

    /// Frames currently retained.
    public var count: Int { storage.withLock { $0.count } }

    /// Every retained record, oldest first.
    public func snapshot() -> [FrameMetrics] {
        storage.withLock { state in
            guard state.count == capacity else { return state.frames }
            return Array(state.frames[state.head...]) + Array(state.frames[..<state.head])
        }
    }

    /// Everything the overlay and a results file need, from one pass over one lock acquisition.
    ///
    /// Grouped because the alternative was three separate calls, each copying the whole ring under
    /// the lock — three times the allocation, three times the time spent blocking `record` from
    /// the frame path, and three chances for the figures to describe different windows.
    public struct Summary: Sendable, Equatable {
        /// Preparation plus geometry building. **Not a frame time**: it excludes rasterisation on
        /// every backend that cannot observe its own drawing.
        public let cpu: FrameStatistics?
        /// The backend's own drawing, where it could time it. `nil` for a retained-mode backend,
        /// whose tessellation and compositing happen in another process.
        public let raster: FrameStatistics?
        public let gpu: FrameStatistics?
        /// `nil` when no retained frame reported a presentation time — unknowable, not zero.
        public let missedDeadlineRatio: Double?
    }

    /// Percentiles of CPU and GPU frame time and the missed-deadline share, over one window.
    ///
    /// - Complexity: O(*n* log *n*) in the retained frames, one lock acquisition, two `UInt64`
    ///   vectors rather than a copy of the records themselves.
    public func summary(frameBudgetSeconds: Double) -> Summary {
        var cpuValues: [UInt64] = []
        var rasterValues: [UInt64] = []
        var gpuValues: [UInt64] = []
        var missed = 0
        var judged = 0

        storage.withLock { state in
            cpuValues.reserveCapacity(state.count)
            for offset in 0..<state.count {
                let metrics = state.frames[self.index(of: offset, in: state)]
                cpuValues.append(metrics.cpuPrepareAndEncodeNs)
                if let raster = metrics.rasterNs { rasterValues.append(raster) }
                if let gpu = metrics.gpuNs { gpuValues.append(gpu) }
                if let late = metrics.missedDeadline(frameBudgetSeconds: frameBudgetSeconds) {
                    judged += 1
                    if late { missed += 1 }
                }
            }
        }

        return Summary(
            cpu: statistics(of: cpuValues),
            raster: statistics(of: rasterValues),
            gpu: statistics(of: gpuValues),
            missedDeadlineRatio: judged > 0 ? Double(missed) / Double(judged) : nil
        )
    }

    /// Percentiles of preparation plus geometry building.
    ///
    /// Not a frame time. See ``Summary/cpu``.
    public func cpuStatistics() -> FrameStatistics? {
        summary(frameBudgetSeconds: .infinity).cpu
    }

    /// Percentiles of the backend's own drawing, over the frames that reported it.
    public func rasterStatistics() -> FrameStatistics? {
        summary(frameBudgetSeconds: .infinity).raster
    }

    /// Percentiles of GPU frame time, over the frames that reported one.
    ///
    /// Returns `nil` when no frame reported GPU time rather than zero: a CPU backend has no GPU
    /// interval, and a zero here would win every comparison it appears in.
    public func gpuStatistics() -> FrameStatistics? {
        summary(frameBudgetSeconds: .infinity).gpu
    }

    /// Share of retained frames that missed their deadline, over the frames that could tell.
    ///
    /// `nil` when no frame reported a presentation time.
    public func missedDeadlineRatio(frameBudgetSeconds: Double) -> Double? {
        summary(frameBudgetSeconds: frameBudgetSeconds).missedDeadlineRatio
    }

    /// Position in the backing array of the record `offset` places after the oldest.
    private func index(of offset: Int, in state: Storage) -> Int {
        state.count == capacity ? (state.head + offset) % capacity : offset
    }

    public func removeAll() {
        storage.withLock { state in
            state.frames.removeAll(keepingCapacity: true)
            state.head = 0
            state.count = 0
        }
    }

    private func statistics(of values: [UInt64]) -> FrameStatistics? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return FrameStatistics(
            sampleCount: sorted.count,
            p50Ns: Self.nearestRank(sorted, percentile: 50),
            p95Ns: Self.nearestRank(sorted, percentile: 95),
            p99Ns: Self.nearestRank(sorted, percentile: 99),
            maxNs: sorted[sorted.count - 1]
        )
    }

    /// Nearest-rank percentile of an already-sorted vector.
    ///
    /// - Precondition: `sorted` is non-empty and ascending.
    static func nearestRank(_ sorted: [UInt64], percentile: Double) -> UInt64 {
        let rank = Int((percentile / 100 * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(1, Swift.min(rank, sorted.count)) - 1]
    }
}
