/// Facts about the build that only the build itself can know.
///
/// Stamped by `fastlane stamp`, which every build lane runs before compiling. **The committed copy
/// holds placeholders and must stay that way** — a stamped copy in the repository would attribute
/// every later build to one old revision.
///
/// The placeholders are deliberately unusable: `bench-guard` rejects a result whose `gitSha` is
/// `unknown`, so a measurement taken from a build that skipped the stamp cannot be filed as
/// evidence. That is the intended behaviour, not an inconvenience.
enum BuildInfo {
    static let gitSha = "unknown"
    static let gitDirty = true
    static let swiftVersion = "unknown"
    static let xcodeVersion: String? = nil
}
