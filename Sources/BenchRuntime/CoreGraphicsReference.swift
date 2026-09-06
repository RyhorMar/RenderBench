import BenchCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws a prepared frame with Core Graphics into a bitmap of fixed size and format, off screen.
///
/// The point is not to produce a picture for a person to look at — it is to produce the *same*
/// bytes twice, so that any backend can be shown to draw the same thing this one draws before
/// their timings are compared. Living here rather than inside whichever backend needed it first is
/// what lets the next backend compare against it without depending on that one.
public enum CoreGraphicsReference {
    /// Renders a frame at a pinned configuration and returns raw premultiplied BGRA bytes.
    ///
    /// Antialiasing is on and interpolation is off. Both are stated rather than left to the
    /// context's defaults, because a default that changes between OS versions would silently
    /// invalidate every stored reference image.
    ///
    /// - Parameters:
    ///   - frame: Geometry to draw, already prepared, background and chrome included. Its
    ///     `plotRect` must match `ComparisonImage`'s pinned size.
    ///   - scale: Device pixels per point. The reference is produced at 1 by default and the
    ///     screen draws at 2 or 3, so a statement relating this image to a device's rendering
    ///     only holds when both were produced at the same scale. Making it a parameter is what
    ///     lets that be checked rather than assumed.
    /// - Returns: `ComparisonImage.byteCount(scale:)` bytes, or `nil` when a context could not be
    ///   created.
    public static func render(_ frame: PreparedFrame, scale: Double = 1) -> [UInt8]? {
        makeCanvas(frame, scale: scale)?.pixels()
    }

    /// Renders a frame exactly as ``render(_:scale:)`` does, but returns the `CGImage` snapshot of
    /// the same bitmap context instead of copying its bytes out.
    ///
    /// Exists for a backend — Core Image so far — whose own pipeline starts from a `CGImage`
    /// rather than from raw bytes, and which must be provably drawing the same thing this
    /// reference draws rather than merely something similar. `CGContext.makeImage()` snapshots the
    /// context's own storage with no intervening copy or re-encoding, so the image this returns and
    /// the bytes ``render(_:scale:)`` returns for the same frame are the same pixels by
    /// construction, not by two rasterisers agreeing.
    ///
    /// - Returns: `nil` under the same condition as ``render(_:scale:)``.
    public static func renderCGImage(_ frame: PreparedFrame, scale: Double = 1) -> CGImage? {
        guard let canvas = makeCanvas(frame, scale: scale) else { return nil }
        return canvas.context.makeImage()
    }

    /// Draws a frame into a freshly allocated ``BitmapCanvas`` and returns it, still holding the
    /// drawn context. Shared by ``render(_:scale:)`` and ``renderCGImage(_:scale:)`` so the two
    /// can never draw anything differently from one another.
    private static func makeCanvas(_ frame: PreparedFrame, scale: Double) -> BitmapCanvas? {
        let pixelWidth = Int((Double(ComparisonImage.width) * scale).rounded())
        let pixelHeight = Int((Double(ComparisonImage.height) * scale).rounded())
        guard let canvas = BitmapCanvas(width: pixelWidth, height: pixelHeight) else { return nil }
        let context = canvas.context
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

        context.setFillColor(frame.chrome.background.cgColor)
        context.fill(CGRect(
            x: 0, y: 0,
            width: CGFloat(ComparisonImage.width), height: CGFloat(ComparisonImage.height)
        ))

        let plot = frame.plotRect
        if plot.isDrawable {
            strokeChrome(frame.chrome.lines, in: context)

            context.setLineWidth(CGFloat(frame.lineWidth))
            context.setLineCap(.round)
            // Bevel matches the Canvas and Core Animation backends' on-screen stroke style. The
            // GPU backend's join differs by construction — it extends segments instead of
            // emitting join geometry — so it is compared against this reference through a
            // structural equivalence check, not byte equality.
            context.setLineJoin(.bevel)
            for series in frame.series {
                context.setStrokeColor(series.colour.cgColor)
                context.addPath(path(for: series.points, in: plot))
                context.strokePath()
            }
        }

        // Labels are deliberately not drawn. Text rasterisation depends on the installed font and
        // on the text engine's version, so including it would make a stored reference invalid on a
        // machine that draws the same chart correctly. Equivalence is about the data path.
        return canvas
    }

    /// Builds one series' stroke path from its points, already projected into `0...1` by
    /// `FramePreparation`.
    ///
    /// A point with `isBreak == true` ends the current subpath rather than contributing a vertex,
    /// matching every other backend's treatment of a missing measurement.
    private static func path(for points: [PlottedPoint], in plot: PlotRect) -> CGPath {
        let path = CGMutablePath()
        var penIsDown = false
        for point in points {
            guard !point.isBreak else {
                penIsDown = false
                continue
            }
            let location = CGPoint(
                x: CGFloat(plot.minX + point.x * plot.width),
                y: CGFloat(plot.maxY - point.y * plot.height)
            )
            if penIsDown {
                path.addLine(to: location)
            } else {
                path.move(to: location)
                penIsDown = true
            }
        }
        return path
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

    /// Writes raw bytes out as a PNG, for storing a reference image.
    ///
    /// - Parameter scale: Must match the scale `pixels` was rendered at; it is what turns the
    ///   pinned point size into the pixel dimensions the byte count is checked against.
    /// - Returns: `true` when the file was written.
    public static func writePNG(_ pixels: [UInt8], scale: Double = 1, to url: URL) -> Bool {
        let pixelWidth = Int((Double(ComparisonImage.width) * scale).rounded())
        let pixelHeight = Int((Double(ComparisonImage.height) * scale).rounded())
        let bytesPerRow = pixelWidth * ComparisonImage.bytesPerPixel
        guard pixels.count == bytesPerRow * pixelHeight else { return false }

        // `CGDataProvider(data:)` retains the CFData, so nothing here outlives its backing. The
        // earlier version handed out a pointer borrowed from an array and a no-op release callback,
        // which left the image reading memory nobody had promised to keep.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return false }
        guard let image = CGImage(
            width: pixelWidth,
            height: pixelHeight,
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
