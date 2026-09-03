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
