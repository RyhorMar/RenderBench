import BenchCore
import CoreGraphics
import Foundation

/// A bitmap and the context that draws into it, with memory that outlives the call that made it.
///
/// The obvious spelling — build the `CGContext` inside `array.withUnsafeMutableBytes` and return it
/// — is undefined behaviour, and both render targets in this package were written that way. The
/// pointer that closure yields is valid for the closure's duration only, and every drawing call
/// afterwards writes through it. It worked because `Array` happens not to move its buffer today;
/// nothing obliges an optimiser to keep that true, and the failure would be silent corruption of
/// every reference image rather than a crash.
///
/// Owning the allocation makes the lifetime explicit and removes the copy that the array version
/// needed on the way out.
public final class BitmapCanvas {
    public let width: Int
    public let height: Int
    public let bytesPerPixel = 4

    /// Premultiplied BGRA, sRGB. Pinned: a comparison run at another format compares two different
    /// questions.
    public let context: CGContext
    private let storage: UnsafeMutableRawPointer
    private let byteCount: Int

    /// - Returns: `nil` when Core Graphics refuses the configuration.
    public init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt32>.alignment
        )
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        guard let context = CGContext(
            data: storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: PaletteColor.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            storage.deallocate()
            return nil
        }

        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.storage = storage
        self.context = context

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        // Core Graphics puts the origin at the bottom left; every geometry in this package is in
        // the top-left space the view layers use. Flipping here rather than in the geometry keeps
        // the on-screen and off-screen paths drawing from one set of coordinates.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
    }

    deinit {
        storage.deallocate()
    }

    /// A copy of the pixels, for comparison and storage.
    public func pixels() -> [UInt8] {
        [UInt8](UnsafeRawBufferPointer(start: storage, count: byteCount))
    }

    /// Borrows the pixels without copying. The pointer must not outlive the call.
    public func withPixels<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
        body(UnsafeRawBufferPointer(start: storage, count: byteCount))
    }
}
