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
    public var pointsDrawn: Int
    /// Draw calls issued.
    public var drawCalls: Int

    /// Total CPU cost of the frame, in nanoseconds.
    public var cpuTotalNs: UInt64 { cpuPrepareNs &+ cpuEncodeNs }

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
        gpuNs: UInt64? = nil,
        presentedTime: Double? = nil,
        targetTimestamp: Double,
        pointsSubmitted: Int,
        pointsDrawn: Int,
        drawCalls: Int
    ) {
        self.frameID = frameID
        self.cpuPrepareNs = cpuPrepareNs
        self.cpuEncodeNs = cpuEncodeNs
        self.gpuNs = gpuNs
        self.presentedTime = presentedTime
        self.targetTimestamp = targetTimestamp
        self.pointsSubmitted = pointsSubmitted
        self.pointsDrawn = pointsDrawn
        self.drawCalls = drawCalls
    }
}
