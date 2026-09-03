import BenchCore
import BenchRuntime
import Foundation
import Metal
import simd

/// Renders a prepared frame into a bitmap off screen, on the GPU, at the pinned comparison format.
///
/// Same size, same pixel order and same colour space as the Core Graphics reference, so the bytes
/// can be compared directly. This is the first target in the project that produces a comparison
/// image without Core Graphics touching it, which is the only reason the equivalence check now
/// tests anything: two backends sharing a rasteriser can only agree.
public final class MetalRenderTarget {
    /// Width in points. Pixels are this times the scale.
    public static let width = ComparisonImage.width
    /// Height in points.
    public static let height = ComparisonImage.height
    /// BGRA, 8 bits per channel, sRGB — matching ``BitmapCanvas``. The `_srgb` suffix is what
    /// makes the hardware apply the transfer function on write, so the shader is handed the same
    /// linear components every other backend works in.
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm_srgb

    public let renderer: MetalLineRenderer
    private let queue: MTLCommandQueue
    private let sampleCount: Int

    /// - Returns: `nil` when the host has no Metal device, which is a fact about the host and not
    ///   a failure of the backend — a caller in a test suite should skip, not fail.
    public convenience init?(sampleCount: Int = 4) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            try self.init(device: device, sampleCount: sampleCount)
        } catch {
            return nil
        }
    }

    public init(device: MTLDevice, sampleCount: Int = 4) throws(MetalRendererError) {
        guard let queue = device.makeCommandQueue() else { throw .encoderUnavailable }
        self.queue = queue
        self.sampleCount = sampleCount
        // One frame in flight: this path waits for the GPU before reading the pixels back, so a
        // ring would only hold buffers nothing can be using.
        self.renderer = try MetalLineRenderer(
            device: device,
            pixelFormat: Self.pixelFormat,
            sampleCount: sampleCount,
            inFlightFrames: 1
        )
    }

    /// Draws a frame and returns raw premultiplied BGRA bytes, `width * height * 4 * scale²`.
    public func render(
        _ frame: PreparedFrame,
        chrome: ChartChrome = .light,
        scale: Double = 1,
        extendSegments: Bool = true
    ) throws(MetalRendererError) -> [UInt8] {
        let pixelWidth = Int((Double(Self.width) * scale).rounded())
        let pixelHeight = Int((Double(Self.height) * scale).rounded())
        let geometry = MetalChartGeometry.build(frame, chrome: chrome, scale: scale, extendSegments: extendSegments)

        let resolveDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        resolveDescriptor.usage = [.renderTarget, .shaderRead]
        resolveDescriptor.storageMode = .shared
        guard let resolve = renderer.device.makeTexture(descriptor: resolveDescriptor) else {
            throw .bufferAllocation(bytes: pixelWidth * pixelHeight * 4)
        }

        let pass = MTLRenderPassDescriptor()
        if sampleCount > 1 {
            let multisampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Self.pixelFormat,
                width: pixelWidth,
                height: pixelHeight,
                mipmapped: false
            )
            multisampleDescriptor.textureType = .type2DMultisample
            multisampleDescriptor.sampleCount = sampleCount
            multisampleDescriptor.usage = .renderTarget
            multisampleDescriptor.storageMode = .private
            guard let multisample = renderer.device.makeTexture(descriptor: multisampleDescriptor) else {
                throw .bufferAllocation(bytes: pixelWidth * pixelHeight * 4 * sampleCount)
            }
            pass.colorAttachments[0].texture = multisample
            pass.colorAttachments[0].resolveTexture = resolve
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolve
            pass.colorAttachments[0].storeAction = .store
        }

        guard let commandBuffer = queue.makeCommandBuffer() else { throw .encoderUnavailable }
        try renderer.draw(
            geometry,
            viewportPixels: SIMD2<Float>(Float(pixelWidth), Float(pixelHeight)),
            clearColour: chrome.background,
            descriptor: pass,
            in: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = pixelWidth * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            resolve.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight),
                mipmapLevel: 0
            )
        }
        return pixels
    }
}
