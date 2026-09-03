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

private func json(run: String = validRun, env: String = validEnv, cases: String = validCase) -> Data {
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
    #expect(result.cases.count == 1)
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
