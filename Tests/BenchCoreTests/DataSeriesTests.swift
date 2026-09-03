import Testing
@testable import BenchCore

private let metadata = SeriesMetadata(name: "Pressure", unit: .psig)

@Test
func extentFollowsTheRunningWindow() {
    var series = DataSeries(capacity: 3, metadata: metadata)
    #expect(series.extent == nil)
    for step in 0..<5 {
        series.append(Sample(carrier: Double(step), value: Double(step) * 10))
    }
    #expect(series.extent == 2...4)
    #expect(series.count == 3)
}

@Test
func sliceExposesThreeBuffersOfEqualLength() {
    var series = DataSeries(capacity: 8, metadata: metadata)
    for step in 0..<5 {
        series.append(Sample(carrier: Double(step), value: Double(step)))
    }
    series.withSlice { slice in
        #expect(slice.count == 5)
        #expect(slice.carriers.count == 5)
        #expect(slice.gaps.count == 5)
        #expect(Array(slice.carriers) == [0, 1, 2, 3, 4])
        #expect(slice.metadata.name == "Pressure")
    }
}

@Test
func dropoutBecomesAGapRatherThanAValue() {
    var series = DataSeries(capacity: 4, metadata: metadata)
    series.append(Sample(carrier: 0, value: 1))
    series.append(Sample(carrier: 1, value: .nan))
    series.append(Sample(carrier: 2, value: 3))
    #expect(series.gaps.segments() == [0..<1, 2..<3])
}
