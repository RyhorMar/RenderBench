import BenchCore
import BenchRuntime
import CanvasBackend
import Foundation
import Metal
import Testing
@testable import MetalBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

private func curves(_ count: Int) -> ArrayProvider {
    var series: [[Sample]] = []
    var metadata: [SeriesMetadata] = []
    for index in 0..<count {
        let amplitude = 1.0 - Double(index) * 0.06
        let frequency = 0.25 + Double(index) * 0.02
        let phase = Double(index) * .pi / 5
        series.append((0..<10_000).map { step in
            let time = Double(step) / 1_000
            return Sample(carrier: time, value: amplitude * sin(2 * .pi * frequency * time + phase))
        })
        metadata.append(SeriesMetadata(name: "s\(index)", unit: .fraction))
    }
    return ArrayProvider(series, metadata: metadata)
}

private func prepared(_ spec: LineChartSpec, shiftedBy shift: Double = 0) -> PreparedFrame {
    var scratch: [Sample] = []
    var frame = FramePreparation.prepare(
        provider: curves(8),
        spec: spec,
        window: window,
        yDomain: yDomain,
        size: (width: Double(ComparisonImage.width), height: Double(ComparisonImage.height)),
        dark: false,
        measuring: ApproximateTextWidth(),
        scratch: &scratch
    )
    if shift != 0 {
        frame.plotRect = PlotRect(
            x: frame.plotRect.x + shift,
            y: frame.plotRect.y,
            width: frame.plotRect.width,
            height: frame.plotRect.height
        )
    }
    return frame
}

private func coreGraphicsReference(_ spec: LineChartSpec) -> [UInt8] {
    var scratch: [Sample] = []
    return OffscreenRenderTarget.render(
        provider: curves(8), spec: spec, window: window, yDomain: yDomain, scratch: &scratch
    ) ?? []
}

/// BGR triples the palette renders as at full coverage.
private let solidSeriesColours: [(UInt8, UInt8, UInt8)] = (0..<8).map { index in
    let encoded = Palette.colour(forSeries: index, dark: false).encodedSRGB
    return (
        UInt8((encoded.blue * 255).rounded()),
        UInt8((encoded.green * 255).rounded()),
        UInt8((encoded.red * 255).rounded())
    )
}

/// Absence of a GPU is a fact about the host, and every test below skips on it. This one makes
/// that visible: without it a machine with no Metal device would report a page of passes.
@Test
func thisHostHasAMetalDevice() {
    #expect(MTLCreateSystemDefaultDevice() != nil, "no Metal device: every render test below skipped")
}

/// The compile-time check the build cannot do.
///
/// SwiftPM does not compile `.metal` files, so the shader is source until something runs it. A
/// syntax error would otherwise first appear as a blank chart on a device.
@Test
func theShaderCompilesAndDeclaresBothFunctions() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let library = try device.makeLibrary(source: MetalShaderSource.source, options: nil)
    let names = Set(library.functionNames)
    #expect(names.contains(MetalShaderSource.vertexFunction))
    #expect(names.contains(MetalShaderSource.fragmentFunction))
}

@Test
func theBackgroundIsTheChromeColourExactly() throws {
    guard let target = MetalRenderTarget() else { return }
    let pixels = try target.render(prepared(LineChartSpec(series: Array(0..<8))))
    let expected = ChartChrome.light.background.encodedSRGB
    // Top-left corner: outside the plot rect, so nothing but the clear touches it.
    #expect(pixels[0] == UInt8((expected.blue * 255).rounded()))
    #expect(pixels[1] == UInt8((expected.green * 255).rounded()))
    #expect(pixels[2] == UInt8((expected.red * 255).rounded()))
    #expect(pixels[3] == 255)
}

/// Colours reach the GPU linear and the target encodes them, so a chart drawn through the shader
/// must be the same colour as one drawn through Core Graphics. Asserting the palette value exactly
/// is what makes this a check: the version of this test that compared "roughly blue" passed for
/// three different wrong colours.
@Test
func fullyCoveredPixelsAreExactlyThePaletteColour() throws {
    guard let target = MetalRenderTarget() else { return }
    let pixels = try target.render(prepared(LineChartSpec(series: [0], lineWidth: 4)))
    let expected = solidSeriesColours[0]
    var solid = 0
    for index in stride(from: 0, to: pixels.count, by: 4)
    where pixels[index] == expected.0 && pixels[index + 1] == expected.1 && pixels[index + 2] == expected.2 {
        solid += 1
    }
    #expect(solid > 1_000, "a four-point stroke should fill thousands of pixels; filled \(solid)")
}

