import BenchRuntime
import Foundation
import SwiftUI

/// One file this app has written, as a row.
struct ResultFile: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let bytes: Int
    let written: Date
}

/// What the app has measured, and — when it has measured nothing — what would have to be true for
/// a file to count.
///
/// The rules stay on screen in both states. A screen that shows them only while empty teaches that
/// they were a hurdle to clear rather than the conditions the numbers mean anything under.
struct ResultsScreen: View {
    @State private var files: [ResultFile] = []
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                count
                if files.isEmpty {
                    SectionCard(label: "why") {
                        Text(Self.emptyReason)
                            .font(AppFont.sans(12, relativeTo: .footnote))
                            .foregroundStyle(AppChrome.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    SectionCard(label: "files") {
                        VStack(spacing: 0) {
                            ForEach(files) { file in row(file) }
                        }
                    }
                }
                rules
            }
            .padding(12)
        }
        .navigationTitle("Results")
        .background(AppChrome.page)
        .onAppear { files = Self.load(from: FileRunStorage()?.directory) }
        .sheet(item: $shareURL) { url in ShareSheet(url: url) }
    }

    private var count: some View {
        StatTile(reading: "\(files.count)", label: "files written on this device",
                 provenance: .source("this device's Documents folder"))
            .accessibilityIdentifier("results.count")
    }

    private func row(_ file: ResultFile) -> some View {
        Button {
            shareURL = FileRunStorage()?.directory.appendingPathComponent(file.name)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(AppFont.mono(11, cappedAt: 16))
                        .foregroundStyle(AppChrome.ink)
                    Text("\(file.bytes) bytes · \(file.written.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppFont.sans(11, relativeTo: .caption))
                        .foregroundStyle(AppChrome.sub)
                }
                Spacer(minLength: 8)
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(AppChrome.accent)
            }
            .padding(AppMetrics.Padding.row)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("results.file.\(file.name)")
    }

    private var rules: some View {
        SectionCard(label: "what a file has to satisfy to count") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.storedFileRules, id: \.self) { rule in
                    Text("· " + rule)
                        .font(AppFont.sans(12, relativeTo: .footnote))
                        .foregroundStyle(AppChrome.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    static let emptyReason = """
        Nothing has been measured on this device yet. A file appears here when a run finishes all \
        three repeats — not when the export button on a comparison screen writes what happens to \
        be on screen, which is a valid document and not a measurement.
        """

    /// The same list `bench-guard` enforces, in the same order, so a reader who is refused knows
    /// which line refused them.
    static let storedFileRules = [
        "measured on a device, never a simulator",
        "built in Release",
        "thermal state below serious at both ends of the run",
        "Low Power Mode off, battery at or above \(Int(BenchmarkResult.minimumBatteryLevel * 100)) %",
        "warm-up frames discarded in every case",
        "all \(BenchmarkResult.requiredRepeats) repeats present, each from its own process",
        "no case whose equivalence check failed",
    ]

    /// Which files in a directory this app wrote, newest first.
    ///
    /// Static and taking a directory so a test can put files in a temporary one: a screen that
    /// only reads Documents can be checked by hand and by nothing else.
    static func load(from directory: URL?) -> [ResultFile] {
        guard let directory else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("renderbench-") && $0.pathExtension == "json" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return ResultFile(
                    name: url.lastPathComponent,
                    bytes: values?.fileSize ?? 0,
                    written: values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.written > $1.written }
    }
}
