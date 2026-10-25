import CoreGraphics
import Testing
@testable import Koala

@MainActor
struct ToolPanelMetricsTests {
    @Test func densityScaleIsOneOnDesignReference() {
        #expect(ToolPanelMetrics.densityScale(longSidePoints: 1180) == 1)
    }

    @Test func densityScaleDoesNotShrinkBelowDesign() {
        // Larger Text / Zoomed packs fewer points — keep design size.
        #expect(ToolPanelMetrics.densityScale(longSidePoints: 1024) == 1)
        #expect(ToolPanelMetrics.densityScale(longSidePoints: 0) == 1)
    }

    @Test func densityScaleGrowsForMoreSpace() {
        // 11" Display Zoom "More Space" landscape long side.
        let scale = ToolPanelMetrics.densityScale(longSidePoints: 1366)
        #expect(abs(scale - 1366 / 1180) < 0.0001)
        #expect(scale > 1)
    }

    @Test func commandWidthTracksDensityOnMoreSpace() {
        let longSide: CGFloat = 1366
        let scale = ToolPanelMetrics.densityScale(longSidePoints: longSide)
        let width = (ToolPanelMetrics.commandWidth * scale).rounded()
        #expect(width == (172 * longSide / 1180).rounded())
        #expect(width > ToolPanelMetrics.commandWidth)
    }
}
