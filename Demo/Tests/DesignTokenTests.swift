import CoreGraphics
import SwiftUI
import Testing
@testable import RenderBenchDemo

/// The token values, written out here as literals rather than read back from ``AppMetrics``.
///
/// A drifting size is the quietest defect this design can have: nothing crashes, no test that
/// checks behaviour notices, and every screen shifts at once. These tests exist so that changing a
/// token is a deliberate act with two files in the diff.
@Test
func radiiAreTheFourTheDesignAllows() {
    #expect(AppMetrics.Radius.card == 14)
    #expect(AppMetrics.Radius.chip == 6)
    #expect(AppMetrics.Radius.dot == 2)
    #expect(AppMetrics.Radius.chart == 12)
}

@Test
func paddingsMatchTheReferenceScreens() {
    #expect(AppMetrics.Padding.card == EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
    #expect(AppMetrics.Padding.row == EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
    #expect(AppMetrics.Padding.chip == EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
}

/// The ranges the design states for paddings, checked as ranges: a value edited out of its range is
/// no longer the design's, whatever else it may be. Every edge, not one of each pair — an edit that
/// only moves `trailing` is exactly the edit a half-checked range test misses.
///
/// The row is held to the card's ranges because the design states none of its own for a list row,
/// and a row that fell outside the card's range would be a shape the design does not contain either
/// way. That is an assumption, and it is written here rather than implied.
@Test
func paddingsStayInsideTheRangesTheDesignStates() {
    func check(_ insets: EdgeInsets, vertical: ClosedRange<CGFloat>, horizontal: ClosedRange<CGFloat>,
               _ name: String) {
        #expect(vertical.contains(insets.top), "\(name) top is \(insets.top)")
        #expect(vertical.contains(insets.bottom), "\(name) bottom is \(insets.bottom)")
        #expect(horizontal.contains(insets.leading), "\(name) leading is \(insets.leading)")
        #expect(horizontal.contains(insets.trailing), "\(name) trailing is \(insets.trailing)")
    }
    check(AppMetrics.Padding.card, vertical: 10...14, horizontal: 12...16, "card")
    check(AppMetrics.Padding.row, vertical: 10...14, horizontal: 12...16, "row")
    check(AppMetrics.Padding.chip, vertical: 2...3, horizontal: 6...8, "chip")
}

@Test
func theTypeScaleIsTheThirteenSizesThatAppear() {
    #expect(AppMetrics.TypeScale.sizes == [34, 22, 20, 18, 16, 14, 13, 12.5, 12, 11.5, 11, 10, 9])
    #expect(AppMetrics.TypeScale.sizes == AppMetrics.TypeScale.sizes.sorted(by: >))
    #expect(Set(AppMetrics.TypeScale.sizes).count == AppMetrics.TypeScale.sizes.count)
}

/// Named sizes have to be sizes the scale contains, or a screen ends up drawn at a size that
/// appears nowhere in the design.
/// Tracking is a fraction of the size, so it is not a member of the scale and needs its own pin.
@Test
func eyebrowTrackingIsTheValueTheScreensUse() {
    #expect(AppMetrics.TypeScale.eyebrowTracking == 0.12)
}

@Test
func namedSizesComeFromTheScale() {
    #expect(AppMetrics.TypeScale.sizes.contains(AppMetrics.TypeScale.largeTitle))
    #expect(AppMetrics.TypeScale.sizes.contains(AppMetrics.TypeScale.label))
    #expect(AppMetrics.TypeScale.largeTitle == 34)
    #expect(AppMetrics.TypeScale.label == 10)
}
