/// One series held in a running window: carriers, values, gaps and the metadata describing them.
///
/// The three buffers are pushed together and rotate together, which is the whole reason they are
/// separate rings rather than one ring of structs: a renderer uploads carriers and values as two
/// contiguous runs without restriding, and a gap never drifts away from the sample it belongs to.
public struct DataSeries: Sendable {
    /// Positions along the carrier, oldest first.
    public private(set) var carriers: RingBuffer<Carrier>
    /// Values, oldest first, in the unit named by ``metadata``.
    public private(set) var values: RingBuffer<Double>
    /// Which of those positions carry no measurement.
    public private(set) var gaps: NullMask
    /// Name, unit, valid range and provenance.
    public var metadata: SeriesMetadata

    /// Samples retained.
    public var count: Int { values.count }

    /// Carrier range currently held, or `nil` while empty.
    public var extent: ClosedRange<Carrier>? {
        guard count > 0 else { return nil }
        return carriers[0]...carriers[count - 1]
    }

    public init(capacity: Int, metadata: SeriesMetadata) {
        self.carriers = RingBuffer(capacity: capacity, filledWith: 0)
        self.values = RingBuffer(capacity: capacity, filledWith: 0)
        self.gaps = NullMask(capacity: capacity)
        self.metadata = metadata
    }

    /// Appends one sample. A value of `Double.nan` is recorded as a gap.
    ///
    /// - Precondition: `sample.carrier` is greater than the newest carrier already held. Not
    ///   checked in release builds; violating it produces a series that binary search cannot
    ///   window correctly rather than a crash.
    public mutating func append(_ sample: Sample) {
        assert(
            count == 0 || sample.carrier > carriers[count - 1],
            "DataSeries expects strictly increasing carriers"
        )
        carriers.push(sample.carrier)
        values.push(sample.value)
        gaps.push(isGap: sample.value.isNaN)
    }

    /// Borrows the whole retained window as a slice a backend can draw.
    ///
    /// - Important: The slice must not escape the closure.
    public func withSlice<R>(_ body: (SeriesSlice) -> R) -> R {
        carriers.withUnsafeSnapshot { carrierBuffer in
            values.withUnsafeSnapshot { valueBuffer in
                gaps.withUnsafeFlags { gapBuffer in
                    body(
                        SeriesSlice(
                            carriers: carrierBuffer,
                            values: valueBuffer,
                            gaps: gapBuffer,
                            metadata: metadata
                        )
                    )
                }
            }
        }
    }

    public mutating func removeAll() {
        carriers.removeAll()
        values.removeAll()
        gaps.removeAll()
    }
}
