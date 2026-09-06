import BenchCore
import BenchRuntime
import Foundation
import Metal

/// What one encoded draw pass submitted to the GPU.
struct MetalComputeDrawStats: Sendable, Equatable {
    var drawCalls: Int
    var pointsDrawn: Int
    var verticesGenerated: Int
}

/// Uniforms for one draw. Layout matches `ChartUniforms` in `MetalComputeShaderSource`; sizes are
/// asserted by a test, not trusted — see `Sources/MetalBackend/MetalLineRenderer.swift`'s own
/// `ChartUniforms` for why that check exists.
struct MetalComputeUniforms {
    var viewportPixels: SIMD2<Float>
    var halfWidth: Float
    var extend: Float
    var colour: SIMD4<Float>
}

/// Draws already-built line geometry: the render half of this backend.
///
/// Duplicated from `Sources/MetalBackend/MetalLineRenderer.swift` for the reason stated on
/// `MetalComputeLineGeometry` — this package's backends do not depend on one another. The
/// reduction is what makes this backend different; the draw is deliberately the same technique, so
/// the equivalence check is judging the reduction and not a second, unrelated difference in how
/// the line itself gets to the screen.
final class MetalComputeLineRenderer {
    let device: MTLDevice
    let libraryCompileNanoseconds: UInt64

    private let pipeline: MTLRenderPipelineState
    private let inFlight: DispatchSemaphore
    private var slots: [Slot]
    private var slotIndex = 0

    private struct Slot {
        var points: MTLBuffer?
        var segments: MTLBuffer?
    }

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        inFlightFrames: Int = 3
    ) throws(MetalComputeError) {
        precondition(inFlightFrames >= 1, "a ring of no buffers cannot hold a frame")
        self.device = device

        let clock = ContinuousClock()
        var compiled: MTLLibrary?
        var compileFailure: String?
        let elapsed = clock.measure {
            do {
                compiled = try device.makeLibrary(source: MetalComputeShaderSource.source, options: nil)
            } catch {
                compileFailure = String(describing: error)
            }
        }
        guard let library = compiled else { throw .libraryCompilation(compileFailure ?? "unknown") }
        self.libraryCompileNanoseconds = elapsed.nanoseconds

        guard let vertex = library.makeFunction(name: MetalComputeShaderSource.vertexFunction) else {
            throw .missingFunction(MetalComputeShaderSource.vertexFunction)
        }
        guard let fragment = library.makeFunction(name: MetalComputeShaderSource.fragmentFunction) else {
            throw .missingFunction(MetalComputeShaderSource.fragmentFunction)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.rasterSampleCount = sampleCount
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipeline(String(describing: error))
        }

        self.inFlight = DispatchSemaphore(value: inFlightFrames)
        self.slots = Array(repeating: Slot(), count: inFlightFrames)
    }

    @discardableResult
    func draw(
        _ geometry: MetalComputeChartGeometry,
        viewportPixels: SIMD2<Float>,
        clearColour: PaletteColor,
        descriptor: MTLRenderPassDescriptor,
        in commandBuffer: MTLCommandBuffer
    ) throws(MetalComputeError) -> MetalComputeDrawStats {
        inFlight.wait()
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: clearColour.red, green: clearColour.green, blue: clearColour.blue, alpha: 1
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw .encoderUnavailable
        }
        defer { encoder.endEncoding() }

        var stats = MetalComputeDrawStats(drawCalls: 0, pointsDrawn: 0, verticesGenerated: 0)
        guard !geometry.isEmpty else { return stats }

        let slot = slotIndex
        slotIndex = (slotIndex + 1) % slots.count
        let pointBytes = geometry.points.count * MemoryLayout<SIMD2<Float>>.stride
        let segmentBytes = geometry.segmentStarts.count * MemoryLayout<UInt32>.stride
        let points = try grow(&slots[slot].points, to: pointBytes)
        let segments = try grow(&slots[slot].segments, to: segmentBytes)
        copy(geometry.points, into: points, bytes: pointBytes)
        copy(geometry.segmentStarts, into: segments, bytes: segmentBytes)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(points, offset: 0, index: 0)
        encoder.setVertexBuffer(segments, offset: 0, index: 1)

        for batch in geometry.batches {
            var uniforms = MetalComputeUniforms(
                viewportPixels: viewportPixels,
                halfWidth: batch.halfWidth,
                extend: batch.extend,
                colour: SIMD4<Float>(
                    Float(batch.colour.red), Float(batch.colour.green), Float(batch.colour.blue), 1
                )
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalComputeUniforms>.stride, index: 2)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: batch.segmentRange.count,
                baseInstance: batch.segmentRange.lowerBound
            )
            stats.drawCalls += 1
            stats.verticesGenerated += batch.segmentRange.count * 6
        }
        stats.pointsDrawn = geometry.points.count
        return stats
    }

    private func copy<Element>(_ source: [Element], into buffer: MTLBuffer, bytes: Int) {
        source.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: bytes)
        }
    }

    private func grow(_ buffer: inout MTLBuffer?, to bytes: Int) throws(MetalComputeError) -> MTLBuffer {
        let needed = max(bytes, 1)
        if let existing = buffer, existing.length >= needed { return existing }
        let size = max(needed, (buffer?.length ?? 0) * 2)
        guard let made = device.makeBuffer(length: size, options: .storageModeShared) else {
            throw .bufferAllocation(bytes: size)
        }
        buffer = made
        return made
    }
}
