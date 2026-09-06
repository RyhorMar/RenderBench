import BenchCore
import BenchRuntime
import BenchScales

/// The pinned size and format of every comparison render, and the one way to produce one from a
/// provider without going through another backend.
///
/// The reference itself — `CoreGraphicsReference` — lives in `BenchRuntime`, reachable by every
/// backend without depending on this one. What stays here is Canvas-specific: turning a data
/// provider into that reference at this target's fixed size, the same way the on-screen chart is
/// built, so a caller who only has a provider does not have to know about `FramePreparation`.
public enum OffscreenRenderTarget {
    /// Width in points of every comparison render.
    public static let width = ComparisonImage.width
    /// Height in points of every comparison render.
    public static let height = ComparisonImage.height
    /// Bytes per pixel: 8-bit BGRA, premultiplied.
    public static let bytesPerPixel = ComparisonImage.bytesPerPixel

    /// Prepares and renders in one step, at this target's fixed size.
    public static func render(
        provider: some ChartDataProvider,
        spec: LineChartSpec,
        window: ClosedRange<Carrier>,
        yDomain: ClosedRange<Double>,
        dark: Bool = false,
        scratch: inout [Sample]
    ) -> [UInt8]? {
        let prepared = FramePreparation.prepare(
            provider: provider,
            spec: spec,
            window: window,
            yDomain: yDomain,
            size: (width: Double(width), height: Double(height)),
            chrome: .forScheme(dark: dark),
            scale: 1,
            dark: dark,
            measuring: ApproximateTextWidth(),
            scratch: &scratch
        )
        return CoreGraphicsReference.render(prepared)
    }
}
