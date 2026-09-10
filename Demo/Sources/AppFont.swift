import SwiftUI
import UIKit

/// The bundled faces, by the name the font system answers to.
///
/// PostScript names, and they are **not** the file names: the file called
/// `IBMPlexSans-SemiBold.ttf` registers as `IBMPlexSans-SmBld`, and `IBMPlexSans-Regular.ttf`
/// registers as plain `IBMPlexSans`. Read out of the files with Core Text rather than guessed —
/// guessing produces a name `UIFont(name:)` answers with `nil`, and a `nil` there does not fail
/// anything: the label just draws in the system font, which is the failure this project cares about
/// least seeing and most likely to ship.
///
/// Three weights of each family, matching the design: 400 body, 500 numbers, 600 headings. No
/// italics — the design uses none, and each face is 170–200 KB of bundle.
enum AppFont {
    static let sansRegular = "IBMPlexSans"
    static let sansMedium = "IBMPlexSans-Medm"
    static let sansSemiBold = "IBMPlexSans-SmBld"

    static let monoRegular = "IBMPlexMono"
    static let monoMedium = "IBMPlexMono-Medm"
    static let monoSemiBold = "IBMPlexMono-SmBld"

    /// Everything above, for a test that wants to prove each one registered.
    static let all = [sansRegular, sansMedium, sansSemiBold, monoRegular, monoMedium, monoSemiBold]

    /// Family names, which is what a caller asking "is this Plex or the system font?" can check —
    /// a fallback answers with the system family, not with one of these.
    static let sansFamily = "IBM Plex Sans"
    static let monoFamily = "IBM Plex Mono"

    /// A mono face that scales with the reader's setting and stops at `cappedAt`.
    ///
    /// The project's Dynamic Type decision in one place: numbers and mono labels do scale — a
    /// monospaced column stays aligned under scaling, since every cell of a style scales by the same
    /// factor — but they stop growing before they push the row apart. The ceiling is per role and
    /// passed in, because what a row can absorb is a property of the row.
    ///
    /// `scaledValue(for:)` has no ceiling of its own, so the clamp is applied here and the result
    /// asked for as a fixed size: a second scaling pass on an already scaled value would compound.
    static func mono(_ size: CGFloat, cappedAt ceiling: CGFloat, weight: Font.Weight = .medium) -> Font {
        let scaled = min(UIFontMetrics(forTextStyle: .footnote).scaledValue(for: size), ceiling)
        return .custom(monoName(for: weight), fixedSize: scaled)
    }

    /// A text face that scales without a ceiling, mapped to the system style whose rhythm this role
    /// follows. Text may grow as far as the reader asks: it wraps, where a number in a tile does not.
    static func sans(_ size: CGFloat, relativeTo style: Font.TextStyle,
                     weight: Font.Weight = .regular) -> Font {
        .custom(sansName(for: weight), size: size, relativeTo: style)
    }

    static func sansName(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: sansSemiBold
        case .medium: sansMedium
        default: sansRegular
        }
    }

    static func monoName(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: monoSemiBold
        case .regular, .light, .thin, .ultraLight: monoRegular
        default: monoMedium
        }
    }
}
