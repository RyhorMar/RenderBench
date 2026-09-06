import BenchCore
import BenchRuntime
import Testing

private let plot = PlotRect(x: 52, y: 10, width: 960, height: 736)

private func chrome() -> ChromeLayout {
    ChromeLayout.build(plot: plot, xTicks: [], yTicks: [], chrome: .light, scale: 1)
}

/// The property every backend's comparison rests on: rendering the same input twice must produce
/// the same bytes, at the size `ComparisonImage` pins.
@Test
func theReferenceIsDeterministicAndSized() {
    var frame = PreparedFrame(plotRect: plot)
    frame.series = [
        PreparedSeries(
            index: 0, colour: Palette.colour(forSeries: 0, dark: false),
            points: [PlottedPoint(x: 0, y: 0.2, isBreak: false), PlottedPoint(x: 1, y: 0.8, isBreak: false)]
        ),
    ]
    frame.chrome = chrome()
    let a = CoreGraphicsReference.render(frame)
    let b = CoreGraphicsReference.render(frame)
    #expect(a != nil && a == b)
    #expect(a?.count == ComparisonImage.byteCount(scale: 1))
}

/// `PlottedPoint.y` is `0` at the domain's bottom, but screen space grows downward — so `y`
/// nearest `1` must land nearest the plot's top edge, not its bottom. A sign error in that mapping
/// draws every chart upside down while every other check that only compares two renders of the
/// same wrong code stays green.
@Test
func aPointNearOneProjectsNearTheTopOfThePlotNotTheBottom() {
    var frame = PreparedFrame(plotRect: plot)
    frame.lineWidth = 8
    frame.series = [
        PreparedSeries(
            index: 0, colour: Palette.colour(forSeries: 0, dark: false),
            points: [
                PlottedPoint(x: 0.4, y: 0.95, isBreak: false),
                PlottedPoint(x: 0.6, y: 0.95, isBreak: false),
            ]
        ),
    ]
    frame.chrome = chrome()
    guard let pixels = CoreGraphicsReference.render(frame) else {
        Issue.record("could not create a bitmap context")
        return
    }
    let x = Int(plot.minX + 0.5 * plot.width)
    let topQuarter = Int(plot.minY)..<Int(plot.minY + plot.height / 4)
    let bottomQuarter = Int(plot.maxY - plot.height / 4)..<Int(plot.maxY)
    #expect(seriesZeroFullyCovers(pixels, atX: x, inRows: topQuarter))
    #expect(!seriesZeroFullyCovers(pixels, atX: x, inRows: bottomQuarter))
}

/// A break must end the subpath, not merely be skipped from it: the placeholder `(0, 0)` a break
/// marker carries is never itself a vertex. Treating it as an ordinary point would draw a stroke
/// through the corner that placeholder maps to, joining two segments the data says are unrelated.
@Test
func aBreakDoesNotContributeItsPlaceholderCoordinatesAsAVertex() {
    var frame = PreparedFrame(plotRect: plot)
    frame.lineWidth = 8
    frame.series = [
        PreparedSeries(
            index: 0, colour: Palette.colour(forSeries: 0, dark: false),
            points: [
                PlottedPoint(x: 0, y: 0.5, isBreak: false),
                PlottedPoint(x: 0.4, y: 0.5, isBreak: false),
                PlottedPoint(x: 0, y: 0, isBreak: true),
                PlottedPoint(x: 0.6, y: 0.5, isBreak: false),
                PlottedPoint(x: 1, y: 0.5, isBreak: false),
            ]
        ),
    ]
    frame.chrome = chrome()
    guard let pixels = CoreGraphicsReference.render(frame) else {
        Issue.record("could not create a bitmap context")
        return
    }
    // The corner the break's own placeholder `(0, 0)` maps to, were it drawn as a real point.
    let corner = (x: Int(plot.minX), y: Int(plot.maxY))
    let rows = max(0, corner.y - 4)..<(corner.y + 4)
    let columns = corner.x..<(corner.x + 8)
    #expect(!columns.contains { seriesZeroFullyCovers(pixels, atX: $0, inRows: rows) })
}

/// The grid, axes and labels are laid out once by `ChromeLayout` and stroked by every backend;
/// this is the check that this backend actually stroked them rather than drawing series onto a
/// blank canvas.
@Test
func theChromeReachesTheBitmapEvenWithNoSeriesToDraw() {
    var frame = PreparedFrame(plotRect: plot)
    frame.chrome = chrome()
    guard let pixels = CoreGraphicsReference.render(frame) else {
        Issue.record("could not create a bitmap context")
        return
    }
    let axis = ChartChrome.light.axis.encodedSRGB
    let blue = UInt8((axis.blue * 255).rounded())
    let green = UInt8((axis.green * 255).rounded())
    let red = UInt8((axis.red * 255).rounded())
    var covered = 0
    for index in stride(from: 0, to: pixels.count, by: 4)
    where pixels[index] == blue && pixels[index + 1] == green && pixels[index + 2] == red {
        covered += 1
    }
    #expect(covered > 500, "only \(covered) axis-coloured pixels; the chrome may not have been drawn")
}

/// Premultiplied BGRA, little-endian: bytes run blue, green, red, alpha. Series 0 is sRGB
/// 0x006BA6 (red 0), so red == 0 selects only pixels the stroke covers completely — a partially
/// covered edge has blended some background in and carries a non-zero red.
private func seriesZeroFullyCovers(_ pixels: [UInt8], atX x: Int, inRows rows: Range<Int>) -> Bool {
    let colour = Palette.colour(forSeries: 0, dark: false).encodedSRGB
    let green = UInt8((colour.green * 255).rounded())
    let blue = UInt8((colour.blue * 255).rounded())
    for y in rows {
        let index = (y * ComparisonImage.width + x) * 4
        guard pixels.indices.contains(index + 2) else { continue }
        if pixels[index] == blue, pixels[index + 1] == green, pixels[index + 2] == 0 { return true }
    }
    return false
}
