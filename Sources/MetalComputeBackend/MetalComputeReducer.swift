import BenchCore
import BenchRuntime
import Foundation
import Metal

/// Why this backend could not be built, could not reduce, or could not draw.
public enum MetalComputeError: Error, Sendable, Equatable {
    case noDevice
    case libraryCompilation(String)
    case missingFunction(String)
    case pipeline(String)
    case bufferAllocation(bytes: Int)
    case commandBufferUnavailable
    case encoderUnavailable
}

/// Mirrors `BucketResult` in `MetalComputeShaderSource` exactly. The layout is asserted by a test
/// rather than trusted — a silent mismatch here reads adjacent bytes as a coordinate and produces
/// a plausible, wrong chart.
struct GPUBucketResult {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var count: UInt32
    var padding: UInt32 = 0
}

/// One contiguous stretch of a series between breaks, already projected into normalised `0...1`.
///
/// A break ends one run and starts the next — the same treatment every other backend gives a
/// gap — so no bucket this backend builds ever spans a dropout.
public struct NormalisedRun: Sendable, Equatable {
    public var points: [SIMD2<Float>]
    public init(points: [SIMD2<Float>]) { self.points = points }
}

/// Splits a prepared series' points at its breaks. Break points themselves carry the placeholder
/// `(0, 0)` and are never real data — `FramePreparation` documents this — so they are dropped
/// rather than treated as coordinates.
public enum RunSplitter {
    public static func runs(in points: [PlottedPoint]) -> [NormalisedRun] {
        var result: [NormalisedRun] = []
        var current: [SIMD2<Float>] = []
        for point in points {
            if point.isBreak {
                if !current.isEmpty { result.append(NormalisedRun(points: current)) }
                current = []
                continue
            }
            current.append(SIMD2<Float>(Float(point.x), Float(point.y)))
        }
        if !current.isEmpty { result.append(NormalisedRun(points: current)) }
        return result
    }
}

/// How many buckets one run reduces to.
///
/// `Int(runWidthNormalised * plotWidth)` is a **point budget**, the same kind `FramePreparation`'s
/// own `target = max(2, Int(plot.width))` hands the CPU path for a whole frame — applied here per
/// run against that run's own share of the plot's width instead, since this backend never sees the
/// whole frame's carrier range, only what already reached it as normalised x. A budget is not a
/// bucket count: `Sources/BenchDownsampling/Downsample.swift`'s `appendMinMax` halves its own
/// budget into `bucketCount = max(1, budget / 2)` because each bucket emits up to two points, min
/// and max, so the width in pixels must be halved to land on the same nominal density. An earlier
/// version of this function used the raw pixel-width budget as the bucket count directly and
/// emitted roughly twice the CPU path's point density for the same nominal budget — a design
/// mistake in the formula itself, not a coding slip, corrected by the halving below.
public enum RunColumns {
    public static func columns(runWidthNormalised: Double, plotWidth: Double) -> Int {
        max(1, Int(runWidthNormalised * plotWidth) / 2)
    }
}

/// Owns the device and the compute pipeline that reduces runs of points to their per-bucket
/// extrema, on the GPU.
///
/// Built once, like `MetalLineRenderer`'s pipeline: the pipeline state is derived here, at
/// construction, from a library the caller compiled exactly once and shares with
/// ``MetalComputeLineRenderer`` too — see ``MetalComputeCompiledLibrary``. The command queue is
/// built here as well and reused by every ``reduce(runsPerSeries:plotWidth:)`` call; an earlier
/// version made a fresh queue inside `reduce` itself, once per frame.
public final class MetalComputeReducer {
    public let device: MTLDevice
    let pipeline: MTLComputePipelineState
    private let queue: MTLCommandQueue

    public init(device: MTLDevice, library: MTLLibrary) throws(MetalComputeError) {
        self.device = device
        guard let function = library.makeFunction(name: MetalComputeShaderSource.reduceFunction) else {
            throw .missingFunction(MetalComputeShaderSource.reduceFunction)
        }
        do {
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw .pipeline(String(describing: error))
        }
        guard let queue = device.makeCommandQueue() else { throw .commandBufferUnavailable }
        self.queue = queue
    }

