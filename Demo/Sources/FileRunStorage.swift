import BenchRuntime
import Foundation

/// The real storage: a plan and a result file in Documents, which is what the Files app shows.
@MainActor
struct FileRunStorage: RunStorage {
    let directory: URL

    init?() {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        directory = documents
    }

    init(directory: URL) { self.directory = directory }

    func loadPlan() -> RunPlan? {
        guard let data = try? Data(contentsOf: RunPlan.fileURL(in: directory)) else { return nil }
        return try? BenchmarkResult.decoder().decode(RunPlan.self, from: data)
    }

    func save(_ plan: RunPlan) {
        guard let data = try? BenchmarkResult.encoder().encode(plan) else { return }
        try? data.write(to: RunPlan.fileURL(in: directory))
    }

    func discardPlan() {
        try? FileManager.default.removeItem(at: RunPlan.fileURL(in: directory))
    }

    func write(_ result: BenchmarkResult) -> String? {
        let name = "renderbench-run-\(Int(result.run.startedAt.timeIntervalSince1970)).json"
        guard let data = try? BenchmarkResult.encoder().encode(result) else { return nil }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }
}
