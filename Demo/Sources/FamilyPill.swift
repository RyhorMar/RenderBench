import BenchCore
import SwiftUI

/// A backend's rasteriser family: the colour and, always, the name.
///
/// The name is not decoration beside the colour — it is the identifier. Three colours are what fits
/// at this project's separability floor, so colour distinguishes three families and nothing finer;
/// which of the nine methods a card belongs to is carried by its name and number. A pill that showed
/// only the colour would claim a distinction the colour cannot make.
struct FamilyPill: View {
    let family: RasteriserFamily

    /// Spelt out here rather than on `RasteriserFamily` itself: the core names families for code to
    /// switch on, and these are the words the design puts on screen.
    nonisolated static func name(of family: RasteriserFamily) -> String {
        switch family {
        case .sharedRasteriser: "shared rasteriser"
        case .ownPipeline: "own pipeline"
        case .hybrid: "hybrid"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: AppMetrics.Radius.dot)
                .fill(colour)
                .frame(width: 9, height: 9)
            Text(Eyebrow.rendered(Self.name(of: family)))
                .font(AppFont.mono(9, cappedAt: 14))
                .tracking(9 * AppMetrics.TypeScale.eyebrowTracking)
                .foregroundStyle(AppChrome.sub2)
        }
        .padding(EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7))
        .background(AppChrome.chip, in: RoundedRectangle(cornerRadius: AppMetrics.Radius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.Radius.chip)
                .strokeBorder(AppChrome.border, lineWidth: 1)
        )
    }

    private var colour: Color {
        let palette = Palette.colour(for: family)
        let encoded = palette.encodedSRGB
        return Color(.sRGB, red: encoded.red, green: encoded.green, blue: encoded.blue)
    }
}
