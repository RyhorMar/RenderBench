import BenchCore
import BenchDownsampling
import BenchRuntime
import Foundation

// The bench-guard. A results file that reaches the repository has already passed this, so a reader
// does not have to wonder whether the run behind a number was valid.
//
// Checks:
//   1. Benchmarks/schema.json parses, and still requires the fields whose absence must be an
//      error — gitSha, deviceModel and thermal state at both ends of the run.
//   2. Benchmarks/example.json decodes and is marked as an example.
//   3. every file under Benchmarks/results/ decodes, is not an example, was not measured on a
//      simulator, and contains no case that failed the equivalence check.
//
// Usage: swift run CheckBenchmarkResults [package-root] [--write-example]

let arguments = CommandLine.arguments
let root = URL(
    fileURLWithPath: arguments.count > 1 && !arguments[1].hasPrefix("--")
        ? arguments[1]
        : FileManager.default.currentDirectoryPath
)
let writeExample = arguments.contains("--write-example")

let benchmarks = root.appendingPathComponent("Benchmarks")
let schemaURL = benchmarks.appendingPathComponent("schema.json")
let exampleURL = benchmarks.appendingPathComponent("example.json")
let resultsURL = benchmarks.appendingPathComponent("results")

var problems: [String] = []

// MARK: The documented example

/// The shape illustration. Its numbers are invented and its `run.id` says so, which is what keeps
/// it out of `results/` and out of any table of measurements.
func exampleResult() -> BenchmarkResult {
    func percentiles(_ p50: UInt64, _ p95: UInt64, _ p99: UInt64, _ max: UInt64) -> FrameStatistics {
        FrameStatistics(sampleCount: 1_200, p50Ns: p50, p95Ns: p95, p99Ns: p99, maxNs: max)
    }
    return BenchmarkResult(
        run: RunMetadata(
            id: "example",
            startedAt: Date(timeIntervalSince1970: 1_756_900_000),
            gitSha: "0000000000000000000000000000000000000000",
            gitDirty: false,
            configuration: .release,
            swiftVersion: "6.3.3",
            xcodeVersion: "26.6"
        ),
        env: RunEnvironment(
            deviceModel: "iPhone00,0",
            osVersion: "26.0",
            isSimulator: false,
            maximumFramesPerSecond: 120,
            thermalStateAtStart: .nominal,
            thermalStateAtEnd: .fair,
            lowPowerModeEnabled: false,
            batteryLevel: 0.87
        ),
        cases: [
            BenchmarkCase(
                chartKind: .stripChart,
                backend: "canvas",
                seriesCount: 8,
                pointsPerSeries: 10_000,
                refreshHz: 120,
                policy: .minMax,
                warmupFrames: 120,
                measuredFrames: 1_200,
                repeatIndex: 1,
                cpu: percentiles(1_400_000, 3_100_000, 3_400_000, 9_800_000),
                gpu: nil,
                missedDeadlineRatio: 0.0,
                pointsSubmitted: 2_512,
                pointsDrawn: 2_512,
                drawCalls: 8,
                equivalence: .notChecked
            ),
            // A second backend, and deliberately one that reports neither counter: the example is
            // what a reader copies, so it has to show both shapes — a row that knows, and a row
            // that says so by leaving the field out rather than by writing a zero.
            BenchmarkCase(
                chartKind: .stripChart,
                backend: "core-animation",
                seriesCount: 8,
                pointsPerSeries: 100_000,
                refreshHz: 120,
                policy: .lttb,
                warmupFrames: 120,
                measuredFrames: 1_200,
                repeatIndex: 1,
                cpu: percentiles(6_900_000, 15_800_000, 16_400_000, 41_000_000),
                gpu: nil,
                missedDeadlineRatio: 0.31,
                pointsSubmitted: 2_512,
                pointsDrawn: nil,
                drawCalls: nil,
                equivalence: .notChecked
            ),
        ]
    )
}

