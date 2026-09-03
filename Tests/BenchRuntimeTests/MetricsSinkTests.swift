import BenchTestSupport
import Testing
@testable import BenchRuntime

private func frame(
    _ id: UInt64,
    cpuNs: UInt64,
    gpuNs: UInt64? = nil,
    presented: Double? = nil,
    target: Double = 0
) -> FrameMetrics {
    FrameMetrics(
        frameID: id,
        cpuPrepareNs: cpuNs / 2,
        cpuEncodeNs: cpuNs - cpuNs / 2,
        gpuNs: gpuNs,
        presentedTime: presented,
        targetTimestamp: target,
        pointsSubmitted: 800,
        pointsDrawn: 800,
        drawCalls: 1
    )
}

@Test
func percentilesMatchTheHandComputedFixture() {
    let sink = MetricsSink(capacity: 200)
    for (index, value) in PercentileFixture.frameDurationsNs.enumerated() {
        sink.record(frame(UInt64(index), cpuNs: value))
    }
    let statistics = sink.cpuStatistics()

    #expect(statistics?.sampleCount == 100)
    #expect(statistics?.p50Ns == PercentileFixture.expectedP50Ns)
    #expect(statistics?.p95Ns == PercentileFixture.expectedP95Ns)
    #expect(statistics?.p99Ns == PercentileFixture.expectedP99Ns)
    #expect(statistics?.maxNs == PercentileFixture.expectedMaxNs)
}

@Test
func nearestRankTakesTheSmallestValueAtOrAboveTheRank() {
    let sorted: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    #expect(MetricsSink.nearestRank(sorted, percentile: 50) == 5)
    #expect(MetricsSink.nearestRank(sorted, percentile: 95) == 10)
    #expect(MetricsSink.nearestRank(sorted, percentile: 0) == 1)
    #expect(MetricsSink.nearestRank([42], percentile: 99) == 42)
}

@Test
func oldestFramesFallOutOfTheWindowInOrder() {
    let sink = MetricsSink(capacity: 4)
    for id in 1...7 { sink.record(frame(UInt64(id), cpuNs: UInt64(id) * 1_000)) }

    #expect(sink.count == 4)
    #expect(sink.snapshot().map(\.frameID) == [4, 5, 6, 7])
}

/// A CPU backend has no GPU interval. Reporting zero would make it the fastest thing on the chart
/// in exactly the column readers use to compare.
@Test
func gpuStatisticsAreAbsentRatherThanZeroWhenNoFrameReportedThem() {
    let sink = MetricsSink(capacity: 16)
    for id in 1...10 { sink.record(frame(UInt64(id), cpuNs: 8_000_000)) }

    #expect(sink.gpuStatistics() == nil)
    #expect(sink.cpuStatistics()?.p50Ns == 8_000_000)
}

@Test
func gpuStatisticsCoverOnlyTheFramesThatReportedThem() {
    let sink = MetricsSink(capacity: 16)
    sink.record(frame(1, cpuNs: 1_000, gpuNs: 4_000_000))
    sink.record(frame(2, cpuNs: 1_000))
    sink.record(frame(3, cpuNs: 1_000, gpuNs: 6_000_000))

    #expect(sink.gpuStatistics()?.sampleCount == 2)
    #expect(sink.gpuStatistics()?.maxNs == 6_000_000)
}

@Test
func aMissedDeadlineNeedsAPresentationTimeToBeKnowable() {
    let budget = 1.0 / 120.0
    let onTime = frame(1, cpuNs: 1_000, presented: 1.000, target: 1.000)
    let late = frame(2, cpuNs: 1_000, presented: 1.020, target: 1.000)
    let unknown = frame(3, cpuNs: 1_000, target: 1.000)

    #expect(onTime.missedDeadline(frameBudgetSeconds: budget) == false)
    #expect(late.missedDeadline(frameBudgetSeconds: budget) == true)
    #expect(unknown.missedDeadline(frameBudgetSeconds: budget) == nil)

    let sink = MetricsSink(capacity: 8)
    sink.record(onTime)
    sink.record(late)
    sink.record(unknown)
    #expect(sink.missedDeadlineRatio(frameBudgetSeconds: budget) == 0.5)
}

