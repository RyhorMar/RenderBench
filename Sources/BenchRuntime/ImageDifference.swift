import Foundation

/// How far two rendered frames are apart.
///
/// This exists to answer one question before any timing is compared: did the two backends draw the
/// same picture? A backend that quietly dropped points, lowered its antialiasing or skipped a fill
/// wins every benchmark it enters, so a timing comparison that has not passed this is not a
/// comparison — it is a race with different rules for each runner.
///
/// - SeeAlso: Docs/methods/equivalence.md
public struct ImageDifference: Sendable, Equatable {
    /// Fraction of channel samples differing by more than the tolerance, in `0...1`.
    ///
    /// Counted per channel rather than per pixel: a pixel whose blue alone is wrong is a real
    /// difference, and per-pixel counting hides how much of it is wrong.
    public let fractionBeyondTolerance: Double
    /// Peak signal-to-noise ratio in decibels, or `.infinity` for identical images.
    public let peakSignalToNoiseRatio: Double
    /// Largest absolute channel difference, in `0...255`.
    public let maximumChannelDelta: Int
    /// True when the two buffers are byte-for-byte equal.
    public let isBitIdentical: Bool

    /// Compares two 8-bit buffers of equal length.
    ///
    /// - Parameters:
    ///   - reference: The picture the other one is judged against.
    ///   - candidate: The picture under test.
    ///   - tolerance: Channel difference treated as noise rather than difference. The project's
    ///     threshold is `8` of 255: below it a difference is attributable to rounding in the
    ///     rasteriser, above it something was drawn differently.
    /// - Precondition: the buffers have equal, non-zero length.
    /// - Complexity: O(*n*), one pass, no allocation.
    public static func between(
        reference: [UInt8],
        candidate: [UInt8],
        tolerance: Int = 8
    ) -> ImageDifference {
        precondition(
            reference.count == candidate.count,
            "comparing buffers of different sizes compares nothing"
        )
        precondition(!reference.isEmpty, "an empty buffer has no difference to report")
        precondition(tolerance >= 0, "a negative tolerance is not a tolerance")

        var beyond = 0
        var squaredError = 0.0
        var worst = 0
        var identical = true

        for index in reference.indices {
            let delta = Int(reference[index]) - Int(candidate[index])
            let magnitude = abs(delta)
            if magnitude != 0 { identical = false }
            if magnitude > tolerance { beyond += 1 }
            if magnitude > worst { worst = magnitude }
            squaredError += Double(delta * delta)
        }

        let meanSquaredError = squaredError / Double(reference.count)
        // Identical images report infinity, and no special case is needed to say so: IEEE
        // division by zero gives infinity, and its logarithm follows. A guard was here until a
        // mutation run showed it could be inverted with no test noticing — the mutation was
        // equivalent because the branch was redundant, which is worth knowing rather than
        // silencing.
        //
        // Infinity rather than a large finite number is deliberate: a finite stand-in invites a
        // threshold comparison that passes silently for images which are merely close.
        let psnr = 10 * log10(255 * 255 / meanSquaredError)

        return ImageDifference(
            fractionBeyondTolerance: Double(beyond) / Double(reference.count),
            peakSignalToNoiseRatio: psnr,
            maximumChannelDelta: worst,
            isBitIdentical: identical
        )
    }

    /// Whether this difference is small enough to call the two pictures the same.
    ///
    /// Both bars must clear, because each catches what the other misses: the fraction catches many
    /// small differences spread over the frame, the ratio catches a few large ones concentrated in
    /// a corner. The thresholds are the project's, and they are conventions rather than results —
    /// stated here so nobody has to guess where they came from.
    public func isEquivalent(
        maximumFractionBeyondTolerance: Double = 0.02,
        minimumPeakSignalToNoiseRatio: Double = 35
    ) -> Bool {
        fractionBeyondTolerance <= maximumFractionBeyondTolerance
            && peakSignalToNoiseRatio >= minimumPeakSignalToNoiseRatio
    }
}
