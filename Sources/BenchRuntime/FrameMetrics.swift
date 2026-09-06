/// What one frame cost.
///
/// Every duration is nanoseconds and every field says so, because the single most common way to
/// get a frame-time table wrong is to mix milliseconds into it silently. Optionals are not
/// "missing data": they mark quantities a given backend genuinely cannot report, and a backend
/// must leave them `nil` rather than substitute a plausible number.
public struct FrameMetrics: Sendable, Equatable, Codable {
    /// Frame this record describes.
    public var frameID: UInt64
    /// Preparing data for the frame — windowing and downsampling. Nanoseconds.
    public var cpuPrepareNs: UInt64
    /// Encoding draw work. Nanoseconds.
    public var cpuEncodeNs: UInt64
    /// Time the backend's own drawing took, in nanoseconds — rasterising, not preparing.
    ///
    /// `nil` when the backend cannot report it, and that is the common case rather than the
    /// exception. An immediate-mode backend can time the inside of its draw callback, one frame
    /// late. A retained-mode one cannot: its tessellation and compositing happen in the render
    /// server, in another process, and nothing in this package can observe them. For those,
    /// `presentedTime` and the missed-deadline ratio are the only honest measurements.
    ///
    /// **`cpuPrepareNs + cpuEncodeNs` is not a frame's cost.** It is what the preparation and the
    /// geometry building cost. Publishing it as a rendering method's frame time — which this
    /// package did until this field existed — omits the rendering.
    public var rasterNs: UInt64?
    /// GPU execution, from the command buffer's own timestamps. Nanoseconds.
    ///
    /// `nil` on every CPU path. A Canvas backend has no GPU interval to report, and writing zero
    /// there would make it look infinitely fast in exactly the column readers compare.
    public var gpuNs: UInt64?
    /// When the frame actually appeared, in seconds on the host clock. `nil` when the backend
    /// cannot observe presentation.
    public var presentedTime: Double?
    /// When it was expected to appear, in seconds on the host clock.
    public var targetTimestamp: Double
    /// Samples handed to the backend after downsampling.
    public var pointsSubmitted: Int
    /// Samples the backend actually drew. Divergence from `pointsSubmitted` is the signal that a
    /// backend is buying its frame time by dropping work.
    ///
    /// `nil` when the backend cannot say — a declarative view built from data has no notion of
    /// "samples drawn" to report, and that is a fact about the method, not a missing measurement.
    /// Zero is a different claim: that the backend counted and found none.
    public var pointsDrawn: Int?
    /// Draw calls issued.
    ///
    /// `nil` when a backend cannot count them — most notably a retained-mode backend that hands a
    /// layer tree to a render server deciding its own submissions on its own thread. `nil` also
    /// when the backend that would draw has no device to draw with at all: a host that cannot
    /// draw must not report the fastest row in the table.
    public var drawCalls: Int?

    /// CPU cost of preparing and encoding the frame, in nanoseconds.
    ///
    /// Named for what it covers. It excludes rasterisation unless the backend reported
    /// ``rasterNs``, so it is a diagnostic sub-total and not a frame time.
    public var cpuPrepareAndEncodeNs: UInt64 { cpuPrepareNs &+ cpuEncodeNs }

    /// Everything this frame is known to have cost on the CPU, in nanoseconds.
    ///
    /// Preparation, geometry building and — where the backend could observe it — rasterisation.
    /// Still not the whole frame on a retained-mode backend, where the compositor's share is
    /// invisible from this process.
    public var cpuTotalNs: UInt64 { cpuPrepareNs &+ cpuEncodeNs &+ (rasterNs ?? 0) }

    /// True when the frame appeared later than half a frame past its target.
    ///
    /// `nil` when presentation time is unavailable — unknowable, which is not the same as false.
    public func missedDeadline(frameBudgetSeconds: Double) -> Bool? {
        guard let presentedTime else { return nil }
        return presentedTime > targetTimestamp + frameBudgetSeconds / 2
    }

    public init(
        frameID: UInt64,
        cpuPrepareNs: UInt64,
        cpuEncodeNs: UInt64,
        rasterNs: UInt64? = nil,
        gpuNs: UInt64? = nil,
        presentedTime: Double? = nil,
        targetTimestamp: Double,
        pointsSubmitted: Int,
        pointsDrawn: Int?,
        drawCalls: Int?
    ) {
        self.frameID = frameID
        self.cpuPrepareNs = cpuPrepareNs
        self.cpuEncodeNs = cpuEncodeNs
        self.rasterNs = rasterNs
        self.gpuNs = gpuNs
        self.presentedTime = presentedTime
        self.targetTimestamp = targetTimestamp
        self.pointsSubmitted = pointsSubmitted
        self.pointsDrawn = pointsDrawn
        self.drawCalls = drawCalls
    }
}
