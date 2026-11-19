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

    /// Every edge gets the same drawing: extension lines, one unbroken dimension line
    /// with arrowheads inside it, and the text just past the line away from the edge.
    @Test func longEdgeDrawsOneLineWithTextPastIt() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 100, y: 0),
            placement: CGPoint(x: 50, y: -40),
            textHalfHeight: 10
        ))

        expectClose(layout.textCenter, CGPoint(x: 50, y: -40))
        #expect(abs(layout.textAngle) < 0.001)
        #expect(layout.extensions.count == 2)
        #expect(layout.arrows.count == 2)
        #expect(layout.shafts.count == 1)

        // Line sits text half-height + overshoot + 2 below the text center.
        expectClose(layout.arrows[0].tip, CGPoint(x: 0, y: -24))
        expectClose(layout.arrows[1].tip, CGPoint(x: 100, y: -24))
        expectClose(layout.shafts[0].start, layout.arrows[0].tip)
        expectClose(layout.shafts[0].end, layout.arrows[1].tip)
        // Wings sit inward of an outward-pointing arrow.
        #expect(layout.arrows[0].upper.x > layout.arrows[0].tip.x)
        #expect(layout.arrows[1].upper.x < layout.arrows[1].tip.x)

        // Extension lines leave the edge and stop below the text.
        #expect(abs(layout.extensions[0].start.x) < 0.01)
        #expect(layout.extensions[0].start.y < 0)
        #expect(layout.extensions[0].end.y < layout.arrows[0].tip.y)
        #expect(layout.extensions[0].end.y > layout.textCenter.y + 10)
    }

    /// Dragging to the other side of the edge flips the dimension with it.
    @Test func placementOnTheOtherSideFlipsTheDimension() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 80, y: 0),
            placement: CGPoint(x: 40, y: 40),
            textHalfHeight: 10
        ))
        expectClose(layout.textCenter, CGPoint(x: 40, y: 40))
        #expect(layout.extensions[0].end.y > layout.extensions[0].start.y)
    }

    /// A short edge looks the same as a long one: arrows stay inside, just smaller.
    @Test func shortEdgeKeepsArrowsInsideAndShrinksThem() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 16, y: 0),
            placement: CGPoint(x: 8, y: -40),
            textHalfHeight: 10
        ))
        #expect(layout.shafts.count == 1)
        #expect(layout.arrows[0].upper.x > layout.arrows[0].tip.x)
        #expect(layout.arrows[1].upper.x < layout.arrows[1].tip.x)
        // Two arrowheads use at most half the line.
        #expect(layout.arrows[0].upper.x - layout.arrows[0].tip.x <= 4.01)
        #expect(layout.arrows[1].tip.x - layout.arrows[1].upper.x <= 4.01)
    }

    /// A placement too close to the edge is pushed out so the text clears the line.
    @Test func closePlacementKeepsMinimumClearance() throws {
        let layout = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 100, y: 0),
            placement: CGPoint(x: 50, y: -5),
            textHalfHeight: 10
        ))
        expectClose(layout.arrows[0].tip, CGPoint(x: 0, y: -DimensionLabelStyle.edgeClearance))
        #expect(layout.textCenter.y + 10 < layout.extensions[0].end.y)
    }

    /// Dropping a label where it rendered must not walk it further out.
    @Test func layoutIsStableWhenFedItsOwnTextCenter() throws {
        let first = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 0, y: 30),
            placement: CGPoint(x: 5, y: 15),
            textHalfHeight: 12
        ))
        let second = try #require(LinearDimensionLayout.layout(
            start: .zero,
            end: CGPoint(x: 0, y: 30),
            placement: first.textCenter,
            textHalfHeight: 12
        ))
        expectClose(second.textCenter, first.textCenter)
        expectClose(second.arrows[0].tip, first.arrows[0].tip)
    }

    /// A quarter-circle's length dimension sits outside the arc, centered on the sweep.
    @Test func arcLengthDimensionSitsOutsideTheMidpoint() throws {
        let layout = try #require(ArcDimensionLayout.layout(
            center: .zero,
            radius: 50,
            startAngle: 0,
            sweep: CGFloat.pi / 2,
            placement: CGPoint(x: 90 * cos(CGFloat.pi / 4), y: 90 * sin(CGFloat.pi / 4)),
            textHalfHeight: 10
        ))
        let expected = 90 * cos(CGFloat.pi / 4)
        expectClose(layout.textCenter, CGPoint(x: expected, y: expected), tolerance: 0.2)
        #expect(layout.extensions.count == 2)
        #expect(layout.arrows.count == 2)
        #expect(layout.arcRuns.count == 1)
        #expect(layout.extensions[0].end.x > layout.extensions[0].start.x)
        #expect(layout.extensions[1].end.y > layout.extensions[1].start.y)
        let tipRadius = hypot(layout.arrows[0].tip.x, layout.arrows[0].tip.y)
        #expect(abs(tipRadius - 74) < 0.2)
    }

    /// A tiny fillet's label sits beyond the dimension arc, and re-placing it is stable.
    @Test func smallArcIsStableWhenFedItsOwnTextCenter() throws {
        let first = try #require(ArcDimensionLayout.layout(
            center: .zero,
            radius: 10,
            startAngle: 0,
            sweep: CGFloat.pi / 2,
            placement: CGPoint(x: 30 * cos(CGFloat.pi / 4), y: 30 * sin(CGFloat.pi / 4)),
            textHalfHeight: 12
        ))
        let textRadius = hypot(first.textCenter.x, first.textCenter.y)
        let tipRadius = hypot(first.arrows[0].tip.x, first.arrows[0].tip.y)
        #expect(textRadius - 12 > tipRadius + 4)

        let second = try #require(ArcDimensionLayout.layout(
            center: .zero,
            radius: 10,
            startAngle: 0,
            sweep: CGFloat.pi / 2,
            placement: first.textCenter,
            textHalfHeight: 12
        ))
        expectClose(second.textCenter, first.textCenter)
    }
}
