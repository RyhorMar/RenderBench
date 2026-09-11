import BenchCore
import BenchDownsampling
import Foundation
import Testing
@testable import BenchRuntime

private let validRun = """
{
  "id": "abc", "startedAt": "2026-09-03T12:00:00Z", "gitSha": "deadbeef",
  "gitDirty": false, "configuration": "release", "swiftVersion": "6.3.3"
}
"""

private let validEnv = """
{
  "deviceModel": "iPhone17,1", "osVersion": "26.0", "isSimulator": false,
  "maximumFramesPerSecond": 120, "thermalStateAtStart": "nominal",
  "thermalStateAtEnd": "fair", "lowPowerModeEnabled": false
}
"""

private let validCase = """
{
  "chartKind": "strip-chart", "backend": "canvas", "seriesCount": 8,
  "pointsPerSeries": 10000, "refreshHz": 120, "policy": "minMax",
  "warmupFrames": 120, "measuredFrames": 1200, "repeatIndex": 1,
  "cpu": {"sampleCount": 1200, "p50Ns": 1, "p95Ns": 2, "p99Ns": 3, "maxNs": 4},
  "pointsSubmitted": 2512, "pointsDrawn": 2512, "drawCalls": 8,
  "equivalence": "notChecked"
}
"""

/// The same case in the three repeats the procedure requires — the shape a stored file has to
/// have. A single pass is a valid document and not a measurement, which is what
/// `tooFewRepeats` exists to say, so the fixture that stands in for a real file carries three.
private let threeRepeats = (1...3)
    .map { validCase.replacingOccurrences(of: "\"repeatIndex\": 1", with: "\"repeatIndex\": \($0)") }
    .joined(separator: ",")

private func json(run: String = validRun, env: String = validEnv, cases: String = threeRepeats) -> Data {
    Data("""
    {"run": \(run), "env": \(env), "cases": [\(cases)]}
    """.utf8)
}

private func decode(_ data: Data) throws -> BenchmarkResult {
    try BenchmarkResult.decoder().decode(BenchmarkResult.self, from: data)
}

@Test
func aCompleteResultDecodes() throws {
    let result = try decode(json())
    #expect(result.run.gitSha == "deadbeef")
    #expect(result.env.deviceModel == "iPhone17,1")
    #expect(result.cases.count == 3)
    #expect(throws: Never.self) { try result.validate(isStoredResult: true) }
}

/// The acceptance criterion for this card, stated three times: an absent required field is a
/// validation error, not a nil.
@Test
func anAbsentGitShaIsAnError() {
    let withoutSha = validRun.replacingOccurrences(of: "\"gitSha\": \"deadbeef\",", with: "")
    #expect(throws: (any Error).self) { try decode(json(run: withoutSha)) }
}

@Test
func anAbsentDeviceModelIsAnError() {
    let withoutModel = validEnv.replacingOccurrences(of: "\"deviceModel\": \"iPhone17,1\",", with: "")
    #expect(throws: (any Error).self) { try decode(json(env: withoutModel)) }
}

@Test
func anAbsentThermalStateIsAnError() {
    for field in ["\"thermalStateAtStart\": \"nominal\",", "\"thermalStateAtEnd\": \"fair\","] {
        let without = validEnv.replacingOccurrences(of: field, with: "")
        #expect(throws: (any Error).self) { try decode(json(env: without)) }
    }
}

/// An empty string is the same defect as an absent key, and a reader cannot tell them apart in a
/// stored file. Decoding treats them the same.
@Test
func anEmptyRequiredFieldIsTheSameErrorAsAnAbsentOne() {
    let blankSha = validRun.replacingOccurrences(of: "\"deadbeef\"", with: "\"   \"")
    let blankModel = validEnv.replacingOccurrences(of: "\"iPhone17,1\"", with: "\"\"")
    #expect(throws: (any Error).self) { try decode(json(run: blankSha)) }
    #expect(throws: (any Error).self) { try decode(json(env: blankModel)) }
}

/// A number that cannot be traced to a revision is not evidence, so the placeholder an unstamped
/// build writes is rejected as firmly as a missing field.
@Test
func anUnstampedBuildIsRejected() {
    let unstamped = validRun.replacingOccurrences(of: "\"deadbeef\"", with: "\"unknown\"")
    #expect(throws: (any Error).self) { try decode(json(run: unstamped)) }
}

