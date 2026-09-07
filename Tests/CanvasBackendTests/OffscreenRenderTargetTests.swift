import BenchCore
import BenchDownsampling
import BenchRuntime
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CanvasBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4

/// A signal whose alternate samples differ maximally, so that a renderer drawing half of them
/// produces a picture no threshold can call equivalent. A gentle signal would not: dropping every
/// other sample of a slow curve is exactly what downsampling does on purpose.
private func zigzag(count: Int, rate: Double, keepingEveryOther: Bool = false) -> ArrayProvider {
    var samples: [Sample] = []
    for index in 0..<count where !keepingEveryOther || index % 2 == 0 {
        samples.append(Sample(carrier: Double(index) / rate, value: index % 2 == 0 ? 1 : -1))
    }
    return ArrayProvider([samples], metadata: [SeriesMetadata(name: "z", unit: .fraction)])
}

/// Eight phase-shifted curves — the picture the stored reference holds.
///
/// A legible chart, deliberately, because a reference image is only useful if a difference in it
/// is visible to whoever is looking at the failure. The zigzag above is the opposite: a solid
/// block, ideal for proving that dropped points are detected and useless as something to look at.
private func eightCurves() -> ArrayProvider {
    let rate = 1_000.0
    var series: [[Sample]] = []
    var metadata: [SeriesMetadata] = []
    for index in 0..<8 {
        let amplitude = 1.0 - Double(index) * 0.06
        let frequency = 0.25 + Double(index) * 0.02
        let phase = Double(index) * .pi / 5
        series.append((0..<10_000).map { step in
            let time = Double(step) / rate
            return Sample(
                carrier: time,
                value: amplitude * sin(2 * .pi * frequency * time + phase)
            )
        })
        metadata.append(SeriesMetadata(name: "s\(index)", unit: .fraction))
    }
    return ArrayProvider(series, metadata: metadata)
}

private func render(_ provider: ArrayProvider, policy: DownsamplePolicy = .minMax) -> [UInt8] {
    var scratch: [Sample] = []
    guard let pixels = OffscreenRenderTarget.render(
        provider: provider,
        spec: LineChartSpec(series: Array(0..<provider.seriesCount), policy: policy),
        window: window,
        yDomain: yDomain,
        scratch: &scratch
    ) else {
        Issue.record("could not create a bitmap context")
        return []
    }
    return pixels
}

/// The property the whole comparison rests on. Two renders of the same input must produce the same
/// bytes, or a difference between backends cannot be told from noise in the rasteriser.
@Test
func theReferenceChartRendersDeterministicallyToo() {
    let provider = eightCurves()
    #expect(render(provider) == render(provider))
}

@Test
func twoRendersOfTheSameFrameAreBitIdentical() {
    let provider = zigzag(count: 10_000, rate: 1_000)
    let first = render(provider)
    let second = render(provider)

    #expect(first.isEmpty == false)
    #expect(first.count == OffscreenRenderTarget.width * OffscreenRenderTarget.height * 4)
    #expect(first == second)

    let difference = ImageDifference.between(reference: first, candidate: second)
    #expect(difference.isBitIdentical)
    #expect(difference.peakSignalToNoiseRatio == .infinity)
    #expect(difference.fractionBeyondTolerance == 0)
}

/// The acceptance criterion for this card: a renderer that drew half the points it was given is
/// detected, not tolerated.
@Test
func aRendererThatDrawsHalfThePointsIsNotEquivalent() {
    let full = render(zigzag(count: 10_000, rate: 1_000))
    let halved = render(zigzag(count: 10_000, rate: 1_000, keepingEveryOther: true))

    let difference = ImageDifference.between(reference: full, candidate: halved)
    #expect(difference.isBitIdentical == false)
    #expect(difference.isEquivalent() == false)
    #expect(difference.fractionBeyondTolerance > 0.02)
}

/// The two bars catch different failures, so a case that clears one and not the other must be
/// judged not equivalent. Here the difference is small in area and large in magnitude.
@Test
func aFewLargeDifferencesFailOnTheRatioEvenWhenTheAreaIsSmall() {
    var reference = [UInt8](repeating: 128, count: 4_000)
    var candidate = reference
    for index in 0..<20 { candidate[index] = 255 }

    let difference = ImageDifference.between(reference: reference, candidate: candidate)
    #expect(difference.fractionBeyondTolerance < 0.02)
    #expect(difference.maximumChannelDelta == 127)

    // Many small differences, spread out: clears the ratio, fails on the area.
    reference = [UInt8](repeating: 128, count: 4_000)
    candidate = reference.map { $0 + 12 }
    let spread = ImageDifference.between(reference: reference, candidate: candidate)
    #expect(spread.fractionBeyondTolerance > 0.02)
    #expect(spread.isEquivalent() == false)
}

