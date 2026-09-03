import BenchCore

/// The README quickstart, compiled by CI so that it cannot rot.
///
/// The contract this file exercises is the whole promise of the package: a consumer draws their
/// own array without adopting the ring buffer, the frame clock or any isolation of ours. The
/// moment this file needs an engine type to compile, the public API has failed at its job.
public enum Quickstart {
    /// Converts readings into the sample form every backend accepts.
    public static func samples(from readings: [(seconds: Double, psi: Double)]) -> [Sample] {
        readings.map { Sample(carrier: $0.seconds, value: $0.psi) }
    }
}
