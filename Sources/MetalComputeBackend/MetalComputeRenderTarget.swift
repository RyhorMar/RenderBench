import BenchCore
import BenchRuntime
import Foundation
import Metal

/// Reduces a frame's every-point series on the GPU and renders the result into a bitmap off
/// screen, at the pinned comparison format — the equivalence counterpart of `MetalRenderTarget`.
///
/// A frame handed here is expected to have been prepared at `DownsamplePolicy.none`: this target
/// does its own reduction and does not additionally reduce whatever the CPU may have already
/// reduced.
final class MetalComputeRenderTarget {
    static let width = ComparisonImage.width
    static let height = ComparisonImage.height
    static let pixelFormat = MTLPixelFormat.bgra8Unorm_srgb

    let reducer: MetalComputeReducer
    let lineRenderer: MetalComputeLineRenderer
    private let queue: MTLCommandQueue
    private let sampleCount: Int

    /// - Returns: `nil` when the host has no Metal device — a fact about the host, not a failure
    ///   of the backend, so a caller in a test suite should skip rather than fail.
    convenience init?(sampleCount: Int = 4) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            try self.init(device: device, sampleCount: sampleCount)
        } catch {
            return nil
        }
    }

    init(device: MTLDevice, sampleCount: Int = 4) throws(MetalComputeError) {
        guard let queue = device.makeCommandQueue() else { throw .commandBufferUnavailable }
        self.queue = queue
        self.sampleCount = sampleCount
        self.reducer = try MetalComputeReducer(device: device)
        self.lineRenderer = try MetalComputeLineRenderer(
            device: device,
            pixelFormat: Self.pixelFormat,
            sampleCount: sampleCount,
            inFlightFrames: 1
        )
    }

    /// Reduces and draws a frame, returning raw premultiplied BGRA bytes.
    func render(_ frame: PreparedFrame, scale: Double = 1) throws(MetalComputeError) -> [UInt8] {
        let runsPerSeries = frame.series.map { RunSplitter.runs(in: $0.points) }
        let reduced = try reducer.reduce(runsPerSeries: runsPerSeries, plotWidth: frame.plotRect.width)
        let geometry = MetalComputeChartGeometry.build(frame, reducedRuns: reduced, scale: scale)

        let pixelWidth = Int((Double(Self.width) * scale).rounded())
        let pixelHeight = Int((Double(Self.height) * scale).rounded())

        let resolveDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        resolveDescriptor.usage = [.renderTarget, .shaderRead]
        resolveDescriptor.storageMode = .shared
        guard let resolve = reducer.device.makeTexture(descriptor: resolveDescriptor) else {
            throw .bufferAllocation(bytes: pixelWidth * pixelHeight * 4)
        }

        let pass = MTLRenderPassDescriptor()
        if sampleCount > 1 {
            let multisampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Self.pixelFormat, width: pixelWidth, height: pixelHeight, mipmapped: false
            )
            multisampleDescriptor.textureType = .type2DMultisample
            multisampleDescriptor.sampleCount = sampleCount
            multisampleDescriptor.usage = .renderTarget
            multisampleDescriptor.storageMode = .private
            guard let multisample = reducer.device.makeTexture(descriptor: multisampleDescriptor) else {
                throw .bufferAllocation(bytes: pixelWidth * pixelHeight * 4 * sampleCount)
            }
            pass.colorAttachments[0].texture = multisample
            pass.colorAttachments[0].resolveTexture = resolve
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolve
            pass.colorAttachments[0].storeAction = .store
        }

        guard let commandBuffer = queue.makeCommandBuffer() else { throw .commandBufferUnavailable }
        try lineRenderer.draw(
            geometry,
            viewportPixels: SIMD2<Float>(Float(pixelWidth), Float(pixelHeight)),
            clearColour: frame.chrome.background,
            descriptor: pass,
            in: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            resolve.getBytes(
                base, bytesPerRow: pixelWidth * 4,
                from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0
            )
        }
        return bytes
    }
}