    /// Reduces every run of every series, in one command buffer, one dispatch per run — then
    /// blocks for the result.
    ///
    /// The block is real, is the point of this method's contract, and must be included by the
    /// caller in whatever it reports as `encodeNs`: a synchronous readback of a GPU buffer is the
    /// one cost this design pays that no other backend pays in the same place, and an async
    /// callback here would make the frame that owns it look free when it is not.
    ///
    /// - Returns: One array of reduced runs per input series, in the same order, with each run's
    ///   points still in carrier order and still normalised `0...1`.
    public func reduce(
        runsPerSeries: [[NormalisedRun]],
        plotWidth: Double
    ) throws(MetalComputeError) -> [[NormalisedRun]] {
        guard let commandBuffer = queue.makeCommandBuffer() else { throw .commandBufferUnavailable }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw .encoderUnavailable }
        encoder.setComputePipelineState(pipeline)

        // Kept alive until the command buffer completes and its results are read; a buffer the
        // GPU is still reading must not be released while the compute pass runs. `columns` and
        // `seriesIndex` travel alongside so the readback below can rebuild each series' run list
        // in the order it was dispatched — the same order it was submitted in, since nothing here
        // reorders series or runs.
        struct Pending {
            let seriesIndex: Int
            let columns: Int
            let results: MTLBuffer
            let points: MTLBuffer
        }
        var pending: [Pending] = []

        for (seriesIndex, runs) in runsPerSeries.enumerated() {
            for run in runs {
                guard let minX = run.points.first?.x, let maxX = run.points.last?.x else { continue }
                let pointCount = run.points.count
                let runWidth = Double(maxX - minX)
                let columns = RunColumns.columns(runWidthNormalised: runWidth, plotWidth: plotWidth)
                let bucketWidth = Float(runWidth) / Float(columns)

                let pointsBytes = pointCount * MemoryLayout<SIMD2<Float>>.stride
                guard let pointsBuffer = device.makeBuffer(
                    bytes: run.points, length: pointsBytes, options: .storageModeShared
                ) else { throw .bufferAllocation(bytes: pointsBytes) }

                let resultsBytes = columns * MemoryLayout<GPUBucketResult>.stride
                guard let resultsBuffer = device.makeBuffer(
                    length: resultsBytes, options: .storageModeShared
                ) else { throw .bufferAllocation(bytes: resultsBytes) }

                var pointCountArg = UInt32(pointCount)
                var minXArg = minX
                var bucketWidthArg = bucketWidth
                var columnsArg = UInt32(columns)

                encoder.setBuffer(pointsBuffer, offset: 0, index: 0)
                encoder.setBytes(&pointCountArg, length: MemoryLayout<UInt32>.stride, index: 1)
                encoder.setBytes(&minXArg, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setBytes(&bucketWidthArg, length: MemoryLayout<Float>.stride, index: 3)
                encoder.setBytes(&columnsArg, length: MemoryLayout<UInt32>.stride, index: 4)
                encoder.setBuffer(resultsBuffer, offset: 0, index: 5)

                let width = min(pipeline.maxTotalThreadsPerThreadgroup, columns)
                let threadgroupSize = MTLSize(width: max(1, width), height: 1, depth: 1)
                let threadgroupCount = MTLSize(
                    width: (columns + threadgroupSize.width - 1) / threadgroupSize.width,
                    height: 1, depth: 1
                )
                encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

                pending.append(Pending(seriesIndex: seriesIndex, columns: columns, results: resultsBuffer, points: pointsBuffer))
            }
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var output = runsPerSeries.map { _ in [NormalisedRun]() }
        for item in pending {
            let raw = item.results.contents().bindMemory(to: GPUBucketResult.self, capacity: item.columns)
            var reduced: [SIMD2<Float>] = []
            reduced.reserveCapacity(item.columns * 2)
            for index in 0..<item.columns {
                let bucket = raw[index]
                if bucket.count >= 1 { reduced.append(bucket.a) }
                if bucket.count >= 2 { reduced.append(bucket.b) }
            }
            output[item.seriesIndex].append(NormalisedRun(points: reduced))
        }
        return output
    }
}
