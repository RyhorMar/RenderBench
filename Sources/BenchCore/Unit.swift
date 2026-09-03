/// What a unit measures. Extensible for the same reason chart kinds are: a consumer adding a
/// quantity should not have to fork the package.
public struct Quantity: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pressure = Quantity(rawValue: "pressure")
    public static let temperature = Quantity(rawValue: "temperature")
    public static let volumetricRate = Quantity(rawValue: "volumetric-rate")
    public static let dimensionless = Quantity(rawValue: "dimensionless")
    public static let concentration = Quantity(rawValue: "concentration")
}

/// A unit of measurement, defined affinely against the quantity's base unit.
///
/// Affine and not multiplicative, because the two conversions that matter most in this domain
/// both carry an offset: psig to psia is a shift of 14.696, and Celsius to Fahrenheit has both a
/// scale and a shift. A purely multiplicative model gets both wrong and gets them wrong quietly.
///
/// `value_in_base = value * scale + offset`
public struct Unit: Sendable, Hashable, Codable {
    /// Symbol as it appears on an axis label: `psig`, `°C`, `m³/d`.
    public let symbol: String
    /// What this unit measures. Conversions across quantities are refused, not scaled.
    public let quantity: Quantity
    /// Multiplier towards the quantity's base unit.
    public let scale: Double
    /// Additive term towards the quantity's base unit, applied after `scale`.
    public let offset: Double
    /// False for quantities whose average is not the average of the thing they describe — API
    /// gravity, ratios taken on mass. Downsampling such a series throws rather than lying.
    public let isAveragable: Bool

    public init(
        symbol: String,
        quantity: Quantity,
        scale: Double,
        offset: Double,
        isAveragable: Bool = true
    ) {
        self.symbol = symbol
        self.quantity = quantity
        self.scale = scale
        self.offset = offset
        self.isAveragable = isAveragable
    }

    /// Converts `value` from this unit into `target`.
    ///
    /// - Throws: ``ChartError/incompatibleUnits(from:to:)`` when the units measure different
    ///   quantities. This is the check that stops a pressure being rendered on a temperature axis.
    public func convert(_ value: Double, to target: Unit) throws(ChartError) -> Double {
        guard quantity == target.quantity else {
            throw ChartError.incompatibleUnits(from: self, to: target)
        }
        let base = value * scale + offset
        return (base - target.offset) / target.scale
    }
}

extension Unit {
    /// Base unit of pressure here: absolute pounds per square inch.
    public static let psia = Unit(symbol: "psia", quantity: .pressure, scale: 1, offset: 0)
    /// Gauge pressure — the same scale shifted by one standard atmosphere.
    public static let psig = Unit(symbol: "psig", quantity: .pressure, scale: 1, offset: 14.696)
    public static let bar = Unit(symbol: "bar", quantity: .pressure, scale: 14.503_773_773_022_1, offset: 0)

    /// Base unit of temperature here: degrees Celsius.
    public static let celsius = Unit(symbol: "°C", quantity: .temperature, scale: 1, offset: 0)
    public static let fahrenheit = Unit(
        symbol: "°F",
        quantity: .temperature,
        scale: 5.0 / 9.0,
        offset: -32.0 * 5.0 / 9.0
    )

    public static let cubicMetresPerDay = Unit(symbol: "m³/d", quantity: .volumetricRate, scale: 1, offset: 0)
    public static let fraction = Unit(symbol: "", quantity: .dimensionless, scale: 1, offset: 0)
    public static let molesPerLitre = Unit(symbol: "mol/L", quantity: .concentration, scale: 1, offset: 0)
}
