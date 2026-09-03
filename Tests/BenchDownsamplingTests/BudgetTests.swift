import BenchCore
import BenchScales
import Foundation
import Testing
@testable import BenchDownsampling

/// The contract nothing asserted before, which is why a gappy slice could emit five times the cap.
private func reduce(
    values: [Double],
    to target: Int,
    policy: DownsamplePolicy
) -> (points: Int, segments: Int) {
    let samples = values.enumerated().map { Sample(carrier: Double($0.offset), value: $0.element) }
    let provider = ArrayProvider([samples], metadata: [SeriesMetadata(name: "s", unit: .fraction)])
    var output: [Sample] = []
    provider.withSeries(0, in: 0...Double(values.count - 1)) { slice in
        try? downsample(
            slice,
            to: target,
            policy: policy,
            xScale: LinearScale(domain: 0...Double(values.count - 1)),
            yScale: LinearScale(domain: -2...2),
            into: &output
        )
    }
    var segments = 0
    var inRun = false
    for value in values {
        if value.isNaN { inRun = false } else if !inRun { segments += 1; inRun = true }
    }
    return (output.filter { !$0.value.isNaN }.count, segments)
}

@Test
func outputNeverExceedsTheTargetOnAnUnbrokenSeries() {
    let values = (0..<5_000).map { sin(Double($0) * 0.03) }
    for policy in [DownsamplePolicy.minMax, .lttb] {
        for target in [2, 17, 100, 400, 1_000] {
            let result = reduce(values: values, to: target, policy: policy)
            #expect(result.points <= target, "\(policy) emitted \(result.points) for target \(target)")
        }
    }
}

/// With more stretches than budget the cap cannot hold — every stretch must contribute a point or
/// the reader loses intervals with no way to know. The bound is then the stretch count, and that
/// is what the doc comment promises.
@Test
func aGappySeriesIsBoundedByItsStretchCount() {
    for gapEvery in [2, 3, 7, 50] {
        var values = (0..<3_000).map { sin(Double($0) * 0.05) }
        for index in stride(from: gapEvery - 1, to: values.count, by: gapEvery) {
            values[index] = .nan
        }
        for policy in [DownsamplePolicy.minMax, .lttb] {
            for target in [50, 128, 400] {
                let result = reduce(values: values, to: target, policy: policy)
                let bound = max(target, result.segments)
                #expect(
                    result.points <= bound,
                    "\(policy) gap 1/\(gapEvery) target \(target): \(result.points) > \(bound)"
                )
            }
        }
    }
}

@Test
func everyStretchContributesAtLeastOnePoint() {
    var values = (0..<600).map { Double($0) }
    for index in stride(from: 5, to: 600, by: 6) { values[index] = .nan }
    let result = reduce(values: values, to: 20, policy: .minMax)
    #expect(result.points >= result.segments)
}

@Test
func aSliceThatIsEntirelyGapsEmitsNothing() {
    let values = [Double](repeating: .nan, count: 200)
    for policy in [DownsamplePolicy.minMax, .lttb, .none] {
        #expect(reduce(values: values, to: 50, policy: policy).points == 0)
    }
}

@Test
func policyNoneKeepsEverySampleWhenThereAreMoreThanTheTarget() {
    let values = (0..<500).map { Double($0) }
    #expect(reduce(values: values, to: 50, policy: .none).points == 500)
}

/// A budget of two has no room for an interior point, so LTTB keeps the endpoints. Emitting the
/// whole stretch instead — the previous behaviour — is what turned the budget into a suggestion.
@Test
func lttbFallsBackToEndpointsRatherThanEverything() {
    var values = (0..<400).map { sin(Double($0)) }
    for index in stride(from: 3, to: 400, by: 4) { values[index] = .nan }
    let result = reduce(values: values, to: 10, policy: .lttb)
    #expect(result.points <= result.segments * 2)
}
