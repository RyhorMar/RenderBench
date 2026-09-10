import SwiftUI

/// A small uppercase mono label: the eyebrow over a card, and the header over a list section.
///
/// The case change happens here rather than in the strings the call sites pass, so the source text
/// stays a readable phrase and cannot arrive half-shouted from one caller and lowercase from the
/// next. The design draws these in the muted token, which at this size is legal for the same reason
/// the tile's absent value is: they are labels beside content, never the content itself.
struct Eyebrow: View {
    let text: String
    /// 9 for a label inside a card, 10 for a header over a section — both rungs of the app's scale.
    var size: CGFloat = 10

    /// `nonisolated` on purpose: a `View`'s members are main-actor work, and this one is a pure
    /// string transform. Leaving it isolated would mean the only rule this component has could be
    /// checked only from the main actor — the same trap the number tile fell into.
    nonisolated static func rendered(_ text: String) -> String { text.uppercased() }

    var body: some View {
        Text(Self.rendered(text))
            .font(AppFont.mono(size, cappedAt: 15))
            .tracking(size * AppMetrics.TypeScale.eyebrowTracking)
            .foregroundStyle(AppChrome.sub)
    }
}

/// The header over a group of rows: the same label, with the spacing a list section needs.
struct SectionHeading: View {
    let text: String

    var body: some View {
        Eyebrow(text: text)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The container everything on these screens sits in: card ground, hairline edge, the card radius
/// and the card padding, with an optional eyebrow above its content.
///
/// A container rather than a modifier because the eyebrow belongs to it: a card whose label is
/// applied by the caller is a card whose label drifts — different spacing above one, a different
/// size on the next.
struct SectionCard<Content: View>: View {
    let label: String?
    @ViewBuilder let content: Content

    init(label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Eyebrow(text: label, size: 9)
                    .padding(.bottom, 5)
            }
            content
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

/// A card's body text: the one sentence under a label. Scales without a ceiling — it wraps, and a
/// reader who asked for larger text wants this larger.
struct CardBody: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.sans(13, relativeTo: .callout))
            .foregroundStyle(AppChrome.sub2)
            .lineSpacing(13 * 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
