import BenchCore
import BenchRuntime
import Foundation
import SwiftUI
import Testing
@testable import CanvasBackend

private let window: ClosedRange<Carrier> = 0...10
private let yDomain: ClosedRange<Double> = -1.4...1.4
private let size = CGSize(width: 1024, height: 768)

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
            return Sample(carrier: time, value: amplitude * sin(2 * .pi * frequency * time + phase))
        })
        metadata.append(SeriesMetadata(name: "s\(index)", unit: .fraction))
    }
    return ArrayProvider(series, metadata: metadata)
}

/// Renders the view off screen through `ImageRenderer`, at 1x so a pixel in the result is a point
/// in the frame it was handed.
@MainActor
private func renderView(_ frame: CanvasFrame) -> [UInt8]? {
    let renderer = ImageRenderer(content: CanvasChartView(frame: frame).frame(width: size.width, height: size.height))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage, let data = cgImage.dataProvider?.data else { return nil }
    return [UInt8](data as Data)
}

/// `CanvasChartView` duplicates `OffscreenRenderTarget`'s chrome-stroking logic for SwiftUI's
/// `GraphicsContext` rather than a raw `CGContext`, and nothing else in the suite ever renders
/// this view — it is reachable only from the demo app. Without this, both a dropped axis and a
/// wrongly coloured stroke pass every other test in the file.
@Test
@MainActor
func theViewStrokesBothAxisLinesInTheChromeColour() {
    var scratch: [Sample] = []
    let frame = CanvasChartRenderer.buildFrame(
        provider: eightCurves(), spec: LineChartSpec(series: []), window: window, yDomain: yDomain,
        size: size, dark: false, scratch: &scratch
    )
    guard let pixels = renderView(frame) else {
        Issue.record("could not render the view")
        return
    }
    let expected = ChartChrome.light.axis.encodedSRGB
    let red = UInt8((expected.red * 255).rounded())
    let green = UInt8((expected.green * 255).rounded())
    let blue = UInt8((expected.blue * 255).rounded())
    var covered = 0
    for index in stride(from: 0, to: pixels.count, by: 4)
    where pixels[index] == red && pixels[index + 1] == green && pixels[index + 2] == blue {
        covered += 1
    }
    // Same bar as ``OffscreenRenderTargetTests.theAxesAreStrokedInTheChromeColour``: above what
    // either axis line alone covers (~960 px, the bottom one), below both together (~1 696 px).
    #expect(covered > 1_200, "only \(covered) axis-coloured pixels; the axes may not have been drawn")
}
