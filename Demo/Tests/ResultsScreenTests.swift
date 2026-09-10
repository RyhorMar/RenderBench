import BenchRuntime
import Foundation
import Testing
@testable import RenderBenchDemo

@MainActor
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("results-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The listing shows the app's own result files and nothing else.
///
/// The plan a run in progress keeps lives in the same directory, and so does whatever else the
/// system leaves there. A listing that showed the plan would offer a half-finished run as a
/// result.
@MainActor
@Test
func onlyResultFilesAreListed() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in ["renderbench-run-2.json", "renderbench-1.json", "run-plan.json", "notes.txt"] {
        try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
    }

    let listed = ResultsScreen.load(from: directory).map(\.name)
    #expect(Set(listed) == ["renderbench-run-2.json", "renderbench-1.json"])
}

/// Newest first, because the file a reader wants is almost always the one just written.
@MainActor
@Test
func filesAreListedNewestFirst() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let old = directory.appendingPathComponent("renderbench-old.json")
    let new = directory.appendingPathComponent("renderbench-new.json")
    try Data("{}".utf8).write(to: old)
    try Data("{}".utf8).write(to: new)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: new.path
    )

    #expect(ResultsScreen.load(from: directory).map(\.name) == ["renderbench-new.json", "renderbench-old.json"])
}

/// A directory that does not exist is empty, not a crash.
@MainActor
@Test
func anAbsentDirectoryListsNothing() {
    #expect(ResultsScreen.load(from: nil).isEmpty)
    #expect(ResultsScreen.load(from: URL(fileURLWithPath: "/no/such/place")).isEmpty)
}

/// The rules on screen are the rules the guard enforces, not a second copy that can drift.
///
/// Both numbers in that list come from `BenchmarkResult` itself, so a change to the battery floor
/// or the repeat count reaches the screen without anybody remembering to edit it.
@MainActor
@Test
func theRulesOnScreenQuoteTheGuardsOwnNumbers() {
    let text = ResultsScreen.storedFileRules.joined(separator: " ")
    #expect(text.contains("\(Int(BenchmarkResult.minimumBatteryLevel * 100)) %"))
    #expect(text.contains("all \(BenchmarkResult.requiredRepeats) repeats"))
    #expect(ResultsScreen.storedFileRules.count == 7)
}
