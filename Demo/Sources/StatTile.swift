import SwiftUI

/// One number with its name and its provenance, which is the smallest unit this project is willing
/// to show a number in.
///
/// The absent case is the reason it is a type rather than a `VStack` at each call site: a backend
/// that cannot report a figure must produce the word `nil`, and the one substitution that would look
/// harmless — a zero — wins every comparison it appears in.
struct StatTile: View {
    /// `nil` where the backend cannot report this figure. Not a zero, and not an empty string: both
    /// of those read as measurements.
    let reading: String?
    let label: String
    let provenance: Provenance

    /// What the value line says, decided by the app's one absence rule rather than here.
    var text: String { Reading.text(reading) }

    /// Absence is coloured, not just worded, so a reader scanning a column of tiles sees it before
    /// reading it. `sub` clears 3:1 against every ground of both themes, which is the floor that
    /// applies here — the value line is 22 pt, well past the 18 pt where large-text rules begin.
    var isAbsent: Bool { reading == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(AppFont.mono(22, cappedAt: 30))
                .foregroundStyle(isAbsent ? AppChrome.sub : AppChrome.ink)
            Text(label)
                .font(AppFont.sans(12, relativeTo: .footnote))
                .foregroundStyle(AppChrome.sub2)
                .padding(.top, 2)
            ProvenanceChip(provenance: provenance)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppMetrics.Padding.card)
        .background(AppChrome.card, in: RoundedRectangle(cornerRadius: AppMetrics.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.card)
                .strokeBorder(AppChrome.border, lineWidth: 1)
        )
    }
}