@Test
func identicalBuffersReportNoDifferenceAtAll() {
    let buffer = [UInt8](repeating: 77, count: 1_000)
    let difference = ImageDifference.between(reference: buffer, candidate: buffer)
    #expect(difference.isBitIdentical)
    #expect(difference.maximumChannelDelta == 0)
    #expect(difference.peakSignalToNoiseRatio == .infinity)
    #expect(difference.isEquivalent())
}

/// Differences at or below the tolerance are rounding in the rasteriser, not different drawing.
@Test
func differencesWithinToleranceDoNotCount() {
    let reference = [UInt8](repeating: 100, count: 1_000)
    let candidate = [UInt8](repeating: 108, count: 1_000)
    let difference = ImageDifference.between(reference: reference, candidate: candidate)
    #expect(difference.maximumChannelDelta == 8)
    #expect(difference.fractionBeyondTolerance == 0)
    #expect(difference.isBitIdentical == false)
}

/// The stored reference image. Regenerate deliberately with `WRITE_GOLDENS=1 swift test`, never
/// automatically: a golden that rewrites itself when it fails records the bug as the new truth.
@Test
func theStoredReferenceStillMatches() throws {
    let goldens = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Goldens")
    let file = goldens.appending(path: "canvas-strip-chart.png")
    let pixels = render(eightCurves())

    if ProcessInfo.processInfo.environment["WRITE_GOLDENS"] != nil {
        try FileManager.default.createDirectory(at: goldens, withIntermediateDirectories: true)
        #expect(CoreGraphicsReference.writePNG(pixels, to: file))
        return
    }

    guard FileManager.default.fileExists(atPath: file.path) else {
        Issue.record("no stored reference; regenerate with WRITE_GOLDENS=1 swift test")
        return
    }

    // Not a raw byte comparison of the two PNG files. A first version of this test tried that and
    // was wrong twice over: an encoder-level byte match is fragile to any sub-pixel rounding change
    // that alters nothing anyone would call a regression, and — found only by sampling the process
    // while it hung — Swift Testing's `#expect(a == b)` on two ~240 KB `Data` values that actually
    // differ runs its collection-diffing machinery, an O(n·d) edit-distance search that pegs a core
    // for minutes. Decoding both to pixels and comparing through this project's own `ImageDifference`
    // — the same instrument and the same tolerance every cross-backend comparison already trusts —
    // both avoids that hang and answers the question this test exists to ask: does the picture still
    // match, not does the compressed file still match.
    guard let storedPixels = decodePNGToPinnedPixels(file) else {
        Issue.record("could not decode the stored reference at \(file.path)")
        return
    }
    let difference = ImageDifference.between(reference: storedPixels, candidate: pixels)
    let message = "\(difference.fractionBeyondTolerance) of channel samples differ by more than "
        + "the tolerance (worst: \(difference.maximumChannelDelta)/255); inspect \(file.path) "
        + "before regenerating it with WRITE_GOLDENS=1 swift test"
    #expect(difference.fractionBeyondTolerance == 0, Comment(rawValue: message))
}

/// Decodes a stored PNG back into the same premultiplied-BGRA, sRGB pixel layout every offscreen
/// render in this package produces, so it can be compared against one directly.
///
/// `interpolationQuality = .none` is not a default worth trusting silently: at anything but exact
/// 1:1 scale, `CGContext.draw` is free to resample, which would compare the resampler against the
/// renderer instead of one render against another.
private func decodePNGToPinnedPixels(_ url: URL) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width, height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: PaletteColor.sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

/// Each bar must be load-bearing on its own, so each needs a case that only it rejects. Without
/// these, removing either threshold leaves every test passing.
@Test
func theAreaBarRejectsManySmallDifferencesOnItsOwn() {
    let reference = [UInt8](repeating: 128, count: 100_000)
    var candidate = reference
    // Three per cent of samples, nine levels apart: over the 2 % area bar, comfortably inside the
    // 35 dB ratio bar.
    for index in stride(from: 0, to: 3_000, by: 1) { candidate[index] = 137 }

    let difference = ImageDifference.between(reference: reference, candidate: candidate)
    #expect(difference.fractionBeyondTolerance > 0.02)
    #expect(difference.peakSignalToNoiseRatio > 35)
    #expect(difference.isEquivalent() == false)
}

