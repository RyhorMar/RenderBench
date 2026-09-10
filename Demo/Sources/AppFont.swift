import Foundation

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
}
