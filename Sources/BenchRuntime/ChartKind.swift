import Foundation

/// Identifies a chart type without closing the set.
///
/// A closed `enum` over the catalogue would make every new chart type a source-breaking change
/// for anyone who switched over it exhaustively, and would stop a consumer adding a type of
/// their own without forking. The cost is that an unknown raw value is representable; backends
/// answer that by reporting no capability for it rather than by trapping.
public struct ChartKind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The reference chart: a multi-series running strip chart. Every backend implements this
    /// one first, because a comparison across backends is only meaningful on identical work.
    public static let stripChart = ChartKind(rawValue: "strip-chart")
}

/// A measured limit for one backend on one chart kind.
///
/// Deliberately not a boolean. "Supports strip charts" is true of every backend here and useless
/// precisely where the reader needs help: the interesting question is how many points survive at
/// what refresh rate, and on which device. A capability without a device and a date is a rumour,
/// so both are required fields rather than optional context.
public struct Capability: Sendable, Codable, Equatable {
    public let kind: ChartKind
    /// Largest point count that held the frame budget in the run this was taken from.
    public let maxPoints: Int
    /// Refresh rate the limit was measured at, in hertz. A 120 Hz limit is not a 60 Hz limit.
    public let refreshHz: Int
    /// Device model the measurement came from, as reported by the run metadata.
    public let device: String
    /// When the measurement was taken. Silicon and OS both move; an old number is a hypothesis.
    public let measuredAt: Date

    public init(kind: ChartKind, maxPoints: Int, refreshHz: Int, device: String, measuredAt: Date) {
        self.kind = kind
        self.maxPoints = maxPoints
        self.refreshHz = refreshHz
        self.device = device
        self.measuredAt = measuredAt
    }
}
