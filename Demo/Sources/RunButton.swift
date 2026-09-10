import SwiftUI

/// The button that starts a run, and the sentence that says why it cannot.
///
/// A disabled control with no reason beside it is the defect this component exists to prevent: the
/// reader is left to guess which of several conditions failed, and the screen looks broken rather
/// than informative. The reason is not written by the caller either — it is built from the same
/// preconditions the rows above it show, so the two cannot disagree about what is wrong.
struct RunButton: View {
    let title: String
    let preconditions: [Precondition]
    let start: () -> Void

    /// Everything that blocks, in the order it is shown. Unchecked conditions are absent from this
    /// list on purpose: they are not reasons, they are questions, and listing them would report a
    /// blockage that does not exist.
    nonisolated static func blockers(in preconditions: [Precondition]) -> [Precondition] {
        preconditions.filter(\.state.blocksRun)
    }

    /// The sentence under a disabled button, or `nil` when nothing blocks.
    ///
    /// It names the failures rather than counting them: "two preconditions fail" tells a reader how
    /// much bad news there is and nothing about what to do next.
    nonisolated static func reason(for preconditions: [Precondition]) -> String? {
        let blocking = blockers(in: preconditions)
        guard blocking.isEmpty == false else { return nil }
        return "blocked: " + blocking.map(\.title.localizedLowercase).joined(separator: " · ")
    }

    private var isBlocked: Bool { Self.blockers(in: preconditions).isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: start) {
                Text(title)
                    .font(AppFont.sans(14, relativeTo: .subheadline, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .disabled(isBlocked)
            .foregroundStyle(isBlocked ? AppChrome.sub : AppChrome.ink)
            .background(isBlocked ? AppChrome.chip : AppChrome.card,
                        in: RoundedRectangle(cornerRadius: AppMetrics.Radius.chart))
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.chart)
                    .strokeBorder(isBlocked ? Color.clear : AppChrome.border, lineWidth: 1)
            )

            if let reason = Self.reason(for: preconditions) {
                ProvenanceChip(provenance: .source(reason))
            }
        }
    }
}
