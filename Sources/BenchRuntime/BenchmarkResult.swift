import BenchCore
import BenchDownsampling
import Foundation

/// Why a stored result must be rejected.
///
/// Separate from `DecodingError` so a caller can tell "this file is not a result" from "this file
/// is a result that must not be published".
public enum BenchmarkValidationError: Error, Equatable, CustomStringConvertible {
    case missingField(String)
    case measuredOnSimulator
    case notReleaseConfiguration(BuildConfiguration)
    case thermallyThrottled(ThermalState)
    case lowPowerModeEnabled
    case batteryTooLow(Double)
    case exampleInResultsDirectory(runID: String)
    case equivalenceFailed(backend: String)
    case noCases
    case counterReportedAsZero(field: String, backend: String)

    public var description: String {
        switch self {
        case .missingField(let name):
            "required field \(name) is missing or empty"
        case .measuredOnSimulator:
            "measured on a simulator, where Metal is translated and there is no thermal envelope"
        case .notReleaseConfiguration(let configuration):
            "measured in \(configuration.rawValue); a debug build measures the compiler's bookkeeping"
        case .thermallyThrottled(let state):
            "thermal state reached \(state.rawValue); the run is invalid, not slow"
        case .lowPowerModeEnabled:
            "Low Power Mode was on, which caps the clocks the run was measuring"
        case .batteryTooLow(let level):
            "battery was at \(Int(level * 100))%, below the 40% floor the procedure requires"
        case .exampleInResultsDirectory(let runID):
            "run \(runID) is marked as an example and must not sit among measured results"
        case .equivalenceFailed(let backend):
            "\(backend) failed the equivalence check, so its timings are not comparable"
        case .noCases:
            "contains no cases, so it measures nothing"
        case .counterReportedAsZero(let field, let backend):
            "\(backend) reported \(field) as 0; a counter a backend cannot know is absent, never zero"
        }
    }
}

extension ThermalState {
    /// Ordering, so "at least serious" is expressible.
    var severity: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }

    /// At or beyond the point where the system throttles.
    ///
    /// A run that reached this did not measure a slow method; it measured a throttled machine, and
    /// the two are not the same finding.
    public var isThrottled: Bool { severity >= ThermalState.serious.severity }
}

/// Thermal state at a point in a run.
///
/// Mirrors `ProcessInfo.ThermalState` as a stable string rather than storing the platform enum's
/// integer: a results file outlives the SDK it was written with.
public enum ThermalState: String, Codable, Sendable, CaseIterable {
    case nominal, fair, serious, critical
}

/// Build configuration a run was measured in.
public enum BuildConfiguration: String, Codable, Sendable {
    case debug, release
}

/// Identity of the run: what code produced these numbers, and when.
public struct RunMetadata: Codable, Sendable, Equatable {
    /// Unique id. The literal `example` marks a fabricated shape illustration; a file carrying it
    /// is refused under `Benchmarks/results/`.
    public var id: String
    public var startedAt: Date
    /// Commit the measured binary was built from. Required, and `unknown` is not accepted: a
    /// number that cannot be traced to a revision is not evidence of anything.
    public var gitSha: String
    /// Whether the working tree had uncommitted changes. A dirty run is recorded, not refused —
    /// but the reader gets to know.
    public var gitDirty: Bool
    public var configuration: BuildConfiguration
    public var swiftVersion: String
    public var xcodeVersion: String?

    public init(
        id: String,
        startedAt: Date,
        gitSha: String,
        gitDirty: Bool,
        configuration: BuildConfiguration,
        swiftVersion: String,
        xcodeVersion: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.gitSha = gitSha
        self.gitDirty = gitDirty
        self.configuration = configuration
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
    }

    /// Decoding rejects a missing or empty required field, so "absent" and "blank" are one error
    /// rather than two behaviours.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        gitSha = try container.decode(String.self, forKey: .gitSha)
        gitDirty = try container.decode(Bool.self, forKey: .gitDirty)
        configuration = try container.decode(BuildConfiguration.self, forKey: .configuration)
        swiftVersion = try container.decode(String.self, forKey: .swiftVersion)
        xcodeVersion = try container.decodeIfPresent(String.self, forKey: .xcodeVersion)

