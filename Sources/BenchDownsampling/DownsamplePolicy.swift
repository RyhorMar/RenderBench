/// How a series is reduced to the number of points a display can actually resolve.
///
/// The choice is not a performance knob. Each policy discards different information, and the
/// one that flatters a benchmark is usually the one that lies to the reader.
public enum DownsamplePolicy: String, Sendable, Codable, CaseIterable {
    /// Per-bucket minimum and maximum, both emitted at the carrier position where they occurred.
    ///
    /// The default. It is the only policy here that preserves the envelope of a signal whose
    /// period is shorter than one pixel column, which is the normal case for a 400 Hz carrier
    /// in a ten-second window.
    case minMax

    /// Largest-Triangle-Three-Buckets, computed in normalised screen space.
    ///
    /// Keeps the samples that contribute most to the perceived shape. Collapses envelopes, so it
    /// must not be used when the reader judges amplitude, and must never feed a numerical step —
    /// derivative, FFT or curve fitting — because it is not band-limited.
    case lttb

    /// Every sample is submitted. Present so that the other two can be measured against a
    /// baseline that is known to be faithful, whatever it costs.
    case none
}
