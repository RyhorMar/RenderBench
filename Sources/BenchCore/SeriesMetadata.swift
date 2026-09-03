/// Where a number came from.
///
/// Kept next to the data rather than in a side table because it changes what may be drawn: an
/// allocated rate and a measured one must not share a line style, and interpolated points must
/// not be presented as observations.
public enum Provenance: String, Sendable, Codable, CaseIterable {
    case measured
    case calculated
    case allocated
    case interpolated
}

/// Everything about a series that is not its samples.
public struct SeriesMetadata: Sendable, Equatable, Codable {
    /// Display name, used on the axis and in the accessibility description.
    public var name: String
    /// Unit the values are expressed in.
    public var unit: Unit
    /// Range the instrument can actually report, when known. Values outside it are suspect and
    /// are counted rather than clipped.
    public var validRange: ClosedRange<Double>?
    /// Where the numbers came from.
    public var provenance: Provenance

    public init(
        name: String,
        unit: Unit,
        validRange: ClosedRange<Double>? = nil,
        provenance: Provenance = .measured
    ) {
        self.name = name
        self.unit = unit
        self.validRange = validRange
        self.provenance = provenance
    }

    /// Axis label combining name and unit: `Wellhead pressure, psig`.
    ///
    /// A dimensionless unit contributes no suffix, so a fraction reads as `Water cut` rather than
    /// `Water cut, `.
    public var axisLabel: String {
        unit.symbol.isEmpty ? name : "\(name), \(unit.symbol)"
    }
}
