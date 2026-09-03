/// Draws from a set of running windows.
///
/// The counterpart to ``ArrayProvider``: that one wraps samples a caller already holds, this one
/// wraps series that are still being written to. Both satisfy the same protocol, which is what lets
/// a backend be measured on live data and on a fixture without knowing the difference.
public struct SeriesCollectionProvider: ChartDataProvider {
    /// The series, in draw order.
    public var series: [DataSeries]

    public init(series: [DataSeries]) {
        self.series = series
    }

    public var seriesCount: Int { series.count }

    public var carrierExtent: ClosedRange<Carrier>? {
        var lowest = Carrier.infinity
        var highest = -Carrier.infinity
        for element in series {
            guard let extent = element.extent else { continue }
            lowest = Swift.min(lowest, extent.lowerBound)
            highest = Swift.max(highest, extent.upperBound)
        }
        return lowest <= highest ? lowest...highest : nil
    }

    public func metadata(at index: Int) -> SeriesMetadata {
        series[index].metadata
    }

    public func withSeries<R>(
        _ index: Int,
        in window: ClosedRange<Carrier>,
        _ body: (SeriesSlice) -> R
    ) -> R {
        series[index].withSlice { slice in
            let range = CarrierSearch.indices(of: slice.carriers, within: window)
            return body(
                SeriesSlice(
                    carriers: UnsafeBufferPointer(rebasing: slice.carriers[range]),
                    values: UnsafeBufferPointer(rebasing: slice.values[range]),
                    gaps: UnsafeBufferPointer(rebasing: slice.gaps[range]),
                    metadata: slice.metadata
                )
            )
        }
    }

}
