import Testing
@testable import RenderBenchDemo

/// The variant that carries the project's whole argument, and the one a well-meaning edit ruins: a
/// pointer, a dash, a "(see 05)" appended to the words. The text is written out here so that any
/// addition fails, not just a rewrite.
@Test
func theNotMeasuredChipSaysExactlyThatAndNothingElse() {
    #expect(Provenance.notMeasured.text == "not measured")
}

@Test
func aMeasuredChipNamesDeviceOSBuildAndCommit() throws {
    let run = try #require(Provenance.Run(device: "iPhone 16 Pro", os: "iOS 26.5", build: "Release",
                                         sha: "8f2c1ab"))
    #expect(Provenance.measured(run).text == "iPhone 16 Pro · iOS 26.5 · Release · 8f2c1ab")
}

/// The refusals are the point of the failable initialiser: a chip that claims a measurement is the
/// one place where a fabricated value looks exactly like a real one.
@Test
func aRunWithoutRealValuesCannotBeBuilt() {
    #expect(Provenance.Run(device: "iPhone 16 Pro", os: "iOS 26.5", build: "Release",
                           sha: "unknown") == nil)
    #expect(Provenance.Run(device: "", os: "iOS 26.5", build: "Release", sha: "8f2c1ab") == nil)
    #expect(Provenance.Run(device: "iPhone 16 Pro", os: "  ", build: "Release", sha: "8f2c1ab") == nil)
    #expect(Provenance.Run(device: "iPhone 16 Pro", os: "iOS 26.5", build: "", sha: "8f2c1ab") == nil)
}

/// `unknown` is not an arbitrary sentinel: it is what the committed build stamp holds. Which of the
/// two branches below runs depends on the build, and both are real states — a raw checkout carries
/// the placeholder, and every lane stamps the file with a real revision before compiling. Asserting
/// only the first is what made this test pass locally and fail in the gate.
@Test
func aMeasuredChipFollowsWhetherThisBuildWasStamped() {
    let run = Provenance.Run(device: "iPhone 16 Pro", os: "iOS 26.5", build: "Release",
                             sha: BuildInfo.gitSha)
    if BuildInfo.gitSha == "unknown" {
        #expect(run == nil, "an unstamped build must not be able to claim a measurement")
    } else {
        #expect(run != nil, "a stamped build must be able to, or nothing could ever be measured")
    }
}

@Test
func theOtherThreeVariantsSayWhatTheDesignSaysTheySay() {
    #expect(Provenance.observation(environment: "simulator").text
        == "observation, not a measurement · simulator")
    #expect(Provenance.hypothesis.text
        == "debug build on host · hypothesis until confirmed in release")
    #expect(Provenance.source("swift test").text == "swift test")
}

/// Five variants, and the list is the vocabulary: a sixth would mean a number on a screen whose
/// origin the reader has to guess.
@Test
func thereAreFiveVariantsAndEachSaysSomething() throws {
    let run = try #require(Provenance.Run(device: "d", os: "o", build: "b", sha: "s"))
    let all: [Provenance] = [
        .measured(run), .notMeasured, .observation(environment: "simulator"), .hypothesis,
        .source("git log"),
    ]
    #expect(all.count == 5)
    for provenance in all {
        #expect(provenance.text.isEmpty == false)
    }
}
