import BenchCore
import BenchHost
import SwiftUI

/// The nine backends as a scrolling row of chips, one chip per backend, each carrying its whole
/// name.
///
/// Replaces a nine-segment `Picker`. A segmented control divides the width it is given, so on a
/// 393 pt screen each segment held about 40 pt — enough for "Metal", not enough for "Core
/// Animation", and a segmented control's answer to that is to truncate the label rather than to
/// admit it does not fit. Nine names that cannot be read do not identify nine methods. A row that
/// scrolls gives every name its own width and pays for it in a gesture instead of in legibility.
///
/// The dot is the rasteriser family and never the method: three colours distinguish three families,
/// and which of the nine methods a chip names is carried by the name beside it.
struct BackendChipRow: View {
    let rows: [CatalogueRow]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(rows) { row in
                    BackendChip(row: row, isSelected: row.id == selection) { selection = row.id }
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityIdentifier("compare.backends")
    }

}

/// One backend's chip: the family dot and the whole name.
///
/// A view of its own so that its width can be measured — the claim that no name is cut is a claim
/// about this view's intrinsic width against the width its text needs, and a chip buried inside a
/// scrolling row cannot be asked for either.
struct BackendChip: View {
    let row: CatalogueRow
    let isSelected: Bool
    let onTap: () -> Void

    /// Point size of the name. Held here because the test that proves the name is not cut has to
    /// measure the text at the size the chip actually draws it.
    static let nameSize: CGFloat = 12

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: AppMetrics.Radius.dot)
                    .fill(colour)
                    .frame(width: 9, height: 9)
                Text(row.entry.descriptor.displayName)
                    .font(AppFont.sans(Self.nameSize, relativeTo: .footnote,
                                       weight: isSelected ? .medium : .regular))
                    // The whole point of the row: a name that would not fit takes the width it
                    // needs and the row scrolls, rather than being cut to fit a share of a picker.
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isSelected ? AppChrome.ink : AppChrome.sub2)
            }
            .padding(AppMetrics.Padding.controlChip)
            .background(AppChrome.card, in: RoundedRectangle(cornerRadius: AppMetrics.Radius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.Radius.chip)
                    .strokeBorder(isSelected ? AppChrome.accent : AppChrome.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compare.backend.\(row.id)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var colour: Color {
        let encoded = Palette.colour(for: row.family).encodedSRGB
        return Color(.sRGB, red: encoded.red, green: encoded.green, blue: encoded.blue)
    }
}
