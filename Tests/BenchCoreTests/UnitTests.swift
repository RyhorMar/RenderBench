import Testing
@testable import BenchCore

@Test
func gaugeAndAbsolutePressureDifferByOneAtmosphere() throws {
    let absolute = try SeriesUnit.psig.convert(0, to: .psia)
    #expect(abs(absolute - 14.696) < 1e-9)
}

@Test
func temperatureConversionCarriesBothScaleAndOffset() throws {
    #expect(abs(try SeriesUnit.celsius.convert(100, to: .fahrenheit) - 212) < 1e-9)
    #expect(abs(try SeriesUnit.fahrenheit.convert(-40, to: .celsius) + 40) < 1e-9)
}

@Test
func roundTripDoesNotAccumulateError() throws {
    var value = 3_014.5
    for _ in 0..<100 {
        value = try SeriesUnit.psig.convert(value, to: .bar)
        value = try SeriesUnit.bar.convert(value, to: .psig)
    }
    #expect(abs(value - 3_014.5) < 1e-6)
}

/// The check that stops a pressure being drawn on a temperature axis. Without the quantity tag
/// the conversion is arithmetically valid and physically meaningless.
@Test
func conversionAcrossQuantitiesIsRefused() {
    #expect(throws: ChartError.incompatibleUnits(from: .psig, to: .celsius)) {
        try SeriesUnit.psig.convert(100, to: .celsius)
    }
}

@Test
func axisLabelOmitsTheSuffixForDimensionlessSeries() {
    let pressure = SeriesMetadata(name: "Wellhead pressure", unit: .psig)
    let cut = SeriesMetadata(name: "Water cut", unit: .fraction)
    #expect(pressure.axisLabel == "Wellhead pressure, psig")
    #expect(cut.axisLabel == "Water cut")
}
