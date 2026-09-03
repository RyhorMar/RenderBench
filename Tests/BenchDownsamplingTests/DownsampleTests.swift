import BenchCore
import Foundation
import BenchScales
import Testing
@testable import BenchDownsampling

private func series(
    _ values: [Double],
    step: Double = 1,
    unit: SeriesUnit = .psig
) -> ArrayProvider {
    let samples = values.enumerated().map { Sample(carrier: Double($0.offset) * step, value: $0.element) }
    return ArrayProvider([samples], metadata: [SeriesMetadata(name: "S", unit: unit)])
}

private func reduce(
    _ provider: ArrayProvider,
    to target: Int,
    policy: DownsamplePolicy,
    yDomain: ClosedRange<Double>
) throws -> [Sample] {
    let extent = provider.carrierExtent ?? 0...1
    var output: [Sample] = []
    try provider.withSeries(0, in: extent) { slice in
        Result { try downsample(
            slice,
            to: target,
            policy: policy,
            xScale: LinearScale(domain: extent),
            yScale: LinearScale(domain: yDomain),
            into: &output
        ) }
    }.get()
    return output
}

/// The property MinMax exists for. A policy that loses the global extremes is not a downsampler,
/// it is a filter, and the reader has no way to tell the difference from the picture.
@Test
func minMaxAlwaysKeepsTheGlobalExtremes() throws {
    var values = (0..<2_000).map { sin(Double($0) * 0.31) }
    values[733] = 9.5
    values[1_512] = -7.25
    let output = try reduce(series(values), to: 200, policy: .minMax, yDomain: -10...10)

    #expect(output.contains { $0.value == 9.5 })
    #expect(output.contains { $0.value == -7.25 })
}

/// The headline comparison: a carrier faster than one bucket. MinMax keeps the envelope, LTTB
/// collapses it. This is the difference the demo shows on screen, asserted as a number.
@Test
func lttbCollapsesAnEnvelopeThatMinMaxPreserves() throws {
    let values = (0..<8_000).map { sin(Double($0) * 0.9) }
    let provider = series(values)

    let byMinMax = try reduce(provider, to: 400, policy: .minMax, yDomain: -1...1)
    let byLTTB = try reduce(provider, to: 400, policy: .lttb, yDomain: -1...1)

    let minMaxSpan = (byMinMax.map(\.value).max() ?? 0) - (byMinMax.map(\.value).min() ?? 0)
    let lttbSpan = (byLTTB.map(\.value).max() ?? 0) - (byLTTB.map(\.value).min() ?? 0)

    #expect(minMaxSpan > 1.98)
    #expect(lttbSpan < minMaxSpan)
}

/// LTTB selects, it does not synthesise. Every emitted point must exist in the input.
@Test
func lttbOutputIsASubsequenceOfTheInput() throws {
    let values = (0..<3_000).map { Double($0).truncatingRemainder(dividingBy: 97) }
    let output = try reduce(series(values), to: 300, policy: .lttb, yDomain: 0...97)
    let originals = Set(values)

    #expect(output.allSatisfy { originals.contains($0.value) })
    #expect(output.first?.value == values.first)
    #expect(output.last?.value == values.last)
}

/// The reason the metric is computed after projection. Restating the same curve in another unit
/// must not change which samples survive; in data space it does.
@Test
func changingTheUnitDoesNotChangeWhichPointsLTTBKeeps() throws {
    let raw = (0..<2_000).map { sin(Double($0) * 0.17) * 40 + 100 }
    let scaled = raw.map { $0 * 14.503_773_773_022_1 }

    let inPsi = try reduce(series(raw), to: 200, policy: .lttb, yDomain: 60...140)
    let inBar = try reduce(
        series(scaled, unit: .bar),
        to: 200,
        policy: .lttb,
        yDomain: (60 * 14.503_773_773_022_1)...(140 * 14.503_773_773_022_1)
    )

    #expect(inPsi.map(\.carrier) == inBar.map(\.carrier))
}

@Test
func noBucketSpansAGap() throws {
    var values = (0..<600).map { Double($0) }
    for index in 200..<260 { values[index] = .nan }
    let output = try reduce(series(values), to: 60, policy: .minMax, yDomain: 0...600)

    let markers = output.filter { $0.value.isNaN }
    #expect(markers.count == 1)

    // Nothing emitted may come from inside the dropout.
    let drawn = output.filter { !$0.value.isNaN }
    #expect(drawn.allSatisfy { $0.value < 200 || $0.value >= 260 })
}

@Test
func policyNoneKeepsEverySampleAndStillBreaksAtGaps() throws {
    var values = (0..<20).map { Double($0) }
    values[7] = .nan
    let output = try reduce(series(values), to: 20, policy: .none, yDomain: 0...20)
    #expect(output.count == 20)
    #expect(output.filter { $0.value.isNaN }.count == 1)
}

@Test
func shortInputIsPassedThroughUnchanged() throws {
    let values = [1.0, 5.0, 3.0]
    let output = try reduce(series(values), to: 50, policy: .minMax, yDomain: 0...10)
    #expect(output.map(\.value) == values)
}

/// A quantity whose mean is meaningless may still be reduced by MinMax, which reports real
/// extrema, but not by LTTB, which weighs a bucket average.
@Test
func averagingPolicyIsRefusedOnANonAveragableQuantity() throws {
    let gravity = SeriesUnit(
        symbol: "°API",
        quantity: .dimensionless,
        scale: 1,
        offset: 0,
        isAveragable: false
    )
    let provider = series((0..<500).map { Double($0 % 40) }, unit: gravity)

    #expect(throws: ChartError.nonAveragable(unit: gravity)) {
        _ = try reduce(provider, to: 50, policy: .lttb, yDomain: 0...40)
    }
    #expect(throws: Never.self) {
        _ = try reduce(provider, to: 50, policy: .minMax, yDomain: 0...40)
    }
}

@Test
func outputBufferIsReusedRatherThanReallocated() throws {
    let provider = series((0..<1_000).map { sin(Double($0)) })
    let extent = provider.carrierExtent ?? 0...1
    var output: [Sample] = []
    output.reserveCapacity(4_096)
    let capacityBefore = output.capacity

    for _ in 0..<10 {
        try provider.withSeries(0, in: extent) { slice in
            Result { try downsample(
                slice,
                to: 100,
                policy: .minMax,
                xScale: LinearScale(domain: extent),
                yScale: LinearScale(domain: -1...1),
                into: &output
            ) }
        }.get()
    }
    #expect(output.capacity == capacityBefore)
    #expect(output.isEmpty == false)
}