@Test
func twoRendersOfTheSameFrameAreBitIdentical() throws {
    guard let target = MetalRenderTarget() else { return }
    let frame = prepared(LineChartSpec(series: Array(0..<8)))
    let first = try target.render(frame)
    let second = try target.render(frame)
    #expect(first.count == ComparisonImage.byteCount(scale: 1))
    #expect(first == second)
}

/// The experiment that separates a rendering difference from an antialiasing difference.
///
/// A two-point stroke centred on a whole coordinate covers exactly two rows of pixels, so no
/// coverage is partial and no rasteriser has anything to decide. Both backends must produce the
/// same bytes. When this passes and the general comparison does not, the remaining difference is
/// antialiasing and nothing else — measured here at 67.5 dB against 32.5 dB for the same chart at
/// the default one-and-a-half point stroke.
@Test
func withNoPartialCoverageBothRasterisersAgreeToTheByte() throws {
    guard let target = MetalRenderTarget() else { return }
    let flat = ArrayProvider(
        [(0..<2_000).map { Sample(carrier: Double($0) / 200, value: 0) }],
        metadata: [SeriesMetadata(name: "flat", unit: .fraction)]
    )
    let spec = LineChartSpec(series: [0], lineWidth: 2)
    var scratch: [Sample] = []
    let frame = FramePreparation.prepare(
        provider: flat, spec: spec, window: window, yDomain: yDomain,
        size: (width: Double(ComparisonImage.width), height: Double(ComparisonImage.height)),
        dark: false, measuring: ApproximateTextWidth(), scratch: &scratch
    )
    var referenceScratch: [Sample] = []
    guard let reference = OffscreenRenderTarget.render(
        provider: flat, spec: spec, window: window, yDomain: yDomain, scratch: &referenceScratch
    ) else {
        Issue.record("could not create a bitmap context")
        return
    }
    let metal = try target.render(frame)

    // The stroke's own rows, away from the chrome and from either end of the line.
    let width = ComparisonImage.width
    for y in 370..<386 {
        let index = (y * width + 500) * 4
        #expect(metal[index] == reference[index], "row \(y) blue")
        #expect(metal[index + 1] == reference[index + 1], "row \(y) green")
        #expect(metal[index + 2] == reference[index + 2], "row \(y) red")
    }
}

/// The comparison the project exists to make, now that a second rasteriser exists.
@Test
func theGPUDrawsTheSameChartAsCoreGraphics() throws {
    guard let target = MetalRenderTarget() else { return }
    let spec = LineChartSpec(series: Array(0..<8))
    let difference = StructuralDifference.between(
        reference: coreGraphicsReference(spec),
        candidate: try target.render(prepared(spec)),
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(difference.solidPixels > 5_000, "nothing was solid enough to compare")
    #expect(difference.agrees, "\(difference.solidMismatches) certain pixels disagree")
}

/// The instrument, checked by breaking the thing it measures.
///
/// Without these the test above says only that today's renderer passes today's threshold. Each row
/// is a renderer that is wrong in a way a chart library really can be wrong, and the criterion has
/// to reject every one of them while accepting the correct render above.
@Test(arguments: [
    (label: "one of eight series missing", spec: LineChartSpec(series: Array(0..<7)), shift: 0.0),
    (label: "shifted by one pixel", spec: LineChartSpec(series: Array(0..<8)), shift: 1.0),
    (label: "stroked at half width", spec: LineChartSpec(series: Array(0..<8), lineWidth: 0.75), shift: 0.0),
    (label: "stroked at double width", spec: LineChartSpec(series: Array(0..<8), lineWidth: 3), shift: 0.0),
])
func aWrongRenderIsRejected(_ testCase: (label: String, spec: LineChartSpec, shift: Double)) throws {
    guard let target = MetalRenderTarget() else { return }
    let difference = StructuralDifference.between(
        reference: coreGraphicsReference(LineChartSpec(series: Array(0..<8))),
        candidate: try target.render(prepared(testCase.spec, shiftedBy: testCase.shift)),
        width: ComparisonImage.width,
        height: ComparisonImage.height,
        solidColours: solidSeriesColours
    )
    #expect(!difference.agrees, "\(testCase.label) was accepted as equivalent")
}
