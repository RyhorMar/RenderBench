/// The provider a consumer gets for free: samples they already have, drawn without adopting
/// anything else in this package.
///
/// Storage is converted once, at construction, from the array-of-structs the caller holds into
/// the parallel arrays a renderer wants. Doing it here rather than per frame is the difference
/// between a quickstart that is honest about cost and one that hides it inside the draw call.
///
/// A value of `Double.nan` is read as a gap. That is the convention the field formats already
/// use — LAS writes `-999.25`, sensors drop out — and it keeps the sample type two doubles wide.
public struct ArrayProvider: ChartDataProvider {
    private struct Series: Sendable {
        var carriers: [Carrier]
        var values: [Double]
        var gaps: [Bool]
        var metadata: SeriesMetadata
    }

    private let series: [Series]

    public let carrierExtent: ClosedRange<Carrier>?

    public var seriesCount: Int { series.count }

    /// Creates a provider over samples the caller already holds.
    ///
    /// - Parameters:
    ///   - samples: One array of samples per series, each ordered by strictly increasing carrier.
    ///   - metadata: One entry per series, in the same order.
    /// - Precondition: `samples.count == metadata.count`.
    /// - Precondition: Each series is sorted by carrier. Not checked in release builds; violating
    ///   it produces silently wrong windows rather than a crash.
    public init(_ samples: [[Sample]], metadata: [SeriesMetadata]) {
        precondition(
            samples.count == metadata.count,
            "ArrayProvider needs one metadata entry per series"
        )

        var built: [Series] = []
        built.reserveCapacity(samples.count)
        var lowest = Carrier.infinity
        var highest = -Carrier.infinity

        for (index, sampleList) in samples.enumerated() {
            var carriers: [Carrier] = []
            var values: [Double] = []
            var gaps: [Bool] = []
            carriers.reserveCapacity(sampleList.count)
            values.reserveCapacity(sampleList.count)
            gaps.reserveCapacity(sampleList.count)

            for sample in sampleList {
                // The doc comment promised this check and did not make it. An unsorted series is
                // not a crash — the binary search simply returns an empty window — so the mistake
                // reaches the screen as a blank chart with no explanation.
                assert(
                    carriers.last.map { sample.carrier > $0 } ?? true,
                    "ArrayProvider expects each series sorted by strictly increasing carrier"
                )
                carriers.append(sample.carrier)
                values.append(sample.value)
                gaps.append(sample.value.isNaN)
            }
            if let first = carriers.first, let last = carriers.last {
                lowest = Swift.min(lowest, first)
                highest = Swift.max(highest, last)
            }
            built.append(
                Series(carriers: carriers, values: values, gaps: gaps, metadata: metadata[index])
            )
        }

        self.series = built
        self.carrierExtent = lowest <= highest ? lowest...highest : nil
    }

    public func metadata(at index: Int) -> SeriesMetadata {
        series[index].metadata
    }

    public func withSeries<R>(
        _ index: Int,
        in window: ClosedRange<Carrier>,
        _ body: (SeriesSlice) -> R
    ) -> R {
        let target = series[index]
        let range = CarrierSearch.indices(of: target.carriers, within: window)

        return target.carriers.withUnsafeBufferPointer { carriers in
            target.values.withUnsafeBufferPointer { values in
                target.gaps.withUnsafeBufferPointer { gaps in
                    body(
                        SeriesSlice(
                            carriers: UnsafeBufferPointer(rebasing: carriers[range]),
                            values: UnsafeBufferPointer(rebasing: values[range]),
                            gaps: UnsafeBufferPointer(rebasing: gaps[range]),
                            metadata: target.metadata
                        )
                    )
                }
            }
        }
    }

}