if writeExample {
    do {
        let data = try BenchmarkResult.encoder().encode(exampleResult())
        try data.write(to: exampleURL)
        print("wrote \(exampleURL.lastPathComponent) from the model")
    } catch {
        FileHandle.standardError.write(Data("cannot write example: \(error)\n".utf8))
        exit(2)
    }
}

/// An instance with **every** optional populated, used only to compare the schema against the
/// model. Deliberately not the example: the example illustrates a plausible run, and a plausible
/// run leaves optionals out.
func everyFieldPopulated() -> BenchmarkResult {
    let stats = FrameStatistics(sampleCount: 1, p50Ns: 1, p95Ns: 1, p99Ns: 1, maxNs: 1)
    return BenchmarkResult(
        run: RunMetadata(
            id: "example",
            startedAt: Date(timeIntervalSince1970: 0),
            gitSha: String(repeating: "0", count: 40),
            gitDirty: false,
            seed: 1,
            configuration: .release,
            swiftVersion: "0",
            xcodeVersion: "0"
        ),
        env: RunEnvironment(
            deviceModel: "iPhone00,0",
            osVersion: "0",
            isSimulator: false,
            maximumFramesPerSecond: 120,
            thermalStateAtStart: .nominal,
            thermalStateAtEnd: .nominal,
            lowPowerModeEnabled: false,
            batteryLevel: 1
        ),
        cases: [
            BenchmarkCase(
                chartKind: .stripChart,
                backend: "example",
                seriesCount: 1,
                pointsPerSeries: 2,
                refreshHz: 120,
                achievedHz: 120,
                policy: .minMax,
                warmupFrames: 1,
                measuredFrames: 1,
                repeatIndex: 1,
                cpu: stats,
                raster: stats,
                gpu: stats,
                missedDeadlineRatio: 0,
                pointsSubmitted: 2,
                pointsDrawn: 2,
                drawCalls: 1,
                equivalence: .passed
            )
        ]
    )
}

// MARK: 1. The schema still requires what must be required

do {
    let data = try Data(contentsOf: schemaURL)
    guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BenchmarkValidationError.missingField("schema root object")
    }
    let properties = schema["properties"] as? [String: Any] ?? [:]

    func required(of block: String) -> Set<String> {
        let node = properties[block] as? [String: Any] ?? [:]
        return Set(node["required"] as? [String] ?? [])
    }

    // Named individually rather than compared wholesale: these are the fields the acceptance
    // criterion is about, and a schema that stops requiring one of them is the defect worth
    // catching, not a schema that gains a field.
    let mustRequire: [(String, String)] = [
        ("run", "gitSha"),
        ("env", "deviceModel"),
        ("env", "thermalStateAtStart"),
        ("env", "thermalStateAtEnd"),
    ]
    for (block, field) in mustRequire where !required(of: block).contains(field) {
        problems.append("Benchmarks/schema.json: \(block).\(field) is no longer required")
    }

    // The inverse, and it guards a rule the `required` list cannot express on its own: six of the
    // nine backends know neither counter. Requiring either one again forces every row to carry a
    // number, and the only number available to a backend that cannot count is a zero — which is
    // exactly the value the whole result format exists to keep out.
    func caseRequired() -> Set<String> {
        let cases = properties["cases"] as? [String: Any] ?? [:]
        let items = cases["items"] as? [String: Any] ?? [:]
        return Set(items["required"] as? [String] ?? [])
    }
    for field in ["pointsDrawn", "drawCalls"] where caseRequired().contains(field) {
        problems.append(
            "Benchmarks/schema.json: cases.\(field) is required again; a backend that cannot count it would have to write a zero"
        )
    }
} catch {
    problems.append("Benchmarks/schema.json: \(error)")
}

// MARK: 1b. The schema and the model agree field by field

