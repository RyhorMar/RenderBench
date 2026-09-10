import Foundation

/// Frames per second over a window, counted rather than inferred from the last interval.
///
/// The rate a display link is asked for is knowable before the first frame; the rate it delivers is
/// knowable only by counting, because no system property reports it. Low Power Mode, thermal state
/// and the accessibility setting that limits the frame rate all lower it, and the last of those
/// cannot be read from inside the process at all.
///
/// A value rather than a class, fed timestamps rather than a link, so that a caller driving its own
/// `MTKView` or `CAMetalDisplayLink` can use it exactly as this package's own ticker does.
public struct FrameRateMeter: Sendable, Equatable {
    /// Seconds of history the rate is computed over.
    public let window: Double
    private var marks: [Double] = []

    public init(window: Double = 1.0) {
        self.window = window
    }

    /// Records one frame at the moment it was drawn.
    public mutating func record(timestamp: Double) {
        marks.append(timestamp)
        let cutoff = timestamp - window
        if let firstKept = marks.firstIndex(where: { $0 >= cutoff }), firstKept > 0 {
            marks.removeFirst(firstKept)
        }
    }

    /// Frames per second across the window, or `nil` while it holds fewer than two marks.
    ///
    /// Intervals, not marks: a run of marks bounds one fewer interval than it has marks, and
    /// dividing by the count would report a rate a frame too high on a short window.
    ///
    /// One condition, not two. A separate count check would be redundant with this one — a single
    /// mark cannot satisfy `first < last` — and a redundant guard is a line no change to it can be
    /// observed through.
    public var rate: Double? {
        guard let first = marks.first, let last = marks.last, first < last else { return nil }
        return Double(marks.count - 1) / (last - first)
    }
}
