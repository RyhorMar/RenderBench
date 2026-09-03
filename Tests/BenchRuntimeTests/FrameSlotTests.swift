import Testing
@testable import BenchRuntime

private func snapshot(frame: UInt64, epoch: UInt64 = 1) -> FrameSnapshot {
    FrameSnapshot(frameID: frame, epoch: epoch, window: 0...10, pointCount: 800)
}

@Test
func takeReturnsTheNewestAndEmptiesTheSlot() {
    let slot = FrameSlot()
    slot.publish(snapshot(frame: 1))
    #expect(slot.take(epoch: 1)?.frameID == 1)
    #expect(slot.take(epoch: 1) == nil)
}

/// The counter that separates this from the thing people mislabel back-pressure. Dropping frames
/// is a legitimate strategy; dropping them without saying how many is not.
@Test
func overwritingAnUntakenSnapshotIsCountedAsADrop() {
    let slot = FrameSlot()
    slot.publish(snapshot(frame: 1))
    slot.publish(snapshot(frame: 2))
    slot.publish(snapshot(frame: 3))

    #expect(slot.take(epoch: 1)?.frameID == 3)

    let counters = slot.counters
    #expect(counters.produced == 3)
    #expect(counters.dropped == 2)
    #expect(counters.delivered == 1)
}

@Test
func aSnapshotFromASupersededConfigurationIsDiscardedNotDrawn() {
    let slot = FrameSlot()
    slot.publish(snapshot(frame: 7, epoch: 1))

    // The window changed; epoch 1 data would draw one frame of the previous configuration.
    #expect(slot.take(epoch: 2) == nil)
    #expect(slot.counters.staleEpoch == 1)
    #expect(slot.counters.delivered == 0)
}

@Test
func countersStartAtZero() {
    #expect(FrameSlot().counters == SlotCounters())
}