@Test
func theRatioBarRejectsAFewLargeDifferencesOnItsOwn() {
    let reference = [UInt8](repeating: 40, count: 100_000)
    var candidate = reference
    // Half a per cent of samples, two hundred levels apart: inside the area bar, far under the
    // ratio bar.
    for index in stride(from: 0, to: 500, by: 1) { candidate[index] = 240 }

    let difference = ImageDifference.between(reference: reference, candidate: candidate)
    #expect(difference.fractionBeyondTolerance < 0.02)
    #expect(difference.peakSignalToNoiseRatio < 35)
    #expect(difference.isEquivalent() == false)
}

/// Colour, exactly. Series 0 is sRGB 0x006BA6, so every fully covered pixel of its stroke is
/// B=166 G=107 R=0 and nothing else.
///
/// Two bugs hid behind a threshold here. Passing linear components darkened the stroke to about
/// blue 97; building the colour with `CGColor(red:green:blue:alpha:)` — which is Generic RGB, not
/// sRGB — shifted it to 181. A `> 150` bound passed for the second of those, and for a partially
/// covered pixel of the first. An exact assertion on fully covered pixels admits neither.
@Test
func strokesAreDrawnInTheExactPaletteColour() {
    let pixels = render(zigzag(count: 4_000, rate: 400))
    var covered = 0
    var wrong = 0
    // Premultiplied BGRA, little-endian: bytes run blue, green, red, alpha. Red is zero for this
    // colour, so red == 0 selects pixels the stroke covers completely — anything partially
    // covered has blended some white in and carries a non-zero red.
    for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 2] == 0 {
        covered += 1
        if pixels[index] != 166 || pixels[index + 1] != 107 { wrong += 1 }
    }
    #expect(covered > 10_000, "only \(covered) fully covered pixels to judge")
    #expect(wrong == 0, "\(wrong) of \(covered) covered pixels are not the palette colour")
}

/// The axes reach the bitmap in the chrome's own colour. Rendered with no series at all, since two
/// axis lines are a small fraction of a 1024×768 image — small enough that the cross-backend
/// tolerance let them go missing without either equivalence check noticing.
@Test
func theAxesAreStrokedInTheChromeColour() {
    var scratch: [Sample] = []
    guard let pixels = OffscreenRenderTarget.render(
        provider: eightCurves(), spec: LineChartSpec(series: []), window: window, yDomain: yDomain, scratch: &scratch
    ) else {
        Issue.record("could not create a bitmap context")
        return
    }
    let expected = ChartChrome.light.axis.encodedSRGB
    let blue = UInt8((expected.blue * 255).rounded())
    let green = UInt8((expected.green * 255).rounded())
    let red = UInt8((expected.red * 255).rounded())
    var covered = 0
    for index in stride(from: 0, to: pixels.count, by: 4)
    where pixels[index] == blue && pixels[index + 1] == green && pixels[index + 2] == red {
        covered += 1
    }
    // Comfortably above what either axis line alone would cover (the shorter, the bottom one, at
    // roughly 960 pixels) and below both together (roughly 1 696): only their sum clears it.
    #expect(covered > 1_200, "only \(covered) axis-coloured pixels; the axes may not have been drawn")
}

/// Antialiasing is pinned on, and a comparison run without it would judge two backends on hard
/// edges — hiding exactly the sub-pixel differences the tolerance exists to absorb.
@Test
func antialiasingProducesIntermediateEdgePixels() {
    // The dense signal, not the reference chart. Measured with antialiasing on and off: the zigzag
    // goes from 192 701 partially covered pixels to 10, while the eight curves only fall from
    // 26 897 to 4 327 — a threshold placed on the second is a threshold that passes either way,
    // which is what the first version of this test did.
    let pixels = render(zigzag(count: 4_000, rate: 400))
    var intermediate = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let blue = Int(pixels[index])
        if blue > 190 && blue < 250 { intermediate += 1 }
    }
    #expect(intermediate > 10_000, "only \(intermediate) partially covered pixels")
}
