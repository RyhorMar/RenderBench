import SwiftUI

/// Where a number came from, in the five forms this project allows and no others.
///
/// The rule it exists to keep: no number is shown without one of these beside it. Five rather than
/// four because a counted number — a test total, a registered-renderer count — is neither measured on
/// a device nor unmeasured; forcing it into "not measured" would say something false about a number
/// that is perfectly well known, just not timed.
enum Provenance: Equatable {
    /// A real run on real hardware: device, OS, build configuration, commit.
    ///
    /// Constructible only through ``Run/init(device:os:build:sha:)``, which refuses a blank part and
    /// refuses the unstamped placeholder — a chip is the one place where a fabricated value would be
    /// invisible, because it looks exactly like a real one.
    struct Run: Equatable {
        let device: String
        let os: String
        let build: String
        let sha: String

        /// `nil` when a part is missing or when the build never went through the stamp, which leaves
        /// `BuildInfo.gitSha` as `unknown`. The caller then has to choose another variant on purpose
        /// instead of shipping a chip that claims a measurement nobody can trace.
        init?(device: String, os: String, build: String, sha: String) {
            let parts = [device, os, build, sha].map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.allSatisfy({ !$0.isEmpty }), parts[3] != "unknown" else { return nil }
            self.device = parts[0]
            self.os = parts[1]
            self.build = parts[2]
            self.sha = parts[3]
        }
    }

    case measured(Run)
    /// The literal words, with nothing appended. A pointer to the section that explains why goes
    /// beside the chip, never inside it: a chip that grows an explanation stops being comparable
    /// with the other chips on the page, which is the whole reason it is a fixed vocabulary.
    case notMeasured
    /// Seen, not measured — the simulator being the usual place.
    case observation(environment: String)
    /// A number from a debug build, true until a release build says otherwise.
    case hypothesis
    /// Something a reader can run or open: `swift test`, `git log`, a file name.
    case source(String)

    var text: String {
        switch self {
        case .measured(let run): [run.device, run.os, run.build, run.sha].joined(separator: " · ")
        case .notMeasured: "not measured"
        case .observation(let environment): "observation, not a measurement · \(environment)"
        case .hypothesis: "debug build on host · hypothesis until confirmed in release"
        case .source(let origin): origin
        }
    }
}

/// The chip itself: mono, bordered, on the chip ground.
///
/// Type scales with the reader's setting up to a ceiling, per the project's Dynamic Type decision —
/// a chip that grows without limit pushes the number it belongs to off the row, and the number is
/// what matters.
struct ProvenanceChip: View {
    let provenance: Provenance

    var body: some View {
        Text(provenance.text)
            .font(AppFont.mono(AppMetrics.TypeScale.label, cappedAt: 15))
            .foregroundStyle(AppChrome.sub2)
            .padding(AppMetrics.Padding.chip)
            .background(AppChrome.chip, in: RoundedRectangle(cornerRadius: AppMetrics.Radius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.chip)
                    .strokeBorder(AppChrome.border, lineWidth: 1)
            )
    }
}
