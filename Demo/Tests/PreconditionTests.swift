import Testing
@testable import RenderBenchDemo

/// The distinction the whole row exists for. Folding "not checked" into "violated" blocks a run that
/// could have gone ahead; folding it into "held" reports a condition as satisfied because nobody
/// looked. Both directions are checked, because a fix for one is the usual way to cause the other.
@Test
func notCheckedIsNeitherHeldNorViolated() {
    #expect(PreconditionState.notChecked != .violated)
    #expect(PreconditionState.notChecked != .held)
    #expect(PreconditionState.notChecked.blocksRun == false)
    #expect(PreconditionState.violated.blocksRun)
    #expect(PreconditionState.held.blocksRun == false)
}

/// Each state carries its own mark, so the three are told apart without colour — which the dark
/// theme needs, where the violation colour clears the floor for graphics and not for text.
@Test
func everyStateHasItsOwnMark() {
    let marks = PreconditionState.allCases.map(\.mark)
    #expect(Set(marks).count == PreconditionState.allCases.count)
    #expect(marks.allSatisfy { $0.isEmpty == false })
    #expect(PreconditionState.violated.mark != PreconditionState.notChecked.mark)
}

/// Three states, and a fourth would be a state the design has no mark for.
@Test
func thereAreExactlyThreeStates() {
    #expect(PreconditionState.allCases.count == 3)
}
