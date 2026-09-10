import SwiftUI

/// One condition a benchmark run depends on, in the three states it can actually be in.
///
/// Three, not two, and the third is the point: "not checked yet" is not "violated". A screen that
/// collapses them either blocks a run that could have gone ahead or, worse, reports a condition as
/// satisfied because nobody looked. The thermal state is the example the design draws — it is read at
/// the start and again at the end, so before a run it is honestly unknown.
enum PreconditionState: Equatable, CaseIterable {
    case held
    case violated
    case notChecked

    /// The mark beside the row, and it differs per state on purpose: colour is never the only thing
    /// that separates them.
    var mark: String {
        switch self {
        case .held: "✓"
        case .violated: "×"
        case .notChecked: "–"
        }
    }

    /// Only a violation stops a run. An unchecked condition is a question, not an answer, and the
    /// screen says so rather than deciding for the reader.
    var blocksRun: Bool { self == .violated }
}

struct Precondition: Equatable {
    let title: String
    /// What the state means here — "running in a simulator", "checked at start and at end".
    let detail: String
    let state: PreconditionState
}

/// A row: mark, title, and the sentence under it.
struct PreconditionRow: View {
    let precondition: Precondition

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(precondition.state.mark)
                .font(AppFont.mono(13, cappedAt: 20))
                .foregroundStyle(colour)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(precondition.title)
                    .font(AppFont.sans(13, relativeTo: .callout, weight: .medium))
                    .foregroundStyle(AppChrome.ink)
                Text(precondition.detail)
                    .font(AppFont.sans(11, relativeTo: .caption))
                    .foregroundStyle(AppChrome.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(AppMetrics.Padding.row)
        .background(AppChrome.card)
    }

    private var colour: Color {
        switch precondition.state {
        case .held: AppChrome.accent
        case .violated: AppChrome.alert
        case .notChecked: AppChrome.sub
        }
    }
}
