import Foundation
import Metal
import Testing
@testable import MetalComputeBackend

/// A synthetic run: `columns` is fixed by choosing `plotWidth` so that
/// `RunColumns.columns(runWidthNormalised:plotWidth:)` returns exactly `columns`, since the run's
/// x span is pinned to `0...1` below.
private func syntheticRun(_ pairs: [(Float, Float)]) -> NormalisedRun {
    NormalisedRun(points: pairs.map { SIMD2<Float>($0.0, $0.1) })
}

/// `MetalComputeReducer.init` takes an already-compiled library rather than compiling its own —
/// this test file is not the timed per-frame path, so compiling one library per test here is not
/// the mistake fixed elsewhere, only a call-site update that fix forces.
private func reducer(for device: MTLDevice) throws -> MetalComputeReducer {
    let library = try MetalComputeCompiledLibrary(device: device)
    return try MetalComputeReducer(device: device, library: library.library)
}

/// A fresh, independent reference implementation of *this backend's own* bucketing algorithm —
/// normalised x, after projection, half-open buckets with the last one extended to +infinity —
/// deliberately not `BenchDownsampling.appendMinMax`. That function buckets raw carrier before
/// projection and splits its budget across a slice's several gap-separated stretches at once;
/// this backend only ever sees points already projected into one run at a time, with no carrier
/// to bucket by and no cross-run budget to split, so the two are answering different questions and
/// a shared reference would silently paper over that.
///
/// Ties resolve to the first occurrence — `<`/`>`, never `<=`/`>=` — matching the kernel.
private func referenceReduce(_ points: [SIMD2<Float>], columns: Int) -> [SIMD2<Float>] {
    guard let minX = points.first?.x, columns > 0 else { return [] }
    let maxX = points.last?.x ?? minX
    let bucketWidth = (maxX - minX) / Float(columns)
    var output: [SIMD2<Float>] = []

    for bucket in 0..<columns {
        let start = minX + bucketWidth * Float(bucket)
        let end = bucket == columns - 1 ? Float.infinity : minX + bucketWidth * Float(bucket + 1)

        var rangeStart: Int?
        var rangeEnd = 0
        for index in points.indices where points[index].x >= start && points[index].x < end {
            if rangeStart == nil { rangeStart = index }
            rangeEnd = index + 1
        }
        guard let start = rangeStart, start < rangeEnd else { continue }

        var minIndex = start
        var maxIndex = start
        for index in start..<rangeEnd {
            if points[index].y < points[minIndex].y { minIndex = index }
            if points[index].y > points[maxIndex].y { maxIndex = index }
        }
        let earlier = min(minIndex, maxIndex)
        let later = max(minIndex, maxIndex)
        output.append(points[earlier])
        if later != earlier { output.append(points[later]) }
    }
    return output
}

@Test
func theGPUKernelMatchesAFreshSwiftReferenceOfTheSameAlgorithm() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let reducer = try reducer(for: device)

    var pairs: [(Float, Float)] = []
    for step in 0..<47 {
        let x = Float(step) / 46
        let y = sinf(x * 6.28 * 2.7) * 0.6 + Float(step % 5) * 0.01
        pairs.append((x, y))
    }
    let run = syntheticRun(pairs)
    let columns = 6

    // `RunColumns.columns` halves its pixel-width budget, so a plot width of `columns * 2` is
    // what yields exactly `columns` buckets for a run spanning the full `0...1`.
    let reduced = try reducer.reduce(runsPerSeries: [[run]], plotWidth: Double(columns * 2))
    let actual = reduced[0][0].points
    let expected = referenceReduce(run.points, columns: columns)

    #expect(actual.count == expected.count)
    for (a, e) in zip(actual, expected) {
        #expect(abs(a.x - e.x) < 1e-5)
        #expect(abs(a.y - e.y) < 1e-5)
    }
}

/// A run with only two points and one bucket exercises the tightest path through the kernel: both
/// binary searches degenerate to the same two-element range, and the pair must still come back in
/// carrier order.
@Test
func aTwoPointRunInOneBucketKeepsCarrierOrder() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let reducer = try reducer(for: device)
    let run = syntheticRun([(0.0, 0.9), (1.0, -0.4)])

    let reduced = try reducer.reduce(runsPerSeries: [[run]], plotWidth: 1)
    let points = reduced[0][0].points
    #expect(points.count == 2)
    #expect(points[0] == SIMD2<Float>(0.0, 0.9))
    #expect(points[1] == SIMD2<Float>(1.0, -0.4))
}

/// A single-point run cannot afford a pair; the kernel must still terminate and hand back exactly
/// that one point rather than a bucket claiming a partner that does not exist.
@Test
func aOnePointRunEmitsExactlyThatPoint() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let reducer = try reducer(for: device)
    let run = syntheticRun([(0.5, 0.25)])

    let reduced = try reducer.reduce(runsPerSeries: [[run]], plotWidth: 4)
    #expect(reduced[0][0].points == [SIMD2<Float>(0.5, 0.25)])
}

/// The wire format the kernel writes and Swift reads back must agree byte for byte, or a mismatch
/// reads adjacent memory as a coordinate and produces a plausible, wrong chart.
@Test
func gpuBucketResultMatchesTheKernelsLayout() {
    #expect(MemoryLayout<GPUBucketResult>.stride == 24)
    #expect(MemoryLayout<GPUBucketResult>.alignment == 8)
}

/// Two series, each with one run, dispatched together: the readback must not mix a bucket of one
/// series into another's run list.
@Test
func multipleSeriesAreReducedIndependently() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let reducer = try reducer(for: device)
    let first = syntheticRun((0..<10).map { (Float($0) / 9, 1.0) })
    let second = syntheticRun((0..<10).map { (Float($0) / 9, -1.0) })

    let reduced = try reducer.reduce(runsPerSeries: [[first], [second]], plotWidth: 3)
    #expect(reduced.count == 2)
    #expect(reduced[0][0].points.allSatisfy { $0.y == 1.0 })
    #expect(reduced[1][0].points.allSatisfy { $0.y == -1.0 })
}