@Test
func aSimulatorRunIsRefusedAmongStoredResultsButDecodes() throws {
    let simulated = validEnv.replacingOccurrences(of: "\"isSimulator\": false", with: "\"isSimulator\": true")
    let result = try decode(json(env: simulated))
    #expect(throws: BenchmarkValidationError.measuredOnSimulator) {
        try result.validate(isStoredResult: true)
    }
}

/// `notChecked` must never be readable as `passed`, and a failed check makes the whole file
/// unpublishable rather than just that case.
@Test
func aFailedEquivalenceCheckInvalidatesTheFile() throws {
    let failed = validCase.replacingOccurrences(of: "\"notChecked\"", with: "\"failed\"")
    let result = try decode(json(cases: failed))
    #expect(throws: BenchmarkValidationError.equivalenceFailed(backend: "canvas")) {
        try result.validate(isStoredResult: true)
    }
}

@Test
func aRunWithNoCasesMeasuredNothing() throws {
    let empty = Data("{\"run\": \(validRun), \"env\": \(validEnv), \"cases\": []}".utf8)
    let result = try decode(empty)
    #expect(throws: BenchmarkValidationError.noCases) { try result.validate(isStoredResult: true) }
}

@Test
func theExampleIsRefusedAmongStoredResults() throws {
    let example = validRun.replacingOccurrences(of: "\"abc\"", with: "\"example\"")
    let result = try decode(json(run: example))
    #expect(result.run.isExample)
    #expect(throws: BenchmarkValidationError.exampleInResultsDirectory(runID: "example")) {
        try result.validate(isStoredResult: true)
    }
    #expect(throws: Never.self) { try result.validate(isStoredResult: false) }
}

@Test
func encodingIsCanonicalAndRoundTrips() throws {
    let original = try decode(json())
    let data = try BenchmarkResult.encoder().encode(original)
    #expect(try decode(data) == original)

    let text = String(decoding: data, as: UTF8.self)
    // Sorted keys, so two runs of the same shape produce diffable files.
    #expect(text.range(of: "\"cases\"")!.lowerBound < text.range(of: "\"env\"")!.lowerBound)
    #expect(text.contains("2026-09-03T12:00:00Z"))
}

/// The platform states map one-to-one. The `@unknown default` arm cannot be reached from a test —
/// there is no way to construct a state this SDK does not know — so the name says what is actually
/// checked rather than promising coverage of that arm.
@Test
func platformThermalStatesMapOneToOne() {
    #expect(ThermalState(ProcessInfo.ThermalState.nominal) == .nominal)
    #expect(ThermalState(ProcessInfo.ThermalState.fair) == .fair)
    #expect(ThermalState(ProcessInfo.ThermalState.serious) == .serious)
    #expect(ThermalState(ProcessInfo.ThermalState.critical) == .critical)
}

/// Ordering, which is what makes "at least serious" expressible. Nominal and fair are usable
/// conditions; serious and critical mean the machine, not the method, was being measured.
@Test
func onlySeriousAndCriticalCountAsThrottled() {
    #expect(ThermalState.nominal.isThrottled == false)
    #expect(ThermalState.fair.isThrottled == false)
    #expect(ThermalState.serious.isThrottled)
    #expect(ThermalState.critical.isThrottled)
}

/// The defect this review round found: the methodology listed hard preconditions and the guard
/// stored files that violated every one of them.
@Test
func everyDocumentedPreconditionIsEnforcedOnAStoredResult() throws {
    let base = try decode(json())

    var throttled = base
    throttled.env.thermalStateAtEnd = .serious
    #expect(throws: BenchmarkValidationError.thermallyThrottled(.serious)) {
        try throttled.validate(isStoredResult: true)
    }

    var throttledAtStart = base
    throttledAtStart.env.thermalStateAtStart = .critical
    #expect(throws: BenchmarkValidationError.thermallyThrottled(.critical)) {
        try throttledAtStart.validate(isStoredResult: true)
    }

    var debugBuild = base
    debugBuild.run.configuration = .debug
    #expect(throws: BenchmarkValidationError.notReleaseConfiguration(.debug)) {
        try debugBuild.validate(isStoredResult: true)
    }

    var lowPower = base
    lowPower.env.lowPowerModeEnabled = true
    #expect(throws: BenchmarkValidationError.lowPowerModeEnabled) {
        try lowPower.validate(isStoredResult: true)
    }

    var flat = base
    flat.env.batteryLevel = 0.05
    #expect(throws: BenchmarkValidationError.batteryTooLow(0.05)) {
        try flat.validate(isStoredResult: true)
    }

    // An unknown battery level is not a violation: some platforms do not report one, and refusing
    // a run for a fact nobody could observe would make the check unusable.
    var noBattery = base
    noBattery.env.batteryLevel = nil
    #expect(throws: Never.self) { try noBattery.validate(isStoredResult: true) }
}

