import Foundation

/// How a reading is written, and there is one answer for the whole app.
///
/// An absent value is the literal word `nil`, not a dash. A dash does not explain itself: a reader
/// cannot tell "this backend cannot report it" from "the row is a separator" from "somebody left a
/// placeholder". `nil` is the same word the code uses for the same thing, and it is the same
/// argument by which this project writes an absent counter as absent rather than as zero.
///
/// Zero is not absence and is never rewritten: a backend that honestly counted zero dropped frames
/// says `0`. The overlay and the tiles on the screens behind it share this word rather than each
/// spelling absence their own way.
enum Reading {
    static let absent = "nil"

    /// A reading a caller has already formatted, which may be absent. The rule lives here rather
    /// than in the view that shows it: a view is main-actor work, and a rule this important should be
    /// checkable without one.
    static func text(_ reading: String?) -> String {
        guard let reading else { return absent }
        return reading
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return absent }
        return "\(value)"
    }

    static func milliseconds(_ nanoseconds: UInt64?) -> String {
        guard let nanoseconds else { return absent }
        return String(format: "%.2f ms", Double(nanoseconds) / 1_000_000)
    }
}
