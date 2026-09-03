import BenchCore
import CoreGraphics
import Foundation

extension PaletteColor {
    /// This colour as a `CGColor` in **sRGB**, with the components gamma-encoded.
    ///
    /// Not `CGColor(red:green:blue:alpha:)`. That initializer is `CGColorCreateGenericRGB`: it tags
    /// the colour `kCGColorSpaceGenericRGB`, which is not sRGB, so Core Graphics colour-matches on
    /// the way into an sRGB destination and every channel lands elsewhere than intended. Measured
    /// on series 0 of the categorical palette, which should rasterise to B=166 G=107 R=0: the
    /// generic path produced B=181 G=127 R=0 — fifteen and twenty levels off, more than twice this
    /// project's own 8/255 equivalence tolerance.
    ///
    /// One implementation for every backend on purpose. Two backends constructing colours
    /// separately were wrong in identical ways, which is exactly the failure the equivalence check
    /// cannot see: both sides shift together and the difference between them stays zero.
    public var cgColor: CGColor {
        let encoded = encodedSRGB
        return CGColor(
            colorSpace: Self.sRGB,
            components: [
                CGFloat(encoded.red), CGFloat(encoded.green), CGFloat(encoded.blue), 1,
            ]
        ) ?? CGColor(gray: 0, alpha: 1)
    }

    /// The destination space every render target in this package pins.
    ///
    /// Named rather than left to `CGColorSpaceCreateDeviceRGB()`, which on Apple platforms today
    /// rasterises identically — measured, and a mutation swapping the two is caught by no test —
    /// but whose meaning is defined by the device rather than by a standard. A results file
    /// outlives the platform that produced it.
    public static let sRGB: CGColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
}
