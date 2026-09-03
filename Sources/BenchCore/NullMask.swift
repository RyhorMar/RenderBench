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
        withUnsafeFlags(runsOfMeasurements(in:))
    }

    public mutating func removeAll() {
        flags.removeAll()
    }
}

/// Ranges of consecutive positions that carry measurements, given a buffer of gap flags.
///
/// Free function rather than a method so that the downsampler — which receives flags borrowed from
/// a provider and never sees a `NullMask` — computes segments with the same code that `NullMask`
/// does. Two implementations of "where does the line break" is one more than the number of answers
/// that can be right.
///
/// - Complexity: O(*n*).
public func runsOfMeasurements(in gaps: UnsafeBufferPointer<Bool>) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start: Int?
    for index in 0..<gaps.count {
        if gaps[index] {
            if let begin = start {
                runs.append(begin..<index)
                start = nil
            }
        } else if start == nil {
            start = index
        }
    }
    if let begin = start {
        runs.append(begin..<gaps.count)
    }
    return runs
}
