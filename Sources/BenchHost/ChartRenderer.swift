import BenchRuntime
import SwiftUI

/// What a renderer is, before any frame is drawn.
public struct RendererDescriptor: Sendable, Equatable, Identifiable {
    /// Mirrors `identifier`, for `Identifiable` conformance.
    public var id: String { identifier }
    /// Stable key used for routing and catalogue lookup. Never shown to a user.
    public let identifier: String
    /// Name shown to a user, e.g. in a picker.
    public let displayName: String
    /// True when the backend can time its own draw pass. False is a fact about the method, not a gap.
    public let reportsRasterTime: Bool
    /// True when the backend reads GPU timestamps.
    public let reportsGPUTime: Bool
    /// True for the one backend whose method *is* the reduction. Eight of nine leave it false;
    /// for the ninth, the scene sets `LineChartSpec.policy` to `DownsamplePolicy.none` so
    /// `FramePreparation` performs no reduction, and the frame arrives with every windowed point
    /// for the backend to reduce on the GPU itself.
    public let reducesOnGPU: Bool

    /// Creates a descriptor. `reducesOnGPU` defaults to `false`, so eight of the nine backends
    /// that do not reduce on the GPU never have to mention it.
    public init(identifier: String, displayName: String, reportsRasterTime: Bool,
                reportsGPUTime: Bool, reducesOnGPU: Bool = false) {
        self.identifier = identifier
        self.displayName = displayName
        self.reportsRasterTime = reportsRasterTime
        self.reportsGPUTime = reportsGPUTime
        self.reducesOnGPU = reducesOnGPU
    }
}

/// What encoding one frame cost, on the CPU, right now.
public struct EncodeReport: Sendable, Equatable {
    /// Monotonic time `encode` took, measured with `ContinuousClock`, in nanoseconds.
    public var encodeNs: UInt64
    /// Samples this backend actually drew for this frame. Divergence from the count submitted to
    /// `encode` is the signal that a backend is buying its frame time by dropping work.
    public var pointsDrawn: Int
    /// Draw calls issued to produce this frame.
    public var drawCalls: Int

    /// Creates a report for one `encode` call.
    public init(encodeNs: UInt64, pointsDrawn: Int, drawCalls: Int) {
        self.encodeNs = encodeNs
        self.pointsDrawn = pointsDrawn
        self.drawCalls = drawCalls
    }
}

/// Measurements that arrive after the frame that produced them. `nil` = cannot report.
public struct DeferredTimes: Sendable, Equatable {
    /// Raster time the backend reported for a previous frame, in nanoseconds.
    public var rasterNs: UInt64?
    /// GPU time the backend reported for a previous frame, in nanoseconds.
    public var gpuNs: UInt64?
    /// When a previously encoded frame actually appeared, in seconds on the host clock. `nil`
    /// means this backend cannot observe presentation, never that the frame appeared at zero —
    /// for a retained-mode backend this and the missed-deadline ratio are the only honest
    /// measurements available at all.
    public var presentedTime: Double?
    /// No deferred measurement available, for a backend that never reports any of these.
    public static let none = DeferredTimes(rasterNs: nil, gpuNs: nil, presentedTime: nil)

    /// Creates a deferred-times value from three independently optional measurements.
    public init(rasterNs: UInt64?, gpuNs: UInt64?, presentedTime: Double?) {
        self.rasterNs = rasterNs
        self.gpuNs = gpuNs
        self.presentedTime = presentedTime
    }
}

/// One of the nine ways to put a prepared frame on screen.
///
/// Everything before `encode` is shared and identical across backends; everything from `encode`
/// on is the method. A renderer never owns a clock, never prepares data, and never decides where
/// the grid goes — those are the three ways a comparison stops being one.
/// Conformers must be `@Observable`, and `encode` must mutate a stored property that `surface`
/// reads. Nothing in the type system says so: a renderer that encodes into private state the view
/// never observes compiles, draws its first frame and then freezes. A demo test fires two ticks
/// at every backend and asserts this number moved.
@MainActor
public protocol ChartRenderer: AnyObject {
    /// Identity and reporting capabilities of this backend, fixed before any instance exists.
    static var descriptor: RendererDescriptor { get }
    /// Measured limits for this backend, one entry per chart kind it has been benchmarked on.
    static var capabilities: [Capability] { get }
    /// Creates a renderer with no frame encoded yet.
    init()
    /// Turns a prepared frame into whatever this backend draws from. Called once per tick.
    /// Must increment ``encodedRevision`` and mutate state that ``surface`` reads.
    func encode(_ frame: PreparedFrame) -> EncodeReport
    /// Frames encoded so far. Read by `surface`, so a renderer that encodes into state the view
    /// cannot observe fails a test instead of freezing silently.
    var encodedRevision: UInt64 { get }
    /// Collects raster/GPU times that arrived since the last call.
    func takeDeferredTimes() -> DeferredTimes
    /// The view showing the last encoded frame. Same underlying type every call.
    var surface: AnyView { get }
    /// Stop consuming GPU/compositor work; the scene has already stopped the clock. `suspend()`
    /// and `resume()` can each arrive twice in a row on a backgrounded-then-foregrounded screen,
    /// so calling either one without an intervening call to the other must be harmless.
    func suspend()
    /// Resume producing frames after `suspend()`. See `suspend()` for the idempotence this and
    /// `suspend()` both require.
    func resume()
    /// Release device resources now. `deinit` on iOS arrives late while a screen is
    /// mid-transition; a torn-down renderer must be inert even if it is still alive. Calling
    /// twice — once from a view disappearing, once from deallocation — must be harmless.
    func teardown()
}
