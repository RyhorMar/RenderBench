import Testing
@testable import BenchCore

private let metadata = SeriesMetadata(name: "Pressure", unit: .psig)

private func provider(carriers: [Double]) -> ArrayProvider {
    ArrayProvider([carriers.map { Sample(carrier: $0, value: $0 * 2) }], metadata: [metadata])
}

@Test
func windowIsInclusiveAtBothEnds() {
    let subject = provider(carriers: [0, 1, 2, 3, 4, 5])
    let carriers = subject.withSeries(0, in: 1...3) { Array($0.carriers) }
    #expect(carriers == [1, 2, 3])
}

@Test
func windowOutsideTheDataYieldsAnEmptySliceRatherThanAnError() {
    let subject = provider(carriers: [10, 11, 12])
    #expect(subject.withSeries(0, in: 0...5) { $0.count } == 0)
    #expect(subject.withSeries(0, in: 90...95) { $0.count } == 0)
}

@Test
func extentSpansEverySeries() {
    let subject = ArrayProvider(
        [
            [Sample(carrier: 5, value: 1), Sample(carrier: 9, value: 2)],
            [Sample(carrier: 1, value: 3), Sample(carrier: 4, value: 4)],
        ],
        metadata: [metadata, metadata]
    )
    #expect(subject.carrierExtent == 1...9)
}

@Test
func emptyInputHasNoExtent() {
    #expect(ArrayProvider([], metadata: []).carrierExtent == nil)
    #expect(ArrayProvider([[]], metadata: [metadata]).carrierExtent == nil)
}

/// A dropout must reach the renderer as a gap, not as a value. A zero here would be drawn as a
/// pressure of zero, which in a control room reads as a shut-in well rather than a dead sensor.
@Test
func notANumberIsCarriedThroughAsAGap() {
    let subject = ArrayProvider(
        [[Sample(carrier: 0, value: 1), Sample(carrier: 1, value: .nan), Sample(carrier: 2, value: 3)]],
        metadata: [metadata]
    )
    let gaps = subject.withSeries(0, in: 0...2) { Array($0.gaps) }
    #expect(gaps == [false, true, false])
}

@Test
func parallelBuffersAlwaysAgreeInLength() {
    let subject = provider(carriers: Array(stride(from: 0.0, to: 100.0, by: 0.5)))
    subject.withSeries(0, in: 12.25...48.75) { slice in
        #expect(slice.carriers.count == slice.values.count)
        #expect(slice.values.count == slice.gaps.count)
    }
}
