/// Position along the axis a series is ordered by: seconds from the series epoch, or metres of
/// measured depth. Never the screen axis — a well log plots its carrier vertically.
///
/// Always `Double`, never `Float`. At present-day unix time a `Float` has a ULP of 128 seconds,
/// and on a UTM northing it is half a metre; either turns a running window into visible jitter.
/// The narrowing to `Float` happens once, at the boundary with the GPU, and only after the
/// window origin has been subtracted.
public typealias Carrier = Double

/// One measurement: a position on the carrier and the value observed there.
public struct Sample: Sendable, Equatable {
    /// Position along the carrier, in the unit the series declares.
    public var carrier: Carrier
    /// Observed value, in the unit the series declares.
    public var value: Double

    public init(carrier: Carrier, value: Double) {
        self.carrier = carrier
        self.value = value
    }
}
