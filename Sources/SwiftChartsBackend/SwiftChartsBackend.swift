import BenchRuntime
import Foundation

/// Swift Charts backend: SwiftUI's own declarative `Chart` view.
///
/// The first of the nine backends that owns its own layout and axis machinery rather than being
/// handed geometry to stroke. This project's chrome is drawn underneath instead, and `Chart`'s
/// own axes and grid are hidden — see `SwiftChartsChartView` — so that machinery never decides
/// where the plot sits; it only ever places marks inside a rectangle this package already chose.
public enum SwiftChartsBackend {
    /// Stable identifier used in benchmark metadata and in the results files.
    public static let identifier = "swift-charts"

    /// What this backend can do, as measured numbers.
    ///
    /// Empty until a device run fills it. A capability declared before it is measured is a
    /// hypothesis wearing a contract's clothes.
    public static let capabilities: [Capability] = []
}