        try Self.require(id, "run.id")
        try Self.require(gitSha, "run.gitSha")
        try Self.require(swiftVersion, "run.swiftVersion")
        guard gitSha != "unknown" else {
            throw BenchmarkValidationError.missingField("run.gitSha (recorded as \"unknown\")")
        }
    }

    private static func require(_ value: String, _ name: String) throws {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BenchmarkValidationError.missingField(name)
        }
    }

    /// True when this run is the documented shape illustration rather than a measurement.
    public var isExample: Bool { id == "example" }
}

/// The machine, the OS and the conditions. Without these a number is not reproducible and not
/// comparable with anything.
public struct RunEnvironment: Codable, Sendable, Equatable {
    /// Hardware identifier as the kernel reports it, e.g. `iPhone17,1`. Required.
    public var deviceModel: String
    public var osVersion: String
    /// A simulator run is refused at publication: Metal is translated, there is no thermal
    /// envelope and the display is not the device's.
    public var isSimulator: Bool
    public var maximumFramesPerSecond: Int
    /// Required at both ends of the run. A run that begins nominal and ends serious measured two
    /// different machines, and only the pair says so.
    public var thermalStateAtStart: ThermalState
    public var thermalStateAtEnd: ThermalState
    public var lowPowerModeEnabled: Bool
    /// Fraction in `0...1`, or `nil` where the platform does not report it.
    public var batteryLevel: Double?

    public init(
        deviceModel: String,
        osVersion: String,
        isSimulator: Bool,
        maximumFramesPerSecond: Int,
        thermalStateAtStart: ThermalState,
        thermalStateAtEnd: ThermalState,
        lowPowerModeEnabled: Bool,
        batteryLevel: Double? = nil
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.isSimulator = isSimulator
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.thermalStateAtStart = thermalStateAtStart
        self.thermalStateAtEnd = thermalStateAtEnd
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.batteryLevel = batteryLevel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        isSimulator = try container.decode(Bool.self, forKey: .isSimulator)
        maximumFramesPerSecond = try container.decode(Int.self, forKey: .maximumFramesPerSecond)
        thermalStateAtStart = try container.decode(ThermalState.self, forKey: .thermalStateAtStart)
        thermalStateAtEnd = try container.decode(ThermalState.self, forKey: .thermalStateAtEnd)
        lowPowerModeEnabled = try container.decode(Bool.self, forKey: .lowPowerModeEnabled)
        batteryLevel = try container.decodeIfPresent(Double.self, forKey: .batteryLevel)

        guard !deviceModel.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BenchmarkValidationError.missingField("env.deviceModel")
        }
        guard !osVersion.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BenchmarkValidationError.missingField("env.osVersion")
        }
    }
}

/// Whether a backend was shown to draw the same picture as the reference before its timings were
/// compared with anything.
public enum EquivalenceVerdict: String, Codable, Sendable {
    case passed
    case failed
    /// The check exists in the specification and not yet in the code. Recorded as its own value so
    /// "not checked" can never be read as "passed".
    case notChecked
}

