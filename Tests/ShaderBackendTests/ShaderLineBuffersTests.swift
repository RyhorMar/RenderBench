import BenchCore
import BenchRuntime
import Foundation
import Testing
@testable import ShaderBackend

/// Decodes a packed buffer back into `Float32` pairs, reading each 4-byte component least-
/// significant-byte first — the layout `ShaderLineBuffers.pack` must produce for `device const
/// float2 *` to read it correctly on every device this project targets. Built independently of
/// `pack` itself (plain byte arithmetic, not `withUnsafeBytes`), so a bug shared between the two
/// could not cancel itself out and pass silently.
private func decode(_ data: Data) -> [(Float32, Float32)] {
    let bytes = [UInt8](data)
    var result: [(Float32, Float32)] = []
    var index = 0
    while index + ShaderLineBuffers.pointStride <= bytes.count {
        func littleEndianFloat(at offset: Int) -> Float32 {
            let bits = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return Float32(bitPattern: bits)
        }
        result.append((littleEndianFloat(at: index), littleEndianFloat(at: index + 4)))
        index += ShaderLineBuffers.pointStride
    }
    return result
}

@Test
func pointStrideIsEightBytes() {
    #expect(ShaderLineBuffers.pointStride == 8)
}

@Test
func packProducesOneEightByteEntryPerPointInOrder() {
    let points = [CGPoint(x: 1, y: 2), CGPoint(x: -3.5, y: 40)]
    let data = ShaderLineBuffers.pack(points)
    #expect(data.count == points.count * ShaderLineBuffers.pointStride)

    let decoded = decode(data)
    #expect(decoded.count == points.count)
    #expect(decoded[0] == (1, 2))
    #expect(decoded[1] == (-3.5, 40))
}

@Test
func packOfNoPointsIsEmpty() {
    #expect(ShaderLineBuffers.pack([]).isEmpty)
}

/// Without this, a mutation that dropped the projection entirely — handing the shader normalised
/// `0...1` coordinates instead of plot-space ones — would still pass every other test here.
@Test
func runsProjectPointsIntoPlotSpace() {
    let plot = PlotRect(x: 100, y: 50, width: 200, height: 80)
    let series = PreparedSeries(
        index: 0,
        colour: Palette.colour(forSeries: 0, dark: false),
        points: [
            PlottedPoint(x: 0, y: 0, isBreak: false),
            PlottedPoint(x: 1, y: 1, isBreak: false),
        ]
    )
    let runs = ShaderLineBuffers.runs(for: series, plot: plot)
    #expect(runs.count == 1)
    let decoded = decode(runs[0])
    #expect(decoded.count == 2)
    #expect(decoded[0] == (100, 130))
    #expect(decoded[1] == (300, 50))
}

/// A break must end one run and start a new one rather than becoming a phantom segment that
/// connects across the gap — the one design decision this card makes on top of the brief.
@Test
func aBreakSplitsASeriesIntoTwoRunsRatherThanOneWithAMarker() {
    let plot = PlotRect(x: 0, y: 0, width: 100, height: 100)
    let series = PreparedSeries(
        index: 0,
        colour: Palette.colour(forSeries: 0, dark: false),
        points: [
            PlottedPoint(x: 0.0, y: 0.0, isBreak: false),
            PlottedPoint(x: 0.1, y: 0.1, isBreak: false),
            PlottedPoint(x: 0.2, y: 0.2, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.6, y: 0.6, isBreak: false),
            PlottedPoint(x: 0.7, y: 0.7, isBreak: false),
        ]
    )
    let runs = ShaderLineBuffers.runs(for: series, plot: plot)
    #expect(runs.count == 2)
    #expect(decode(runs[0]).count == 3)
    #expect(decode(runs[1]).count == 2)
}

/// A run of one point has no segment for the shader to draw. Packing it anyway would cost a
/// `colorEffect` invocation that can only ever report zero coverage.
@Test
func aRunOfOnePointIsDroppedRatherThanPacked() {
    let plot = PlotRect(x: 0, y: 0, width: 100, height: 100)
    let series = PreparedSeries(
        index: 0,
        colour: Palette.colour(forSeries: 0, dark: false),
        points: [
            PlottedPoint(x: 0.1, y: 0.1, isBreak: false),
            PlottedPoint(x: 0, y: 0, isBreak: true),
            PlottedPoint(x: 0.5, y: 0.5, isBreak: false),
            PlottedPoint(x: 0.6, y: 0.6, isBreak: false),
        ]
    )
    let runs = ShaderLineBuffers.runs(for: series, plot: plot)
    #expect(runs.count == 1)
    #expect(decode(runs[0]).count == 2)
}

@Test
func runsOfAnEmptySeriesIsEmpty() {
    let series = PreparedSeries(index: 0, colour: Palette.colour(forSeries: 0, dark: false), points: [])
    #expect(ShaderLineBuffers.runs(for: series, plot: PlotRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
}
