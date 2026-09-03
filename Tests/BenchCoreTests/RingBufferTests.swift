import Testing
@testable import BenchCore

@Test
func snapshotIsEmptyBeforeAnythingIsPushed() {
    let buffer = RingBuffer(capacity: 4, filledWith: 0.0)
    #expect(buffer.count == 0)
    #expect(buffer.snapshot() == [])
}

@Test
func fillsBeforeItWraps() {
    var buffer = RingBuffer(capacity: 4, filledWith: 0)
    for value in 1...4 { buffer.push(value) }
    #expect(buffer.snapshot() == [1, 2, 3, 4])
    #expect(buffer.count == 4)
}

@Test
func oldestIsOverwrittenOnceFull() {
    var buffer = RingBuffer(capacity: 4, filledWith: 0)
    for value in 1...6 { buffer.push(value) }
    #expect(buffer.snapshot() == [3, 4, 5, 6])
    #expect(buffer.count == 4)
    #expect(buffer.totalPushed == 6)
}

/// The mirrored layout exists for this: whatever the head position, the retained elements are one
/// run. A wrapped buffer that returned two slices would force a copy on the hot path.
@Test
func snapshotStaysContiguousAtEveryHeadPosition() {
    var buffer = RingBuffer(capacity: 5, filledWith: 0)
    for value in 1...5 { buffer.push(value) }
    for extra in 6...20 {
        buffer.push(extra)
        let expected = Array((extra - 4)...extra)
        #expect(buffer.snapshot() == expected)
        buffer.withUnsafeSnapshot { pointer in
            #expect(pointer.count == 5)
            #expect(Array(pointer) == expected)
        }
    }
}

@Test
func subscriptCountsFromTheOldest() {
    var buffer = RingBuffer(capacity: 3, filledWith: 0)
    for value in 1...5 { buffer.push(value) }
    #expect(buffer[0] == 3)
    #expect(buffer[2] == 5)
}

@Test
func capacityOfOneKeepsOnlyTheNewest() {
    var buffer = RingBuffer(capacity: 1, filledWith: 0)
    buffer.push(7)
    buffer.push(9)
    #expect(buffer.snapshot() == [9])
}

@Test
func removeAllEmptiesContentsButNotTheProducerCounter() {
    var buffer = RingBuffer(capacity: 3, filledWith: 0)
    for value in 1...5 { buffer.push(value) }
    buffer.removeAll()
    #expect(buffer.count == 0)
    #expect(buffer.totalPushed == 5)
}

/// Model test: ten thousand operations against a plain array kept as the reference. Catches the
/// off-by-one in the mirrored index arithmetic that cases of size four would not.
///
/// The operation sequence is generated, but not randomly: a failing run must be reproducible from
/// the test name alone. `SystemRandomNumberGenerator` would make a failure here unrepeatable,
/// which is the one thing this project refuses to accept from a measurement or from a test.
@Test
func agreesWithAReferenceArrayOverTenThousandOperations() {
    let capacity = 37
    var buffer = RingBuffer(capacity: capacity, filledWith: 0)
    var reference: [Int] = []
    var state: UInt64 = 0x2545_F491_4F6C_DD1D

    for step in 0..<10_000 {
        // xorshift64*, inlined so that this target keeps its Foundation-only dependency set.
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let draw = Int((state &* 0x2545_F491_4F6C_DD1D) >> 33) % 100

        if draw < 5 {
            buffer.removeAll()
            reference.removeAll()
            continue
        }
        buffer.push(step)
        reference.append(step)
        if reference.count > capacity { reference.removeFirst(reference.count - capacity) }

        #expect(buffer.count == reference.count)
        if step % 97 == 0 {
            #expect(buffer.snapshot() == reference)
        }
    }
    #expect(buffer.snapshot() == reference)
}