/// One measured configuration: a backend, a load, a policy, and what it cost.
public struct BenchmarkCase: Codable, Sendable, Equatable {
    public var chartKind: ChartKind
    /// Backend identifier, e.g. `canvas`.
    public var backend: String
    public var seriesCount: Int
    public var pointsPerSeries: Int
    public var refreshHz: Int
    public var policy: DownsamplePolicy
    /// Frames discarded before measurement began.
    public var warmupFrames: Int
    /// Frames the statistics were computed over.
    public var measuredFrames: Int
    /// Which repeat of this configuration, counting from one. Repeats restart the application.
    public var repeatIndex: Int
    /// Preparation plus geometry building. **Not the frame's cost**: a backend that cannot
    /// observe its own drawing reports none of it here, so this column is comparable between
    /// backends only as a sub-total.
    public var cpu: FrameStatistics
    /// The backend's own rasterisation, where it could time it.
    ///
    /// `nil` for a retained-mode backend, whose tessellation and compositing happen in the render
    /// server in another process — unobservable from here, and therefore absent rather than zero.
    /// Without this column, and without `missedDeadlineRatio`, a row says nothing about whether a
    /// method holds a frame budget.
    public var raster: FrameStatistics?
    /// `nil` on a CPU-only backend, which has no GPU interval to report. Never zero.
    public var gpu: FrameStatistics?
    /// `nil` when nothing in the run could observe presentation.
    public var missedDeadlineRatio: Double?
    public var pointsSubmitted: Int
    /// `nil` where the backend cannot know how many points reached the raster — six of the nine
    /// cannot. Never zero: a zero here reads as "drew nothing", which wins every comparison it
    /// appears in, and it is not what "cannot report" means.
    public var pointsDrawn: Int?
    /// `nil` where the backend cannot count its own draw calls. Never zero: a drawn frame issued
    /// at least one.
    public var drawCalls: Int?
    public var equivalence: EquivalenceVerdict

    public init(
        chartKind: ChartKind,
        backend: String,
        seriesCount: Int,
        pointsPerSeries: Int,
        refreshHz: Int,
        policy: DownsamplePolicy,
        warmupFrames: Int,
        measuredFrames: Int,
        repeatIndex: Int,
        cpu: FrameStatistics,
        raster: FrameStatistics? = nil,
        gpu: FrameStatistics? = nil,
        missedDeadlineRatio: Double? = nil,
        pointsSubmitted: Int,
        // No `= nil` default, unlike `raster` and `gpu` above. Those are absent for whole classes
        // of backend and defaulting them costs nothing; these two are absent per backend, and a
        // default would let a backend that *can* count silently stop reporting.
        pointsDrawn: Int?,
        drawCalls: Int?,
        equivalence: EquivalenceVerdict = .notChecked
    ) {
        self.chartKind = chartKind
        self.backend = backend
        self.seriesCount = seriesCount
        self.pointsPerSeries = pointsPerSeries
        self.refreshHz = refreshHz
        self.policy = policy
        self.warmupFrames = warmupFrames
        self.measuredFrames = measuredFrames
        self.repeatIndex = repeatIndex
        self.cpu = cpu
        self.raster = raster
        self.gpu = gpu
        self.missedDeadlineRatio = missedDeadlineRatio
        self.pointsSubmitted = pointsSubmitted
        self.pointsDrawn = pointsDrawn
        self.drawCalls = drawCalls
        self.equivalence = equivalence
    }
}

/// One benchmark run, as it is stored under `Benchmarks/results/`.
///
/// The format is deliberately verbose about conditions and terse about numbers. A percentile takes
/// one line; establishing that the percentile means anything takes a dozen.
///
/// - SeeAlso: Docs/methods/frame-statistics.md
public struct BenchmarkResult: Codable, Sendable, Equatable {
    public var run: RunMetadata
    public var env: RunEnvironment
    public var cases: [BenchmarkCase]

    public init(run: RunMetadata, env: RunEnvironment, cases: [BenchmarkCase]) {
        self.run = run
        self.env = env
        self.cases = cases
    }

