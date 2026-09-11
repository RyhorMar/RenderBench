import BenchHost
import Foundation
import SwiftUI

/// The screen that takes a measurement: what has to hold, what is being measured now, and the file
/// at the end of it.
///
/// The chart is on screen for a reason and not for decoration. These numbers are the cost of
/// drawing to a display that is presenting the frames; a chart measured off screen, or behind
/// another view, is measured in a state the release build is never in.
struct RunScreen: View {
    @State private var scene = ChartScene()
    @State private var runner: BenchmarkRunner?
    @State private var conditions = RunConditions.current()
    @State private var shareURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private let second = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isMeasuring {
                    ChartPane(scene: scene)
                        .frame(height: 220)
                }
                progress
                controls
                preconditionSection
            }
            .padding(12)
        }
        .navigationTitle("Measure")
        .background(AppChrome.page)
        .onAppear(perform: prepare)
        .onDisappear {
            scene.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in scene.isDark = scheme == .dark }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { runner?.interrupted(reason: "the app left the foreground") }
        }
        .onReceive(second) { _ in
            runner?.secondElapsed()
            if isIdle { conditions = RunConditions.current() }
        }
        .sheet(item: $shareURL) { url in ShareSheet(url: url) }
    }

    private var isMeasuring: Bool {
        switch runner?.phase {
        case .warmup, .measuring: true
        default: false
        }
    }

    private var isIdle: Bool {
        switch runner?.phase {
        case .none, .idle, .blocked: true
        default: false
        }
    }

    @ViewBuilder
    private var progress: some View {
        SectionCard(label: "run") {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(AppFont.sans(13, relativeTo: .callout, weight: .medium))
                    .foregroundStyle(AppChrome.ink)
                if let detail = detail {
                    Text(detail)
                        .font(AppFont.sans(11, relativeTo: .caption))
                        .foregroundStyle(AppChrome.sub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("run.status")
        }
    }

    private var headline: String {
        switch runner?.phase {
        case .warmup(let backend, _): "Warming up · \(backend)"
        case .measuring(let backend, _): "Measuring · \(backend)"
        case .cooling(let left): "Cooling down · \(left) s"
        case .awaitingRelaunch(let done, let total): "Repeat \(done) of \(total) done"
        case .wrote(let file): "Written · \(file)"
        case .abandoned(let reason): "Abandoned · \(reason)"
        case .blocked: "Blocked"
        default: "Not started"
        }
    }

    private var detail: String? {
        switch runner?.phase {
        case .warmup(_, let left): "\(left) frames to discard"
        case .measuring(_, let left): "\(left) frames to go"
        case .cooling: "the chart is stopped so the device can cool"
        case .awaitingRelaunch:
            "quit the app and open it again — a repeat that reuses a warm process measures the process"
        case .wrote: "in Files, under this app's folder"
        default: nil
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch runner?.phase {
        case .awaitingRelaunch:
            EmptyView()
        case .wrote(let file):
            Button("Share \(file)") { shareURL = FileRunStorage()?.directory.appendingPathComponent(file) }
                .accessibilityIdentifier("run.share")
        default:
            RunButton(title: startTitle, preconditions: rows) { start() }
                .accessibilityIdentifier("run.start")
        }
    }

    private var startTitle: String {
        runner?.resumable == nil ? "Measure every backend, three times" : "Continue the run in progress"
    }

    private var preconditionSection: some View {
        SectionCard(label: "before anything is measured") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    PreconditionRow(precondition: row)
                }
            }
        }
    }

    private var rows: [Precondition] { RunPreconditions.list(for: conditions) }

    private func prepare() {
        UIApplication.shared.isIdleTimerDisabled = true
        conditions = RunConditions.current()
        guard runner == nil, let storage = FileRunStorage() else { return }
        let made = BenchmarkRunner(scene: scene, storage: storage)
        scene.onFrame = { [weak made] in made?.frameDrawn(at: scene.lastFrameTimestamp) }
        runner = made
        if ProcessInfo.processInfo.arguments.contains(RootView.autoStartArgument) { start() }
    }

    private func start() {
        guard let runner else { return }
        if runner.resumable != nil {
            runner.resume()
        } else {
            runner.start(backends: Catalogue.renderers.map(\.id))
        }
    }
}

/// The system share sheet, which is how a JSON file leaves the phone without Xcode.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