// `additionalProperties: false` means a field the model encodes and the schema does not declare
// makes every file this project writes invalid for any external validator — including ours, once
// one is wired in. The inverse is quieter and just as wrong: a field the schema declares and no
// encoder emits documents a column that never arrives. Neither is visible from reading one file,
// because the fields at stake are the optional ones and a given run may carry none of them.
//
// Compared against an instance with every optional populated, not against a stored result: a
// result is allowed to omit optionals, so it can never show that the schema declares too few.
do {
    let data = try Data(contentsOf: schemaURL)
    guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BenchmarkValidationError.missingField("schema root object")
    }
    let defs = schema["$defs"] as? [String: Any] ?? [:]

    /// Follows `$ref` into `$defs`. Only local refs exist here; a remote one is a defect worth
    /// naming rather than silently skipping.
    func resolve(_ node: [String: Any]) -> [String: Any] {
        guard let ref = node["$ref"] as? String else { return node }
        let name = ref.replacingOccurrences(of: "#/$defs/", with: "")
        guard ref.hasPrefix("#/$defs/"), let target = defs[name] as? [String: Any] else {
            problems.append("Benchmarks/schema.json: cannot resolve \(ref)")
            return [:]
        }
        return target
    }

    func compare(_ encoded: Any, against node: [String: Any], at path: String) {
        let node = resolve(node)
        if let object = encoded as? [String: Any] {
            let declared = node["properties"] as? [String: Any] ?? [:]
            for key in object.keys.sorted() where declared[key] == nil {
                problems.append(
                    "Benchmarks/schema.json: \(path).\(key) is encoded by the model and not declared; additionalProperties is false, so our own files would be rejected"
                )
            }
            for key in declared.keys.sorted() where object[key] == nil {
                problems.append(
                    "Benchmarks/schema.json: \(path).\(key) is declared and no encoder emits it"
                )
            }
            for key in object.keys.sorted() {
                guard let child = declared[key] as? [String: Any] else { continue }
                compare(object[key]!, against: child, at: "\(path).\(key)")
            }
        } else if let array = encoded as? [Any], let first = array.first {
            compare(first, against: node["items"] as? [String: Any] ?? [:], at: "\(path)[]")
        }
    }

    let encoded = try JSONSerialization.jsonObject(
        with: try BenchmarkResult.encoder().encode(everyFieldPopulated())
    )
    compare(encoded, against: schema, at: "root")
} catch {
    problems.append("Benchmarks/schema.json: field-by-field comparison failed: \(error)")
}

// MARK: 2. The example

if !FileManager.default.fileExists(atPath: exampleURL.path) {
    problems.append("Benchmarks/example.json: missing — regenerate with --write-example")
} else {
    do {
        let data = try Data(contentsOf: exampleURL)
        let decoded = try BenchmarkResult.decoder().decode(BenchmarkResult.self, from: data)
        try decoded.validate(isStoredResult: false)

        if !decoded.run.isExample {
            problems.append(
                "Benchmarks/example.json: run.id must be \"example\" so it cannot be mistaken for a measurement"
            )
        }
        if decoded != exampleResult() {
            problems.append(
                "Benchmarks/example.json: has drifted from the model — regenerate with --write-example"
            )
        }
    } catch let error as BenchmarkValidationError {
        problems.append("Benchmarks/example.json: \(error.description)")
    } catch {
        problems.append("Benchmarks/example.json: \(error)")
    }
}

// MARK: 3. Stored results

let storedFiles: [String] = {
    guard let walker = FileManager.default.enumerator(atPath: resultsURL.path) else { return [] }
    var found: [String] = []
    for case let relative as String in walker where relative.hasSuffix(".json") {
        found.append(relative)
    }
    return found.sorted()
}()

for relative in storedFiles {
    let url = resultsURL.appendingPathComponent(relative)
    let label = "Benchmarks/results/\(relative)"
    do {
        let data = try Data(contentsOf: url)
        let decoded = try BenchmarkResult.decoder().decode(BenchmarkResult.self, from: data)
        try decoded.validate(isStoredResult: true)
    } catch let error as BenchmarkValidationError {
        problems.append("\(label): \(error.description)")
    } catch {
        problems.append("\(label): \(error)")
    }
}

// MARK: Report

for problem in problems.sorted() {
    print("error: \(problem)")
}

if problems.isEmpty {
    let count = storedFiles.count
    print("bench-guard: schema and example valid, \(count) stored result\(count == 1 ? "" : "s") checked")
    exit(0)
}
exit(1)