    /// Checks the conditions that decoding cannot: a result may be well-formed and still unfit to
    /// publish.
    ///
    /// The conditions are the same ones the procedure in `Benchmarks/README.md` calls hard stops.
    /// The runner refuses to *start* when they do not hold; this refuses to *store* a file that
    /// says they did not — because a methodology enforced only at one end is enforced nowhere, and
    /// a document listing preconditions that nothing checks is the defect this project exists to
    /// avoid publishing.
    ///
    /// - Parameter isStoredResult: `true` when the file sits under `Benchmarks/results/`, where the
    ///   conditions apply. `false` when validating the documented example, which is a shape
    ///   illustration and is only checked for shape.
    public func validate(isStoredResult: Bool) throws(BenchmarkValidationError) {
        guard !cases.isEmpty else { throw .noCases }
        for element in cases where element.equivalence == .failed {
            throw .equivalenceFailed(backend: element.backend)
        }
        // Checked on the example too, not only on stored results: the example is what a reader
        // copies, and an example carrying a zero would teach the wrong shape.
        for element in cases {
            if element.drawCalls == 0 {
                throw .counterReportedAsZero(field: "drawCalls", backend: element.backend)
            }
            if element.pointsDrawn == 0, element.pointsSubmitted > 0 {
                throw .counterReportedAsZero(field: "pointsDrawn", backend: element.backend)
            }
        }
        guard isStoredResult else { return }

        guard !run.isExample else { throw .exampleInResultsDirectory(runID: run.id) }
        guard !env.isSimulator else { throw .measuredOnSimulator }
        guard run.configuration == .release else {
            throw .notReleaseConfiguration(run.configuration)
        }
        // Both ends, because a run that began nominal and ended serious was throttled partway and
        // its percentiles describe two different machines.
        for state in [env.thermalStateAtStart, env.thermalStateAtEnd] where state.isThrottled {
            throw .thermallyThrottled(state)
        }
        guard !env.lowPowerModeEnabled else { throw .lowPowerModeEnabled }
        if let level = env.batteryLevel, level < Self.minimumBatteryLevel {
            throw .batteryTooLow(level)
        }
    }

    /// Battery floor the procedure requires. Below it the system begins making its own decisions
    /// about clocks, and the run measures those instead.
    public static let minimumBatteryLevel = 0.4

    /// Canonical on-disk encoding: sorted keys and ISO-8601 dates, so two runs of the same shape
    /// produce diffable files.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension ThermalState {
    /// Maps the platform's thermal state onto the stored vocabulary.
    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default:
            // A state this build does not know is not nominal. Guessing downward would let a run
            // measured on a throttled device pass the precondition that exists to catch it.
            self = .critical
        }
    }
}

extension RunEnvironment {
    /// Captures everything about the machine that Foundation can see.
    ///
    /// The two values it cannot see are parameters: the display's maximum refresh rate and the
    /// battery level both come from UIKit, which this module is not allowed to import. Keeping the
    /// rest here rather than in the application means the next backend does not reimplement it —
    /// and get it subtly different.
    ///
    /// - Parameters:
    ///   - maximumFramesPerSecond: From `UIScreen.maximumFramesPerSecond`.
    ///   - batteryLevel: From `UIDevice.batteryLevel`, or `nil` where monitoring is off.
    ///   - thermalStateAtStart: Captured when the run began, not now. A run's thermal state at its
    ///     start is not recoverable afterwards, and the pair is the whole point.
    public static func current(
        maximumFramesPerSecond: Int,
        batteryLevel: Double?,
        thermalStateAtStart: ThermalState
    ) -> RunEnvironment {
        RunEnvironment(
            deviceModel: hardwareIdentifier(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isSimulator: isRunningOnSimulator,
            maximumFramesPerSecond: maximumFramesPerSecond,
            thermalStateAtStart: thermalStateAtStart,
            thermalStateAtEnd: ThermalState(ProcessInfo.processInfo.thermalState),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: batteryLevel
        )
    }

    /// True when this build is running on a simulator.
    public static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Hardware identifier as the kernel reports it, e.g. `iPhone17,1`.
    ///
    /// A marketing name is ambiguous across regions and storage tiers, so the identifier is stored
    /// instead. On a simulator `uname` reports the host architecture, which says nothing about the
    /// device being emulated; the simulator's own environment variable is used there so the file
    /// still records what was being pretended.
    public static func hardwareIdentifier() -> String {
        if isRunningOnSimulator,
           let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return "\(simulated) (simulator)"
        }
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }
}