/// The example is a shape illustration, so it is checked for shape only. Applying the run
/// conditions to it would force it to carry a plausible thermal state and battery level, which is
/// exactly the kind of invented detail that makes an example look like a measurement.
@Test
func theExampleIsNotHeldToTheRunConditions() throws {
    var example = try decode(json())
    example.run.id = "example"
    example.run.configuration = .debug
    example.env.lowPowerModeEnabled = true
    #expect(throws: Never.self) { try example.validate(isStoredResult: false) }
}

@Test
func theHardwareIdentifierSaysWhenItIsPretending() {
    let identifier = RunEnvironment.hardwareIdentifier()
    #expect(identifier.isEmpty == false)
    if RunEnvironment.isRunningOnSimulator {
        #expect(identifier.contains("simulator"))
    }
}

// MARK: Counters a backend cannot know

/// Six of the nine backends know neither counter. Absence has to survive the round trip as
/// absence: a decoder that turned it into a zero would publish "drew nothing" as a measurement.
@Test
func anAbsentCounterDecodesAsNilRatherThanZero() throws {
    let withoutCounters = threeRepeats
        .replacingOccurrences(of: "\"pointsDrawn\": 2512, ", with: "")
        .replacingOccurrences(of: "\"drawCalls\": 8,", with: "")
    let result = try decode(json(cases: withoutCounters))
    #expect(result.cases[0].pointsDrawn == nil)
    #expect(result.cases[0].drawCalls == nil)
    #expect(result.cases[0].pointsDrawn != 0)
    #expect(throws: Never.self) { try result.validate(isStoredResult: true) }
}

/// The other half of the round trip, and the reason the schema says `additionalProperties: false`
/// with no null type: an unknown counter leaves the key out entirely rather than writing `null`.
@Test
func anUnknownCounterIsEncodedAsAnAbsentKeyNotNull() throws {
    let source = try decode(
        json(
            cases: validCase
                .replacingOccurrences(of: "\"pointsDrawn\": 2512, ", with: "")
                .replacingOccurrences(of: "\"drawCalls\": 8,", with: "")
        )
    )
    let encoded = try BenchmarkResult.encoder().encode(source)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(!text.contains("pointsDrawn"))
    #expect(!text.contains("drawCalls"))
    #expect(!text.contains("null"))
}

/// A drawn frame issued at least one draw call. A zero in this field is a backend saying "I do not
/// know" in the one vocabulary the format reserves for a measurement.
@Test
func aZeroDrawCountIsRejected() throws {
    let zeroed = validCase.replacingOccurrences(of: "\"drawCalls\": 8", with: "\"drawCalls\": 0")
    let result = try decode(json(cases: zeroed))
    #expect(throws: BenchmarkValidationError.counterReportedAsZero(field: "drawCalls", backend: "canvas")) {
        try result.validate(isStoredResult: true)
    }
}

/// Points submitted but none drawn is either a backend that dropped every point or one that could
/// not count; neither is a row worth publishing.
@Test
func drawingNoneOfTheSubmittedPointsIsRejected() throws {
    let zeroed = validCase.replacingOccurrences(of: "\"pointsDrawn\": 2512", with: "\"pointsDrawn\": 0")
    let result = try decode(json(cases: zeroed))
    #expect(throws: BenchmarkValidationError.counterReportedAsZero(field: "pointsDrawn", backend: "canvas")) {
        try result.validate(isStoredResult: true)
    }
}

/// The gap the first version of this rule left: it spared a case that had submitted nothing, so a
/// zero could still be published as long as `pointsSubmitted` was zero too. The schema never allowed
/// it — `pointsDrawn` has `minimum: 1` regardless — and the two gates disagreeing is worse than
/// either being strict.
@Test
func aZeroIsRejectedEvenWhenNothingWasSubmitted() throws {
    let emptied = validCase
        .replacingOccurrences(of: "\"pointsSubmitted\": 2512", with: "\"pointsSubmitted\": 0")
        .replacingOccurrences(of: "\"pointsDrawn\": 2512", with: "\"pointsDrawn\": 0")
    let result = try decode(json(cases: emptied))
    #expect(throws: BenchmarkValidationError.counterReportedAsZero(field: "pointsDrawn", backend: "canvas")) {
        try result.validate(isStoredResult: true)
    }
}

