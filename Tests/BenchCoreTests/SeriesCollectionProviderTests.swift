import Testing
@testable import BenchCore

private let metadata = SeriesMetadata(name: "Pressure", unit: .psig)

private func series(capacity: Int, count: Int, from start: Int = 0) -> DataSeries {
    var result = DataSeries(capacity: capacity, metadata: metadata)
    for index in start..<(start + count) {
        result.append(Sample(carrier: Double(index), value: Double(index) * 2))
    }
    return result
}

/// The provider the demo actually renders from, and the one that had no test file at all: its
/// windowing runs over a ring that has wrapped, which no `ArrayProvider` test exercises.
@Test
func windowingWorksAfterTheRingHasWrapped() {
    let provider = SeriesCollectionProvider(series: [series(capacity: 10, count: 25)])
    // Capacity 10 over 25 pushes leaves carriers 15...24.
    #expect(provider.carrierExtent == 15...24)

    let inside = provider.withSeries(0, in: 17...20) { Array($0.carriers) }
    #expect(inside == [17, 18, 19, 20])

    let clipped = provider.withSeries(0, in: 0...17) { Array($0.carriers) }
    #expect(clipped == [15, 16, 17])
}

@Test
func aWindowPastTheRetainedRangeIsEmptyRatherThanWrong() {
    let provider = SeriesCollectionProvider(series: [series(capacity: 8, count: 40)])
    #expect(provider.withSeries(0, in: 0...5) { $0.count } == 0)
    #expect(provider.withSeries(0, in: 100...200) { $0.count } == 0)
}

@Test
func extentSpansEverySeriesEvenWhenTheyStartApart() {
    let provider = SeriesCollectionProvider(series: [
        series(capacity: 10, count: 5, from: 0),
        series(capacity: 10, count: 5, from: 20),
    ])
    #expect(provider.carrierExtent == 0...24)
}

@Test
func anEmptyCollectionHasNoExtent() {
    #expect(SeriesCollectionProvider(series: []).carrierExtent == nil)
    #expect(SeriesCollectionProvider(series: [DataSeries(capacity: 4, metadata: metadata)]).carrierExtent == nil)
}

@Test
func parallelBuffersStayAlignedAcrossTheWrap() {
    let provider = SeriesCollectionProvider(series: [series(capacity: 16, count: 100)])
    provider.withSeries(0, in: 90...99) { slice in
        #expect(slice.carriers.count == slice.values.count)
        #expect(slice.values.count == slice.gaps.count)
        for offset in 0..<slice.count {
            #expect(slice.values[offset] == slice.carriers[offset] * 2)
        }
    }
}

/// One search, used by both providers. Before this it was two copies and only one of them tested.
@Test
func carrierSearchAgreesWithALinearScan() {
    let carriers = (0..<200).map { Double($0) * 0.5 }
    for lower in stride(from: -1.0, through: 100.0, by: 7.3) {
        for width in [0.0, 0.4, 3.7, 25.0] {
            let window = lower...(lower + width)
            let found = CarrierSearch.indices(of: carriers, within: window)
            let expected = carriers.enumerated().filter { window.contains($0.element) }.map(\.offset)
            #expect(Array(found) == expected, "window \(window)")
        }
    }
}
