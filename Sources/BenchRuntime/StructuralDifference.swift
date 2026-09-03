import Foundation

/// Whether two renders drew the same shapes, when they did not use the same rasteriser.
///
/// ``ImageDifference`` asks whether two images are the same to within rounding, and that is the
/// right question only while both sides rasterise through the same code — as the first two
/// backends did, which is why they agreed bit-for-bit and why a mistake they shared went unseen.
/// A GPU renderer cannot meet that threshold and should not be asked to: multisampling quantises
/// coverage to a fixed number of steps, while Core Graphics computes it analytically, so an edge
/// pixel legitimately differs by far more than eight parts in 255. Measured on this project's
/// reference chart: 32.5 dB and a worst channel of 159, with every fully covered pixel identical.
///
/// So the question changes. Coverage may differ wherever coverage is partial; it may not differ
/// where the reference is certain. Two things are checked:
///
/// The criterion is ``solidMismatches`` being zero: a pixel the reference filled completely must
/// be filled the same way. It was chosen by breaking a working renderer four ways and measuring,
/// not by picking a threshold that the current code happened to pass. On this project's reference
/// chart, against the Core Graphics reference:
///
/// | render | solid mismatches of 8188 |
/// |---|---|
/// | correct | 0 |
/// | one of eight series dropped | 979 |
/// | shifted by one pixel | 7975 |
/// | stroked at half width | 7037 |
/// | stroked at double width | 139 |
///
/// ``mismatchesAwayFromEdges`` is reported and **is not a criterion**. The correct render scores
/// 133 on it, because where eight curves overlap no neighbourhood is free of edges and the
/// heuristic has nowhere to anchor. It separates the cases too — 913 and up for the broken ones —
/// but only with a threshold, and a threshold chosen to make today's code pass is not a check.
public struct StructuralDifference: Sendable, Equatable {
    /// Pixels the reference rendered at full coverage that the candidate rendered differently.
    public let solidMismatches: Int
    /// Pixels the reference rendered at full coverage, whether or not they matched.
    public let solidPixels: Int
    /// Pixels differing while no edge lies within one pixel of them in either image.
    public let mismatchesAwayFromEdges: Int
    /// Every pixel differing by more than the tolerance, for context.
    public let differingPixels: Int

    /// True when no pixel the reference was certain about disagreed.
    ///
    /// Silent about edges on purpose: that is where two rasterisers are allowed to differ, and
    /// where this project's two Core Graphics backends could never have differed at all.
    public var agrees: Bool { solidMismatches == 0 }

    /// Compares two premultiplied BGRA buffers of the same size.
    ///
    /// - Parameters:
    ///   - solidColours: Colours that count as full coverage, as BGR triples. A pixel matching one
    ///     of these in the reference is a pixel the reference was certain about.
    ///   - tolerance: Channel difference treated as rounding. Eight of 255, as elsewhere.
    /// - Complexity: O(*n*) with a 3×3 neighbourhood, no allocation beyond one edge map.
    public static func between(
        reference: [UInt8],
        candidate: [UInt8],
        width: Int,
        height: Int,
        solidColours: [(UInt8, UInt8, UInt8)],
        tolerance: Int = 8
    ) -> StructuralDifference {
        precondition(reference.count == candidate.count, "comparing buffers of different sizes compares nothing")
        precondition(reference.count == width * height * 4, "buffer does not match the stated size")

        // A pixel is "uncertain" when it or a neighbour differs between the two images by any
        // amount; edges are exactly where the two rasterisers may legitimately disagree, and they
        // are found from the data rather than from a guess about where lines were drawn.
        var uncertain = [Bool](repeating: false, count: width * height)
        for index in 0..<(width * height) {
            let byte = index * 4
            var worst = 0
            for channel in 0..<3 {
                worst = max(worst, abs(Int(reference[byte + channel]) - Int(candidate[byte + channel])))
            }
            uncertain[index] = worst > 0
        }

        var solidMismatches = 0
        var solidPixels = 0
        var awayFromEdges = 0
        var differing = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let byte = index * 4
                var worst = 0
                for channel in 0..<3 {
                    worst = max(worst, abs(Int(reference[byte + channel]) - Int(candidate[byte + channel])))
                }
                let isSolid = solidColours.contains {
                    reference[byte] == $0.0 && reference[byte + 1] == $0.1 && reference[byte + 2] == $0.2
                }
                if isSolid { solidPixels += 1 }
                guard worst > tolerance else { continue }
                differing += 1
                if isSolid { solidMismatches += 1 }

                // Near an edge means: some neighbour agreed exactly. A run of differing pixels
                // wider than a rasteriser's edge cannot be explained by the edge.
                var neighbourAgreed = false
                for dy in -1...1 where !neighbourAgreed {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        if !uncertain[ny * width + nx] { neighbourAgreed = true; break }
                    }
                }
                if !neighbourAgreed { awayFromEdges += 1 }
            }
        }

        return StructuralDifference(
            solidMismatches: solidMismatches,
            solidPixels: solidPixels,
            mismatchesAwayFromEdges: awayFromEdges,
            differingPixels: differing
        )
    }
}
