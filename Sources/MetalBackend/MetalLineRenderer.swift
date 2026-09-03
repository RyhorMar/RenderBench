import BenchCore
import BenchRuntime
import Foundation
import Metal
import simd

/// Why a renderer could not be built or could not draw.
public enum MetalRendererError: Error, Sendable, Equatable {
    case noDevice
    case libraryCompilation(String)
    case missingFunction(String)
    case pipeline(String)
    case bufferAllocation(bytes: Int)
    case encoderUnavailable
}

/// What one encoded frame submitted to the GPU.
public struct MetalDrawStats: Sendable, Equatable {
    public var drawCalls: Int
    public var pointsDrawn: Int
    public var verticesGenerated: Int
}

/// Uniforms for one draw. Layout matches `ChartUniforms` in ``MetalShaderSource``; the sizes are
/// asserted by a test rather than trusted, because a silent mismatch reads adjacent memory as a
/// colour and produces a plausible chart in the wrong hue.
struct ChartUniforms {
    var viewportPixels: SIMD2<Float>
    var halfWidth: Float
    var extend: Float
    var colour: SIMD4<Float>
}

/// Metal backend's renderer: uploads points once per frame, expands them on the GPU.
///
/// Third of the nine, and the first that does not rasterise through Core Graphics. Until it
/// existed, the cross-backend equivalence check compared two users of the same rasteriser, so a
/// shared mistake in it was invisible to the check — which is exactly how both backends came to
/// stroke every series in the wrong colour space and pass.
///
/// It does not own a display link: one tick per scene is an invariant of this project.
public final class MetalLineRenderer {
    public let device: MTLDevice
    /// Cost of compiling the shader from source, in nanoseconds. Paid once, before the first
    /// frame, and reported so that it is not mistaken for something a frame pays.
    public let libraryCompileNanoseconds: UInt64

    private let pipeline: MTLRenderPipelineState
    private let inFlight: DispatchSemaphore
    private var slots: [Slot]
    private var slotIndex = 0

    /// Buffers for one frame in flight. Writing into a shared-storage buffer the GPU is still
    /// reading is a data race that shows up as one frame's geometry appearing inside another's;
    /// the ring plus the semaphore is what makes that impossible rather than unlikely.
    private struct Slot {
        var points: MTLBuffer?
        var segments: MTLBuffer?
    }

    /// - Parameters:
    ///   - sampleCount: Multisample count. Four, because the GPU has no equivalent of Core
    ///     Graphics' analytic coverage and a chart of one-point lines without multisampling is a
    ///     staircase — a difference in output, not in method.
    ///   - inFlightFrames: How many frames may be encoded before one completes.
    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int = 4,
        inFlightFrames: Int = 3
    ) throws(MetalRendererError) {
        precondition(inFlightFrames >= 1, "a ring of no buffers cannot hold a frame")
        self.device = device

        let clock = ContinuousClock()
        var compiled: MTLLibrary?
        var compileFailure: String?
        let elapsed = clock.measure {
            do {
                compiled = try device.makeLibrary(source: MetalShaderSource.source, options: nil)
            } catch {
                compileFailure = String(describing: error)
            }
        }
        guard let library = compiled else {
            throw .libraryCompilation(compileFailure ?? "unknown")
        }
        self.libraryCompileNanoseconds = elapsed.nanoseconds

        guard let vertex = library.makeFunction(name: MetalShaderSource.vertexFunction) else {
            throw .missingFunction(MetalShaderSource.vertexFunction)
        }
        guard let fragment = library.makeFunction(name: MetalShaderSource.fragmentFunction) else {
            throw .missingFunction(MetalShaderSource.fragmentFunction)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.rasterSampleCount = sampleCount
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Blending stays off. Every colour in the chart is opaque, and the segments of one
        // polyline deliberately overlap at the joins — with blending on, each overlap would
        // darken and a corner would read as a different colour from the line it belongs to.
        descriptor.colorAttachments[0].isBlendingEnabled = false

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipeline(String(describing: error))
        }

        self.inFlight = DispatchSemaphore(value: inFlightFrames)
        self.slots = Array(repeating: Slot(), count: inFlightFrames)
    }

    /// Encodes one frame and registers the fence that releases its buffers.
    ///
    /// The render pass is created here rather than taken as a parameter so that the wait, the
    /// upload and the signal cannot be separated by a caller. Blocks until a buffer slot frees.
    @discardableResult
    public func draw(
        _ geometry: MetalChartGeometry,
        viewportPixels: SIMD2<Float>,
        clearColour: PaletteColor,
        descriptor: MTLRenderPassDescriptor,
        in commandBuffer: MTLCommandBuffer
    ) throws(MetalRendererError) -> MetalDrawStats {
        inFlight.wait()
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: clearColour.red,
            green: clearColour.green,
            blue: clearColour.blue,
            alpha: 1
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw .encoderUnavailable
        }
        defer { encoder.endEncoding() }

        var stats = MetalDrawStats(drawCalls: 0, pointsDrawn: 0, verticesGenerated: 0)
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
            var uniforms = ChartUniforms(
                viewportPixels: viewportPixels,
                halfWidth: batch.halfWidth,
                extend: batch.extend,
                colour: SIMD4<Float>(
                    Float(batch.colour.red),
                    Float(batch.colour.green),
                    Float(batch.colour.blue),
                    1
                )
            )
            // Small and per-draw: `setVertexBytes` copies into the encoder's own storage, so
            // there is no buffer for the next batch to overwrite while this one is still queued.
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ChartUniforms>.stride, index: 2)
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

    private func grow(_ buffer: inout MTLBuffer?, to bytes: Int) throws(MetalRendererError) -> MTLBuffer {
        let needed = max(bytes, 1)
        if let existing = buffer, existing.length >= needed { return existing }
        // Doubling rather than exact fit: a window that grows by one point per frame would
        // otherwise reallocate every frame, and the allocation would be charged to the method.
        let size = max(needed, (buffer?.length ?? 0) * 2)
        guard let made = device.makeBuffer(length: size, options: .storageModeShared) else {
            throw .bufferAllocation(bytes: size)
        }
        buffer = made
        return made
    }
}
