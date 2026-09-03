/// Locating a carrier window inside an ordered run of carriers.
///
/// One implementation, used by every provider. The window moves each frame and the buffer does
/// not, so this must not cost anything proportional to the buffer — and an off-by-one here shows
/// up as a chart that is one sample wrong, which is exactly the kind of defect a second copy of
/// the same search would let survive in whichever provider had no test.
///
/// - SeeAlso: Docs/methods/buffers-and-windows.md
public enum CarrierSearch {
    /// Half-open index range of the carriers falling inside `window`, both ends inclusive.
    ///
    /// - Precondition: `carriers` is sorted ascending.
    /// - Complexity: O(log *n*).
    public static func indices<C: RandomAccessCollection>(
        of carriers: C,
        within window: ClosedRange<Carrier>
    ) -> Range<Int> where C.Element == Carrier, C.Index == Int {
        let start = lowerBound(carriers, notLessThan: window.lowerBound)
        // `nextUp` rather than a second comparison mode: the window is inclusive at the top, and
        // the smallest representable step past it turns that into the half-open bound a slice
        // needs without a separate upper-bound search.
        let end = lowerBound(carriers, notLessThan: window.upperBound.nextUp)
        return start..<Swift.max(start, end)
    }

    /// Index of the first element not less than `value`, or the count when there is none.
    static func lowerBound<C: RandomAccessCollection>(
        _ carriers: C,
        notLessThan value: Carrier
    ) -> Int where C.Element == Carrier, C.Index == Int {
        var low = carriers.startIndex
        var high = carriers.endIndex
        while low < high {
            let middle = low + (high - low) / 2
            if carriers[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
