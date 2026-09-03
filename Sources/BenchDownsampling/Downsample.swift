import BenchCore
import BenchScales

/// Reduces a series to the number of points a display can resolve, under the chosen policy.
///
/// Writes into `output` rather than returning an array: this runs once per series per frame, and
/// a fresh allocation on that path is a measurable cost the caller can avoid by keeping one
/// buffer alive. `output` is cleared but keeps its capacity.
///
/// Gaps survive the reduction. Each uninterrupted stretch is reduced on its own, no bucket spans
/// a dropout, and a sample whose value is `Double.nan` is emitted between stretches so the
/// renderer still knows to lift the pen.
///
/// - Parameters:
///   - slice: Samples to reduce, ordered by increasing carrier.
///   - targetPoints: Upper bound on emitted points, gap markers excluded.
///   - policy: How to choose which points survive. See ``DownsamplePolicy``.
///   - xScale: Projection of the carrier. Used by `lttb` so its metric is unit-free.
///   - yScale: Projection of the value. Used by `lttb` for the same reason.
///   - output: Destination. Cleared on entry, capacity retained.
/// - Throws: ``ChartError/nonAveragable(unit:)`` when `lttb` is applied to a quantity whose mean
///   is meaningless.
/// - Precondition: `targetPoints >= 2`.
/// - Complexity: O(*n*) for every policy, single pass.
public func downsample(
    _ slice: SeriesSlice,
    to targetPoints: Int,
    policy: DownsamplePolicy,
    xScale: some AxisScale,
    yScale: some AxisScale,
    into output: inout [Sample]
) throws(ChartError) {
    precondition(targetPoints >= 2, "downsampling needs room for at least the two endpoints")
    output.removeAll(keepingCapacity: true)
    guard slice.count > 0 else { return }

    // LTTB weighs a triangle whose third vertex is the mean of the next bucket. On a quantity
    // that must not be averaged that mean is not a number anyone should act on, so the policy is
    // refused rather than quietly applied. MinMax is allowed on the same series: it returns real
    // extrema and computes nothing.
    if policy == .lttb, !slice.metadata.unit.isAveragable {
        throw ChartError.nonAveragable(unit: slice.metadata.unit)
    }

    let segments = contiguousRuns(in: slice.gaps)
    guard !segments.isEmpty else { return }

    if policy == .none || slice.count <= targetPoints {
        emitEverything(slice, segments: segments, into: &output)
        return
    }

    let total = segments.reduce(0) { $0 + $1.count }
    for (index, segment) in segments.enumerated() {
        // Budget split by share of the samples, so a long stretch is not reduced as hard as a
        // short one just because they are both stretches.
        let share = max(2, targetPoints * segment.count / max(total, 1))
        switch policy {
        case .minMax:
            appendMinMax(slice, segment: segment, budget: share, into: &output)
        case .lttb:
            appendLTTB(slice, segment: segment, budget: share, xScale: xScale, yScale: yScale, into: &output)
        case .none:
            break
        }
        if index < segments.count - 1 {
            output.append(Sample(carrier: slice.carriers[segment.upperBound - 1], value: .nan))
        }
    }
}

/// Index ranges of consecutive positions that carry measurements.
func contiguousRuns(in gaps: UnsafeBufferPointer<Bool>) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start: Int?
    for index in 0..<gaps.count {
        if gaps[index] {
            if let begin = start { runs.append(begin..<index); start = nil }
        } else if start == nil {
            start = index
        }
    }
    if let begin = start { runs.append(begin..<gaps.count) }
    return runs
}

private func emitEverything(
    _ slice: SeriesSlice,
    segments: [Range<Int>],
    into output: inout [Sample]
) {
    for (index, segment) in segments.enumerated() {
        for position in segment {
            output.append(Sample(carrier: slice.carriers[position], value: slice.values[position]))
        }
        if index < segments.count - 1 {
            output.append(Sample(carrier: slice.carriers[segment.upperBound - 1], value: .nan))
        }
    }
}

