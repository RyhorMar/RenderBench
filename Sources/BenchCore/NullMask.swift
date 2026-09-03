/// Which positions of a series carry no measurement.
///
/// Rotates with the data it describes, so a gap stays attached to its sample as the window moves.
/// Represented as one `Bool` per position rather than as packed bits: the packed form is a real
/// optimisation, but nothing here has been measured yet, and an unmeasured optimisation in a
/// project about measurement would be the wrong kind of irony. The representation is private, so
/// packing it later changes no caller.
public struct NullMask: Sendable {
    private var flags: RingBuffer<Bool>

    /// Number of positions described.
    public var count: Int { flags.count }

    public init(capacity: Int) {
        self.flags = RingBuffer(capacity: capacity, filledWith: false)
    }

    /// Records whether the next position is a gap.
    public mutating func push(isGap: Bool) {
        flags.push(isGap)
    }

    /// True when the position `offset` after the oldest carries no measurement.
    public subscript(offset: Int) -> Bool { flags[offset] }

    /// Borrows the flags, oldest first, as one contiguous run.
    public func withUnsafeFlags<R>(_ body: (UnsafeBufferPointer<Bool>) -> R) -> R {
        flags.withUnsafeSnapshot(body)
    }

    /// Ranges of consecutive positions that do carry measurements.
    ///
    /// A renderer draws one polyline per range and lifts the pen between them; a downsampler
    /// treats each range separately so that no bucket spans a dropout. The count of ranges equals
    /// the count of uninterrupted stretches in the input, which is what the tests assert.
    ///
    /// - Complexity: O(*count*).
    public func segments() -> [Range<Int>] {
        withUnsafeFlags { flags in
            var result: [Range<Int>] = []
            var runStart: Int?
            for index in 0..<flags.count {
                if flags[index] {
                    if let begin = runStart {
                        result.append(begin..<index)
                        runStart = nil
                    }
                } else if runStart == nil {
                    runStart = index
                }
            }
            if let begin = runStart {
                result.append(begin..<flags.count)
            }
            return result
        }
    }

    public mutating func removeAll() {
        flags.removeAll()
    }
}
