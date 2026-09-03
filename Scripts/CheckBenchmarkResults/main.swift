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
            BenchmarkCase(
                chartKind: .stripChart,
                backend: "canvas",
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
                pointsDrawn: 2_512,
                drawCalls: 8,
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
} catch {
    problems.append("Benchmarks/schema.json: \(error)")
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
