import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct LinearDimensionLayoutTests {
    private func expectClose(
        _ a: CGPoint,
        _ b: CGPoint,
        tolerance: CGFloat = 0.01,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(a.x - b.x) < tolerance, "x: \(a.x) vs \(b.x)", sourceLocation: sourceLocation)
        #expect(abs(a.y - b.y) < tolerance, "y: \(a.y) vs \(b.y)", sourceLocation: sourceLocation)
    }

    /// A long edge gets extension lines from both ends, outward arrows, and the
    /// measurement centered on the dimension line.
    @Test func longEdgePlacesArrowsOutwardAndTextInTheMiddle() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 100, y: 0),
            placement: CGPoint(x: 50, y: -40),
            textGap: 12,
            minimumOffset: 16
        ))

        expectClose(layout.textCenter, CGPoint(x: 50, y: -40))
        #expect(abs(layout.textAngle) < 0.001)
        #expect(layout.extensions.count == 2)
        #expect(layout.arrows.count == 2)
        #expect(layout.shafts.count == 2)

        expectClose(layout.arrows[0].tip, CGPoint(x: 0, y: -40))
        expectClose(layout.arrows[1].tip, CGPoint(x: 100, y: -40))
        // Wings sit inward of an outward-pointing arrow.
        #expect(layout.arrows[0].upper.x > layout.arrows[0].tip.x)
        #expect(layout.arrows[1].upper.x < layout.arrows[1].tip.x)

        // Extension lines leave the edge endpoints and pass the dimension line.
        #expect(abs(layout.extensions[0].start.x) < 0.01)
        #expect(layout.extensions[0].start.y < 0)
        #expect(layout.extensions[0].end.y < layout.arrows[0].tip.y)
        #expect(abs(layout.extensions[1].start.x - 100) < 0.01)
    }

    /// Dragging to the other side of the edge flips the dimension with it.
    @Test func placementOnTheOtherSideFlipsTheDimension() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 80, y: 0),
            placement: CGPoint(x: 40, y: 28),
            textGap: 10,
            minimumOffset: 16
        ))
        expectClose(layout.textCenter, CGPoint(x: 40, y: 28))
        #expect(layout.extensions[0].end.y > layout.extensions[0].start.y)
    }

    /// A short edge moves the arrows outside so they don't swallow the measurement.
    @Test func shortEdgePointsArrowsInward() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 20, y: 0),
            placement: CGPoint(x: 10, y: -30),
            textGap: 30,
            minimumOffset: 16
        ))
        expectClose(layout.textCenter, CGPoint(x: 10, y: -30))
        #expect(layout.arrows[0].upper.x < layout.arrows[0].tip.x)
        #expect(layout.arrows[1].upper.x > layout.arrows[1].tip.x)
    }

    /// A quarter-circle's length dimension sits outside the arc, centered on the sweep.
    @Test func arcLengthDimensionSitsOutsideTheMidpoint() throws {
        let layout = try #require(ArcDimensionLayout.layout(
            center: .zero,
            radius: 50,
            startAngle: 0,
            sweep: CGFloat.pi / 2,
            placement: CGPoint(x: 80 * cos(CGFloat.pi / 4), y: 80 * sin(CGFloat.pi / 4)),
            textGap: 12,
            minimumOffset: 16
        ))
        let expected = 80 * cos(CGFloat.pi / 4)
        expectClose(layout.textCenter, CGPoint(x: expected, y: expected), tolerance: 0.2)
        #expect(layout.extensions.count == 2)
        #expect(layout.arrows.count == 2)
        #expect(layout.arcRuns.count == 2)
        #expect(layout.extensions[0].end.x > layout.extensions[0].start.x)
        #expect(layout.extensions[1].end.y > layout.extensions[1].start.y)
    }
}
