/// Fixed-capacity buffer of the most recent `capacity` elements, laid out so that a snapshot is
/// always one contiguous run.
///
/// Storage is `2 × capacity` and every element is written twice, at `i` and at `i + capacity`.
/// The duplicate costs memory that a plain ring would not, and buys the property the renderers
/// need: the newest `count` elements are contiguous for any head position, so a frame hands the
/// GPU a single pointer instead of two slices that must be stitched or copied.
///
/// The type is a value type and `snapshot` borrows rather than copies, so a reader that runs
/// while the producer pushes sees a consistent older state rather than a torn one.
///
/// - Invariant: `count <= capacity`, and `head` is always in `0..<capacity`.
/// - SeeAlso: Docs/methods/buffers-and-windows.md — why the storage is mirrored, and what that
///   costs.
public struct RingBuffer<Element: Sendable>: Sendable {
    /// Most elements retained. Older ones are overwritten.
    public let capacity: Int

    private var storage: [Element]
    private var head: Int
    /// Elements currently held, growing to `capacity` and staying there.
    public private(set) var count: Int
    /// Total ever pushed, including those overwritten. Used to detect a consumer that fell
    /// behind far enough to have missed data rather than merely lagged.
    public private(set) var totalPushed: UInt64

    /// Creates an empty buffer.
    ///
    /// - Parameters:
    ///   - capacity: Elements retained. Must be positive.
    ///   - placeholder: Value the backing storage is filled with. It is never observable:
    ///     ``withUnsafeSnapshot(_:)`` and the subscript expose `count` elements and no more. A
    ///     placeholder is required only because the mirrored layout needs random access, which
    ///     rules out growing the storage on demand.
    /// - Precondition: `capacity > 0`.
    public init(capacity: Int, filledWith placeholder: Element) {
        precondition(capacity > 0, "RingBuffer needs a positive capacity")
        self.capacity = capacity
        self.storage = Array(repeating: placeholder, count: capacity * 2)
        self.head = 0
        self.count = 0
        self.totalPushed = 0
    }

    /// Appends one element, overwriting the oldest once full.
    ///
    /// - Complexity: O(1), no allocation after construction.
    public mutating func push(_ element: Element) {
        storage[head] = element
        storage[head + capacity] = element
        head = head + 1 == capacity ? 0 : head + 1
        if count < capacity { count += 1 }
        totalPushed &+= 1
    }

    /// Index into `storage` of the oldest retained element.
    private var start: Int {
        (head - count + capacity) % capacity
    }

    /// The element at `offset` positions after the oldest.
    ///
    /// - Precondition: `offset` is in `0..<count`.
    public subscript(offset: Int) -> Element {
        precondition(offset >= 0 && offset < count, "RingBuffer offset out of range")
        return storage[start + offset]
    }

    /// Borrows the retained elements, oldest first, as one contiguous run.
    ///
    /// - Important: The pointer must not escape the closure; the next push may overwrite it.
    /// - Complexity: O(1). No copy is made.
    public func withUnsafeSnapshot<R>(_ body: (UnsafeBufferPointer<Element>) -> R) -> R {
        let begin = start
        let end = begin + count
        return storage.withUnsafeBufferPointer { buffer in
            body(UnsafeBufferPointer(rebasing: buffer[begin..<end]))
        }
    }

    /// Copies the retained elements, oldest first. For tests and for callers who need ownership.
    ///
    /// - Complexity: O(*count*), allocates.
    public func snapshot() -> [Element] {
        withUnsafeSnapshot(Array.init)
    }

    /// Drops every retained element. Capacity and `totalPushed` are unchanged: the counter
    /// describes the producer, not the contents.
    public mutating func removeAll() {
        head = 0
        count = 0
    }
}
