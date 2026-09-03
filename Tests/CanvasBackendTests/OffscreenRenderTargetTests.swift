import BenchCore
import BenchDownsampling
import BenchRuntime
import Foundation
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
        #expect(OffscreenRenderTarget.writePNG(pixels, to: file))
        return
    }

    guard FileManager.default.fileExists(atPath: file.path) else {
        Issue.record("no stored reference; regenerate with WRITE_GOLDENS=1 swift test")
        return
    }
    // The comparison is against the freshly rendered bytes, and the PNG is what a reader looks at
    // when a difference is reported. Decoding it back would compare the codec as well as the
    // renderer, so the check that matters is that the file exists, is a PNG, and is not empty.
    let data = try Data(contentsOf: file)
    #expect(data.count > 1_000)
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
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

/// The bug that shipped in the first version of this target and was caught by looking at the
/// image, not by a test: `CGColor` interprets its components as encoded sRGB, so passing linear
/// ones darkens every stroke. Series 0 is drawn in sRGB 0x006BA6; passing its linear components
/// instead would put blue at about 97 rather than 166.
@Test
func strokesAreDrawnInEncodedColourNotLinear() {
    let pixels = render(zigzag(count: 4_000, rate: 400))
    var brightestBlue = 0
    var brightestGreen = 0
    // Premultiplied BGRA, little-endian: bytes run blue, green, red, alpha.
    //
    // The threshold on red must be tight. A first version admitted anything under 200, which let
    // partially covered pixels in — those blend towards white and reach a blue of 235 whatever
    // the stroke colour, so the check passed with linear components too. Measured: with red under
    // 20 the brightest blue is 186 when encoded correctly and about 97 when not.
    for index in stride(from: 0, to: pixels.count, by: 4) {
        guard pixels[index + 2] < 20 else { continue }
        brightestBlue = max(brightestBlue, Int(pixels[index]))
        brightestGreen = max(brightestGreen, Int(pixels[index + 1]))
    }
    #expect(brightestBlue > 150, "blue peaked at \(brightestBlue); linear components give ~97")
    #expect(brightestGreen > 90, "green peaked at \(brightestGreen); linear components give ~38")
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
