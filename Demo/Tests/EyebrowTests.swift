import Testing
@testable import RenderBenchDemo

/// The label shouts, the source text does not. Callers pass a readable phrase and the component
/// raises it, so the same phrase cannot arrive uppercase from one screen and lowercase from another.
@Test
func anEyebrowRaisesTheTextItIsGiven() {
    #expect(Eyebrow.rendered("nine methods") == "NINE METHODS")
    #expect(Eyebrow.rendered("cannot know about itself") == "CANNOT KNOW ABOUT ITSELF")
}

/// Already-uppercase text and text with digits pass through unharmed — the transform is a case
/// change, not a rewrite.
@Test
func raisingIsIdempotentAndLeavesDigitsAlone() {
    #expect(Eyebrow.rendered("RENDERBENCH") == "RENDERBENCH")
    #expect(Eyebrow.rendered("01 · nine methods") == "01 · NINE METHODS")
    #expect(Eyebrow.rendered("") == "")
}
