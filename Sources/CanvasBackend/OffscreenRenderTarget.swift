import BenchCore
import BenchRuntime
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Draws a prepared frame into a bitmap of fixed size and format, off screen.
///
/// The point is not to produce a picture for a person to look at — it is to produce the *same*
/// bytes twice, so that two backends can be shown to draw the same thing before their timings are
/// compared. Everything about the target is pinned for that reason: the size, the pixel format,
/// the colour space and the antialiasing. A comparison run at whatever size the window happened to
/// be compares two different questions.
public enum OffscreenRenderTarget {
    /// Width in points of every comparison render.
    public static let width = ComparisonImage.width
    /// Height in points of every comparison render.
    public static let height = ComparisonImage.height
    /// Bytes per pixel: 8-bit BGRA, premultiplied.
    public static let bytesPerPixel = ComparisonImage.bytesPerPixel

    /// Renders a frame at a pinned configuration and returns raw premultiplied BGRA bytes.
    ///
    /// Antialiasing is on and interpolation is off. Both are stated rather than left to the
    /// context's defaults, because a default that changes between OS versions would silently
    /// invalidate every stored reference image.
    ///
    /// - Parameters:
    ///   - frame: Geometry to draw, already prepared, background and chrome included. Its
    ///     `plotRect` must match this target's size, which
    ///     `render(provider:spec:window:yDomain:dark:scratch:)` guarantees.
    ///   - scale: Device pixels per point. The reference is produced at 1 by default and the
    ///     screen draws at 2 or 3, so a statement relating this image to a device's rendering
    ///     only holds when both were produced at the same scale. Making it a parameter is what
    ///     lets that be checked rather than assumed.
    /// - Returns: `width * height * 4` bytes, or `nil` when a context could not be created.
    public static func render(
        _ frame: CanvasFrame,
        scale: Double = 1
    ) -> [UInt8]? {
        let pixelWidth = Int((Double(width) * scale).rounded())
        let pixelHeight = Int((Double(height) * scale).rounded())
        guard let canvas = BitmapCanvas(width: pixelWidth, height: pixelHeight) else { return nil }
        let context = canvas.context
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

        context.setFillColor(frame.chrome.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        let plot = frame.plotRect
        if plot.width > 1, plot.height > 1 {
            strokeChrome(frame.chrome.lines, in: context)

            context.setLineWidth(CGFloat(frame.lineWidth))
            context.setLineCap(.round)
            // Bevel: matches both backends' on-screen stroke style, so the reference is a
            // reference for what actually ships.
            context.setLineJoin(.bevel)
            for stroke in frame.strokes {
                context.setStrokeColor(stroke.colour.cgColor)
                context.addPath(stroke.path.cgPath)
                context.strokePath()
            }
        }

        // Labels are deliberately not drawn. Text rasterisation depends on the installed font and
        // on the text engine's version, so including it would make a stored reference invalid on a
        // machine that draws the same chart correctly. Equivalence is about the data path.
        return canvas.pixels()
    }

    /// Strokes lines that share a colour and width in one `strokePath()` call, each as its own
    /// subpath (`move`, never chained with `addLine` into the previous one).
    ///
    /// Measured: stroking the two touching axis lines as separate `strokePath()` calls — one
    /// naive line at a time — shifts one pixel at their shared corner (1024x768 comparison image,
    /// `eightCurves()` fixture: byte offset 3,055,824 goes from `938e8eff` to `ada9a9ff`). Two
    /// antialiased edges blended onto the canvas in separate calls compose differently from the
    /// same two edges blended once. Grouping by colour and width avoids that; whether a line
    /// starts a new subpath or continues the last one inside that single call does not — the two
    /// touching axis lines were confirmed byte-identical either way.
    private static func strokeChrome(_ lines: [ChromeLine], in context: CGContext) {
        var index = 0
        while index < lines.count {
            let style = lines[index]
            context.setLineWidth(CGFloat(style.width))
            context.setStrokeColor(style.colour.cgColor)
            while index < lines.count, lines[index].colour == style.colour, lines[index].width == style.width {
                let line = lines[index]
                context.move(to: CGPoint(x: line.x0, y: line.y0))
                context.addLine(to: CGPoint(x: line.x1, y: line.y1))
                index += 1
            }
            context.strokePath()
        }
    }

    /// Prepares and renders in one step, at this target's fixed size.
    public static func render(
        provider: some ChartDataProvider,
        spec: LineChartSpec,
        window: ClosedRange<Carrier>,
        yDomain: ClosedRange<Double>,
        dark: Bool = false,
        scratch: inout [Sample]
    ) -> [UInt8]? {
        let frame = CanvasChartRenderer.buildFrame(
            provider: provider,
            spec: spec,
            window: window,
            yDomain: yDomain,
            size: CGSize(width: width, height: height),
            dark: dark,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
        return render(frame)
    }

    /// Writes raw bytes out as a PNG, for storing a reference image.
    ///
    /// - Returns: `true` when the file was written.
    public static func writePNG(_ pixels: [UInt8], to url: URL) -> Bool {
        let bytesPerRow = width * bytesPerPixel
        guard pixels.count == bytesPerRow * height else { return false }

        // `CGDataProvider(data:)` retains the CFData, so nothing here outlives its backing. The
        // earlier version handed out a pointer borrowed from an array and a no-op release callback,
        // which left the image reading memory nobody had promised to keep.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return false }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: PaletteColor.sRGB,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return false }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

}