@Test
func cpuTotalIsTheSumOfItsParts() {
    let metrics = frame(1, cpuNs: 9_000_001)
    #expect(metrics.cpuTotalNs == 9_000_001)
}

/// The three figures now come from one pass over one lock acquisition, so they cannot describe
/// different windows — and the ring is no longer copied three times per report.
@Test
func summaryAgreesWithTheIndividualAccessors() {
    let sink = MetricsSink(capacity: 64)
    for id in 1...40 {
        sink.record(
            frame(
                UInt64(id),
                cpuNs: UInt64(id) * 100_000,
                gpuNs: id % 2 == 0 ? UInt64(id) * 50_000 : nil,
                presented: id % 3 == 0 ? 1.05 : 1.0,
                target: 1.0
            )
        )
    }
    let budget = 1.0 / 120.0
    let summary = sink.summary(frameBudgetSeconds: budget)

    #expect(summary.cpu == sink.cpuStatistics())
    #expect(summary.gpu == sink.gpuStatistics())
    #expect(summary.missedDeadlineRatio == sink.missedDeadlineRatio(frameBudgetSeconds: budget))
    #expect(summary.gpu?.sampleCount == 20)
}

/// Nearest-rank on a vector with ties and duplicates, which the shared fixture does not contain.
@Test
func nearestRankHandlesTiesAndDuplicates() {
    let sorted: [UInt64] = [5, 5, 5, 5, 5, 9, 9, 9, 9, 100]
    #expect(MetricsSink.nearestRank(sorted, percentile: 50) == 5)
    #expect(MetricsSink.nearestRank(sorted, percentile: 60) == 9)
    #expect(MetricsSink.nearestRank(sorted, percentile: 100) == 100)
}

@Test
func summaryOverAnEmptySinkReportsNothingRatherThanZero() {
    let summary = MetricsSink(capacity: 8).summary(frameBudgetSeconds: 1.0 / 60.0)
    #expect(summary.cpu == nil)
    #expect(summary.gpu == nil)
    #expect(summary.missedDeadlineRatio == nil)
}

/// The three columns stay apart. A backend that cannot observe its own drawing reports no raster
/// time, and that must read as absent rather than as zero — a zero would let its `cpu` column be
/// mistaken for a frame cost.
@Test
func rasterTimeIsReportedSeparatelyAndIsAbsentWhenUnobserved() {
    let sink = MetricsSink(capacity: 32)
    for id in 1...10 {
        sink.record(frame(UInt64(id), cpuNs: 2_000_000))
    }
    let withoutRaster = sink.summary(frameBudgetSeconds: 1.0 / 60.0)
    #expect(withoutRaster.cpu?.p50Ns == 2_000_000)
    #expect(withoutRaster.raster == nil)

    sink.removeAll()
    for id in 1...10 {
        var metrics = frame(UInt64(id), cpuNs: 2_000_000)
        metrics.rasterNs = 500_000
        sink.record(metrics)
    }
    let withRaster = sink.summary(frameBudgetSeconds: 1.0 / 60.0)
    #expect(withRaster.cpu?.p50Ns == 2_000_000, "the cpu column absorbed the raster time")
    #expect(withRaster.raster?.p50Ns == 500_000)
    #expect(withRaster.raster?.sampleCount == 10)
}

/// The two totals answer different questions and neither is allowed to masquerade as the other.
@Test
func theSubTotalAndTheTotalAreDistinct() {
    var metrics = frame(1, cpuNs: 3_000_000)
    #expect(metrics.cpuPrepareAndEncodeNs == 3_000_000)
    #expect(metrics.cpuTotalNs == 3_000_000)

    metrics.rasterNs = 1_000_000
    #expect(metrics.cpuPrepareAndEncodeNs == 3_000_000, "the sub-total absorbed the raster time")
    #expect(metrics.cpuTotalNs == 4_000_000)
}
