import Foundation

extension Duration {
    // Public because every backend times its own encoding and reports nanoseconds; the stdlib's
    // static `Duration.nanoseconds(_:)` shadows this name at the call site otherwise.
    /// This duration in whole nanoseconds.
    public var nanoseconds: UInt64 {
        let parts = components
        let seconds = UInt64(max(0, parts.seconds))
        let fraction = UInt64(max(0, parts.attoseconds) / 1_000_000_000)
        return seconds &* 1_000_000_000 &+ fraction
    }
}
