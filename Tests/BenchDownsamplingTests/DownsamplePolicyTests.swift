import Testing
@testable import BenchDownsampling

/// Policy names are written into benchmark result files and read back by the comparison script.
/// Renaming a case silently invalidates every stored run, so the spelling is pinned by a test.
@Test
func policyRawValuesArePartOfTheResultFormat() {
    #expect(DownsamplePolicy.minMax.rawValue == "minMax")
    #expect(DownsamplePolicy.lttb.rawValue == "lttb")
    #expect(DownsamplePolicy.none.rawValue == "none")
    #expect(DownsamplePolicy.allCases.count == 3)
}
