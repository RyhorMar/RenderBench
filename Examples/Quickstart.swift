import BenchCore

/// The README quickstart, compiled by CI so that it cannot rot.
///
/// The contract exercised here is the whole promise of the package: a consumer draws samples
/// they already hold, without adopting a ring buffer, a frame clock, or any isolation of ours.
/// The moment this file needs an engine type to compile, the public API has failed at its job.
public enum Quickstart {
    /// Wraps readings from a caller's own store and reads back one ten-second window.
    public static func lastTenSeconds(
        of readings: [(seconds: Double, psi: Double)]
    ) -> (points: Int, label: String) {
        let provider = ArrayProvider(
            [readings.map { Sample(carrier: $0.seconds, value: $0.psi) }],
            metadata: [
                SeriesMetadata(
                    name: "Wellhead pressure",
                    unit: .psig,
                    validRange: 0...10_000,
                    provenance: .measured
                )
            ]
        )
        guard let extent = provider.carrierExtent else { return (0, "") }
        let window = (extent.upperBound - 10)...extent.upperBound
        let points = provider.withSeries(0, in: window) { $0.count }
        return (points, provider.metadata(at: 0).axisLabel)
    }
}