/// The zero rule applies to the example too, not only to stored results: the example is the shape
/// a reader copies.
@Test
func aZeroCounterIsRejectedInAnUnstoredResultAsWell() throws {
    let zeroed = validCase.replacingOccurrences(of: "\"drawCalls\": 8", with: "\"drawCalls\": 0")
    let result = try decode(json(cases: zeroed))
    #expect(throws: (any Error).self) { try result.validate(isStoredResult: false) }
}

// MARK: A correctly shaped file that is not a measurement

/// The file the application's export button writes, on a device, in Release, with nothing wrong
/// with it — and it is still refused.
///
/// Every field in it is honest: the export performs no warm-up and it says `0`, and it is one
/// pass and it says `1`. Honest and "not a measurement" are compatible, which is why the
/// directory that holds evidence checks these two rather than trusting the shape of the document.
private let exportShapedCase = validCase
    .replacingOccurrences(of: "\"warmupFrames\": 120", with: "\"warmupFrames\": 0")

@Test
func aFileWithNoWarmUpIsRefusedFromTheResultsDirectory() throws {
    let threeUnwarmed = (1...3)
        .map { exportShapedCase.replacingOccurrences(of: "\"repeatIndex\": 1", with: "\"repeatIndex\": \($0)") }
        .joined(separator: ",")
    let result = try decode(json(cases: threeUnwarmed))
    #expect(throws: BenchmarkValidationError.notWarmedUp(backend: "canvas")) {
        try result.validate(isStoredResult: true)
    }
}

@Test
func aSinglePassIsRefusedFromTheResultsDirectory() throws {
    let result = try decode(json(cases: validCase))
    #expect(throws: BenchmarkValidationError.tooFewRepeats(found: 1, required: 3)) {
        try result.validate(isStoredResult: true)
    }
}

/// The whole of what the export button produces, refused at the first of the two.
@Test
func theExportButtonsOwnFileIsRefused() throws {
    let result = try decode(json(cases: exportShapedCase))
    #expect(throws: (any Error).self) { try result.validate(isStoredResult: true) }
    // And still a valid document: the format is not what is wrong with it.
    #expect(throws: Never.self) { try result.validate(isStoredResult: false) }
}

/// Neither rule reaches outside the results directory. The example has one repeat by design, and
/// a file being read rather than filed is not being offered as evidence.
@Test
func neitherRuleAppliesOutsideTheResultsDirectory() throws {
    let result = try decode(json(cases: exportShapedCase))
    #expect(throws: Never.self) { try result.validate(isStoredResult: false) }
}

// MARK: The rate the run actually got

/// The rate asked for and the rate got are different quantities, and the file carries both.
///
/// `refreshHz` is what the display can do. It said 120 on a run where a backend sustained 73, and
/// it was not lying — it answers a different question. Nothing in this format answered the other
/// one until now, and no system property answers it either: it has to be counted.
@Test
func aCaseCarriesTheRateItActuallyAchieved() throws {
    let withAchieved = validCase.replacingOccurrences(
        of: "\"refreshHz\": 120,",
        with: "\"refreshHz\": 120, \"achievedHz\": 73.4,"
    )
    let result = try decode(json(cases: withAchieved))
    #expect(result.cases[0].achievedHz == 73.4)
    #expect(result.cases[0].refreshHz == 120, "the display's rate is untouched by the one achieved")
}

/// A run taken before the rate was counted says nothing rather than zero.
///
/// Absent is the honest reading for a file this project wrote before it could count: zero would
/// claim the app drew no frames, which is the opposite of what happened.
@Test
func aCaseWithoutAnAchievedRateDecodesAsAbsentNotZero() throws {
    let result = try decode(json())
    #expect(result.cases[0].achievedHz == nil)
    #expect(result.cases[0].achievedHz != 0)
}

/// The schema declares it, so an external validator sees it too.
@Test
func theSchemaDeclaresTheAchievedRate() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "Benchmarks/schema.json"))
    let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let cases = try #require((schema["properties"] as? [String: Any])?["cases"] as? [String: Any])
    let item = try #require(cases["items"] as? [String: Any])
    let properties = try #require(item["properties"] as? [String: Any])
    #expect(properties["achievedHz"] != nil, "the model carries a field the schema does not declare")
}
