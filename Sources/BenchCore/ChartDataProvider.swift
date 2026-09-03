/// A borrowed, allocation-free view of one series over a carrier window.
///
/// The three buffers are parallel and equal in length. `gaps` marks positions that carry no
/// measurement: a renderer must break the line there rather than interpolate across, and a
/// downsampler must not let a bucket span one.
///
/// - Important: This value must not outlive the closure it is handed to. The buffers point into
///   storage owned by the provider, which is free to reuse it as soon as the closure returns.
///   The compiler cannot enforce that yet in this API shape; treat escaping it as undefined
///   behaviour, not as a style violation.
public struct SeriesSlice {
    /// Positions along the carrier, strictly increasing.
    public let carriers: UnsafeBufferPointer<Carrier>
    /// Values, in the unit named by `metadata`.
    public let values: UnsafeBufferPointer<Double>
    /// `true` where no measurement exists at the corresponding carrier position.
    public let gaps: UnsafeBufferPointer<Bool>
    /// Name, unit, valid range and provenance of the series.
    public let metadata: SeriesMetadata

    public init(
        carriers: UnsafeBufferPointer<Carrier>,
        values: UnsafeBufferPointer<Double>,
        gaps: UnsafeBufferPointer<Bool>,
        metadata: SeriesMetadata
    ) {
        self.carriers = carriers
        self.values = values
        self.gaps = gaps
        self.metadata = metadata
    }

    /// Number of samples in the slice.
    public var count: Int { values.count }
}

/// Anything a backend can draw.
///
/// This is the boundary the whole package is built around: a consumer must be able to render
/// their own array without adopting the ring buffer, the frame clock, or any isolation of ours.
/// If drawing a plain `[Sample]` ever requires an engine type, this protocol has failed.
///
/// - Note: Implementations must be safe to call from the frame tick. The exact isolation —
///   `nonisolated` with an internal lock, or main-actor bound — is provisional and is settled
///   once three backends exist and the cost of each is known. The current choice is
///   `nonisolated`, because the frame slot is read off the main actor by design and binding the
///   provider to it would serialise the work this package exists to measure.
public protocol ChartDataProvider: Sendable {
    /// Number of series available.
    var seriesCount: Int { get }

    /// Carrier range spanned by all series, or `nil` when there is no data.
    var carrierExtent: ClosedRange<Carrier>? { get }

    /// Metadata for one series.
    ///
    /// - Precondition: `index` is in `0..<seriesCount`.
    func metadata(at index: Int) -> SeriesMetadata

    /// Borrows the samples of one series that fall inside `window`.
    ///
    /// - Parameters:
    ///   - index: Series to read. Must be in `0..<seriesCount`.
    ///   - window: Inclusive carrier range. An empty intersection yields an empty slice, not an
    ///     error: a running window legitimately passes over gaps in the record.
    ///   - body: Receives the borrowed slice. Must not let it escape.
    /// - Complexity: O(log *n*) to locate the window, O(1) to borrow it.
    func withSeries<R>(
        _ index: Int,
        in window: ClosedRange<Carrier>,
        _ body: (SeriesSlice) -> R
    ) -> R
}
