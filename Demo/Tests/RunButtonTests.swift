import Testing
@testable import RenderBenchDemo

private let held = Precondition(title: "Warm-up discarded", detail: "first repeat is never recorded",
                                state: .held)
private let simulator = Precondition(title: "Physical device", detail: "running in a simulator",
                                     state: .violated)
private let debug = Precondition(title: "Release configuration", detail: "current build is Debug",
                                 state: .violated)
private let thermal = Precondition(title: "Thermal state nominal", detail: "checked at start and at end",
                                   state: .notChecked)

/// The defect this component exists to prevent: a control that refuses and does not say why.
@Test
func aBlockedButtonNamesWhatFailed() {
    let reason = RunButton.reason(for: [simulator, debug, thermal, held])
    #expect(reason != nil)
    #expect(reason?.contains("physical device") == true)
    #expect(reason?.contains("release configuration") == true)
}

/// It names them rather than counting them: a count tells a reader how much bad news there is and
/// nothing about what to do next.
@Test
func theReasonIsNotACount() {
    let reason = RunButton.reason(for: [simulator, debug])
    #expect(reason?.contains("2") == false)
    #expect(reason?.contains("two") == false)
}

/// An unchecked condition is a question, not a reason. Listing it would report a blockage that does
/// not exist — the same collapse of three states into two the row itself refuses.
@Test
func anUncheckedConditionIsNotAReason() {
    #expect(RunButton.reason(for: [held, thermal]) == nil)
    #expect(RunButton.blockers(in: [held, thermal]).isEmpty)
    #expect(RunButton.reason(for: [simulator, thermal])?.contains("thermal") == false)
}

/// Nothing blocking means no sentence at all, not an empty one: an empty line under a live button is
/// a gap a reader reads as a missing message.
@Test
func nothingBlockingMeansNoSentence() {
    #expect(RunButton.reason(for: [held]) == nil)
    #expect(RunButton.reason(for: []) == nil)
}