/// Per-bucket extrema, each emitted at the carrier position where it actually occurred.
///
/// Buckets are cut on the carrier, not on the sample index. On an irregular grid — which is the
/// normal case once a source has dropped samples — index buckets cover unequal spans of time, and
/// the envelope comes out modulated by the sampling irregularity rather than by the signal.
private func appendMinMax(
    _ slice: SeriesSlice,
    segment: Range<Int>,
    budget: Int,
    into output: inout [Sample]
) {
    let first = slice.carriers[segment.lowerBound]
    let last = slice.carriers[segment.upperBound - 1]
    let span = last - first
    let bucketCount = max(1, budget / 2)
    guard span > 0, segment.count > 2 else {
        for position in segment {
            output.append(Sample(carrier: slice.carriers[position], value: slice.values[position]))
        }
        return
    }
    let width = span / Double(bucketCount)

    var position = segment.lowerBound
    var bucket = 0
    while position < segment.upperBound, bucket < bucketCount {
        let edge = bucket == bucketCount - 1 ? last.nextUp : first + Double(bucket + 1) * width
        var minimum = position
        var maximum = position
        var scanned = false

        while position < segment.upperBound, slice.carriers[position] < edge {
            scanned = true
            if slice.values[position] < slice.values[minimum] { minimum = position }
            if slice.values[position] > slice.values[maximum] { maximum = position }
            position += 1
        }
        if scanned {
            // Ordered by carrier, not by magnitude: emitting the maximum first would draw the
            // line back on itself inside every bucket.
            let earlier = min(minimum, maximum)
            let later = max(minimum, maximum)
            output.append(Sample(carrier: slice.carriers[earlier], value: slice.values[earlier]))
            if later != earlier {
                output.append(Sample(carrier: slice.carriers[later], value: slice.values[later]))
            }
        }
        bucket += 1
    }
}

/// Largest-Triangle-Three-Buckets, with every area computed in normalised screen space.
///
/// The triangle metric mixes the two axes, so computing it in data space makes the chosen points
/// depend on whether the pressure is in bars or in pascals — the same curve, decimated
/// differently, for no reason a reader could see. Projecting first removes the units entirely.
///
/// - Note: Steinarsson, S., *Downsampling Time Series for Visual Representation*, MSc thesis,
///   University of Iceland, 2013, §4.2. Screen-space evaluation and gap handling are additions;
///   the thesis specifies neither.
private func appendLTTB(
    _ slice: SeriesSlice,
    segment: Range<Int>,
    budget: Int,
    xScale: some AxisScale,
    yScale: some AxisScale,
    into output: inout [Sample]
) {
    guard segment.count > budget, budget >= 3 else {
        for position in segment {
            output.append(Sample(carrier: slice.carriers[position], value: slice.values[position]))
        }
        return
    }

    func projected(_ position: Int) -> (x: Double, y: Double) {
        (
            xScale.map(slice.carriers[position]).normalised,
            yScale.map(slice.values[position]).normalised
        )
    }
    func emit(_ position: Int) {
        output.append(Sample(carrier: slice.carriers[position], value: slice.values[position]))
    }

    let inner = budget - 2
    let step = Double(segment.count - 2) / Double(inner)

    emit(segment.lowerBound)
    var selected = segment.lowerBound

    for bucket in 0..<inner {
        let start = segment.lowerBound + 1 + Int(Double(bucket) * step)
        let end = min(segment.lowerBound + 1 + Int(Double(bucket + 1) * step), segment.upperBound - 1)
        guard start < end else { continue }

        // Mean of the following bucket forms the third vertex. Clamped to the last real bucket so
        // the final iteration cannot divide by an empty range.
        let nextStart = end
        let nextEnd = min(
            segment.lowerBound + 1 + Int(Double(bucket + 2) * step),
            segment.upperBound
        )
        var averageX = 0.0
        var averageY = 0.0
        var counted = 0
        for position in nextStart..<max(nextStart + 1, nextEnd) where position < segment.upperBound {
            let point = projected(position)
            averageX += point.x
            averageY += point.y
            counted += 1
        }
        if counted > 0 {
            averageX /= Double(counted)
            averageY /= Double(counted)
        }

        let anchor = projected(selected)
        var best = start
        var bestArea = -1.0
        for candidate in start..<end {
            let point = projected(candidate)
            let area = abs(
                (anchor.x - averageX) * (point.y - anchor.y)
                    - (anchor.x - point.x) * (averageY - anchor.y)
            )
            if area > bestArea {
                bestArea = area
                best = candidate
            }
        }
        emit(best)
        selected = best
    }

    emit(segment.upperBound - 1)
}
